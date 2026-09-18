import Flutter
import Foundation
import Otp

/// The iOS half of the bridge: everything that touches the SDK.
///
/// There is no Objective-C++ half here, unlike the React Native bridge: Pigeon generates `OtpHostApi`
/// as a Swift protocol the SDK can be spoken to from directly, because Flutter's plugin channel does
/// not need Objective-C++ codegen the way React Native's does.
///
/// Nothing here holds Dart state. The bridge is stateless by design, so a session is looked up by the
/// verification's id and rebuilt from the API when Dart has been hot restarted out from under it,
/// the same way a JavaScript reload does on the React Native bridge.
/// No isolation of its own, and no `@MainActor` on the presenting entry points either, unlike the
/// React Native bridge. The SDK's own presenting calls are already main actor isolated, so awaiting
/// them from here hops for us; annotating this type as well would only add a boundary the Swift 6
/// language mode then has to be convinced about.
public final class OtpPlugin: NSObject, FlutterPlugin, OtpHostApi {

  public static func register(with registrar: FlutterPluginRegistrar) {
    OtpHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: OtpPlugin())
  }

  private let sessions = Sessions()

  func configure(publishableKey: String, baseUrl: String?) async throws {
    try await answer {
      OtpClient.configure(publishableKey: publishableKey, baseURL: baseUrl.flatMap(URL.init(string:)))
    }
  }

  // MARK: - The presented screens

  func verify(recipient: String, locale: String?) async throws -> VerificationMessage {
    try await answer {
      Self.message(try await OtpClient.verify(recipient: recipient, locale: locale))
    }
  }

  func verifyCollecting(kind: String, locale: String?) async throws -> VerificationMessage {
    try await answer {
      guard let collecting = Self.recipientKind(kind) else {
        throw Refusal("collecting must be \"phone\" or \"email\", not \"\(kind)\"")
      }
      return Self.message(try await OtpClient.verify(collecting: collecting, locale: locale))
    }
  }

  func resumeInterrupted() async throws -> VerificationMessage? {
    try await answer {
      try await OtpClient.resumeInterrupted().map(Self.message)
    }
  }

  // MARK: - The core, for an app drawing its own screens

  func start(recipient: String, locale: String?) async throws -> PendingOtpMessage {
    try await answer {
      let session = OtpSession()
      let pending = try await session.start(recipient: recipient, locale: locale)
      await sessions.remember(session, for: pending.id)
      return Self.message(pending)
    }
  }

  func submit(otpId: String, code: String) async throws -> CodeSubmissionMessage {
    try await answer {
      let id = try Self.uuid(otpId)
      let session = try await sessions.session(for: id)
      let outcome = try await session.submit(code: code)
      if case .verified = outcome {
        await sessions.forget(id)
      }
      return Self.message(outcome)
    }
  }

  func resend(otpId: String, channel: String?) async throws -> PendingOtpMessage {
    try await answer {
      let id = try Self.uuid(otpId)
      let session = try await sessions.session(for: id)
      let requested = try channel.map { name -> OtpChannel in
        guard let known = Self.channel(name) else {
          throw Refusal("\(name) is not a channel this build can name")
        }
        return known
      }
      return Self.message(try await session.resend(preferring: requested))
    }
  }

  func resume(otpId: String) async throws -> PendingOtpMessage {
    try await answer {
      let id = try Self.uuid(otpId)
      let session = OtpSession()
      let pending = try await session.resume(id, locale: OtpClient.interrupted?.locale)
      await sessions.remember(session, for: id)
      return Self.message(pending)
    }
  }

  func interrupted() async throws -> InterruptedMessage? {
    guard let interrupted = OtpClient.interrupted else { return nil }
    return InterruptedMessage(
      otpId: interrupted.otpId.uuidString.lowercased(),
      expiresAt: Self.iso(interrupted.expiresAt),
      locale: interrupted.locale
    )
  }

  // MARK: - Answering a call

  /// Runs the body and turns a thrown error into the one `PigeonError` shape Dart reads back.
  ///
  /// Every method above goes through here, so a failure cannot reach Dart as anything but the
  /// documented rejection.
  private func answer<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let refusal as Refusal {
      throw PigeonError(code: "validationFailed", message: refusal.message, details: nil)
    } catch let error as OtpError {
      throw PigeonError(
        code: Self.code(error.kind),
        message: error.message ?? Self.code(error.kind),
        details: Self.details(error)
      )
    } catch {
      throw PigeonError(code: "unexpected", message: error.localizedDescription, details: nil)
    }
  }

  // MARK: - Crossing the bridge

  /// The kinds, spelled exactly as `OtpErrorKind` in `otp_flutter.dart`. The two lists are one
  /// contract, and a value that does not appear on both sides reaches application code as `unknown`.
  private static func code(_ kind: OtpError.Kind) -> String {
    switch kind {
    case .notConfigured: "notConfigured"
    case .unauthorized: "unauthorized"
    case .deviceProofRejected: "deviceProofRejected"
    case .deviceProofUnsupported: "deviceProofUnsupported"
    case .notFound: "notFound"
    case .conflict: "conflict"
    case .validationFailed: "validationFailed"
    case .rateLimited: "rateLimited"
    case .unavailable: "unavailable"
    case .transport: "transport"
    case .cancelled: "cancelled"
    case .noPresenter: "noPresenter"
    case .unexpected: "unexpected"
    @unknown default: "unknown"
    }
  }

  /// Carries the fields a rejection has nowhere else to put. `otp_flutter.dart` reads this back from
  /// `PlatformException.details` as a map with exactly these keys, unlike React Native's `NSError`
  /// `userInfo`, because that is the shape a Pigeon error's `details` crosses in.
  // `any Sendable` rather than `Any`: PigeonError carries its details as `Sendable?`, and this
  // target builds in the Swift 6 language mode, where a plain `Any` dictionary is not one.
  private static func details(_ error: OtpError) -> [String: any Sendable] {
    var info: [String: any Sendable] = [:]
    if let type = error.type { info["type"] = type }
    if let statusCode = error.statusCode { info["statusCode"] = statusCode }
    if let retryAfter = error.retryAfter { info["retryAfterSeconds"] = retryAfter }
    return info
  }

  private static func message(_ pending: PendingOtp) -> PendingOtpMessage {
    PendingOtpMessage(
      id: pending.id.uuidString.lowercased(),
      status: string(pending.status),
      channel: pending.channel.map(string),
      maskedRecipient: pending.maskedRecipient,
      codeLength: Int64(pending.codeLength),
      expiresAt: iso(pending.expiresAt),
      resendAvailableAt: pending.resendAvailableAt.map(iso),
      handoffUrl: pending.handoffURL?.absoluteString
    )
  }

  private static func message(_ verification: Verification) -> VerificationMessage {
    VerificationMessage(
      otpId: verification.otpId.uuidString.lowercased(),
      token: verification.token,
      tokenExpiresAt: iso(verification.tokenExpiresAt)
    )
  }

  private static func message(_ outcome: CodeSubmission) -> CodeSubmissionMessage {
    switch outcome {
    case .verified(let verification):
      CodeSubmissionMessage(verification: message(verification))
    case .rejected(let attemptsRemaining, let reason):
      CodeSubmissionMessage(
        attemptsRemaining: attemptsRemaining.map(Int64.init),
        reason: string(reason)
      )
    @unknown default:
      CodeSubmissionMessage(reason: "unknown")
    }
  }

  private static func string(_ reason: RejectionReason) -> String {
    switch reason {
    case .incorrectCode: "incorrectCode"
    case .expired: "expired"
    case .noAttemptsLeft: "noAttemptsLeft"
    case .unknown: "unknown"
    @unknown default: "unknown"
    }
  }

  private static func string(_ status: OtpStatus) -> String {
    switch status {
    case .pending: "pending"
    case .approved: "approved"
    case .failed: "failed"
    case .expired: "expired"
    case .unknown: "unknown"
    @unknown default: "unknown"
    }
  }

  private static func string(_ channel: OtpChannel) -> String {
    switch channel {
    case .sms: "sms"
    case .whatsapp: "whatsapp"
    case .email: "email"
    case .telegram: "telegram"
    case .unknown: "unknown"
    @unknown default: "unknown"
    }
  }

  private static func channel(_ name: String) -> OtpChannel? {
    switch name {
    case "sms": .sms
    case "whatsapp": .whatsapp
    case "email": .email
    case "telegram": .telegram
    // Deliberately not `unknown`: a resend has to name a channel the API can act on, and this build
    // cannot name one it does not know.
    default: nil
    }
  }

  private static func recipientKind(_ name: String) -> RecipientKind? {
    switch name {
    case "phone": .phone
    case "email": .email
    default: nil
    }
  }

  /// ISO 8601 with the offset, which is what `DateTime.parse` in Dart parses.
  private static func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  private static func uuid(_ value: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else {
      throw Refusal("\(value) is not a verification id")
    }
    return id
  }
}

/// An argument this bridge refused before the SDK ever saw it.
///
/// Its own type because `OtpError` cannot be built from outside the SDK, which is deliberate: an
/// error carrying the SDK's name should come from the SDK. It crosses as `validationFailed`, the same
/// kind the API returns for a value it will not accept.
private struct Refusal: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}

/// The sessions of verifications that are in flight.
///
/// Dart passes an id on every call and holds no session, so this is where the native half of that
/// mapping lives. An id with no session here is one whose process outlived its Dart half, and it is
/// rebuilt from the API rather than refused.
private actor Sessions {
  private var sessions: [UUID: OtpSession] = [:]

  func session(for id: UUID) async throws -> OtpSession {
    if let existing = sessions[id] { return existing }
    let rebuilt = OtpSession()
    _ = try await rebuilt.resume(id, locale: OtpClient.interrupted?.locale)
    sessions[id] = rebuilt
    return rebuilt
  }

  func remember(_ session: OtpSession, for id: UUID) {
    sessions[id] = session
  }

  func forget(_ id: UUID) {
    sessions.removeValue(forKey: id)
  }
}
