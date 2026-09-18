/// Phone and email verification over the native otp.com SDKs.
///
/// This is the only import a consumer needs. The generated platform channel types in
/// `src/messages.g.dart` are an implementation detail and stay internal to this package.
library;

import 'package:flutter/services.dart';

import 'src/messages.g.dart';

/// Channel a verification was dispatched on.
///
/// Routing gains channels over time and an app already on a phone cannot be updated to match, so
/// adding a case here would break an exhaustive `switch` in every app already built against this
/// package. A channel this build was never told about arrives as [OtpChannel.unknown] instead.
enum OtpChannel { sms, whatsapp, email, telegram, unknown }

/// Where a verification stands.
///
/// See [OtpChannel] for why an unrecognised value arrives as [OtpStatus.unknown] rather than as a
/// new case.
enum OtpStatus { pending, approved, failed, expired, unknown }

/// Why a submitted code was rejected.
enum RejectionReason { incorrectCode, expired, noAttemptsLeft, unknown }

/// Which recipient the SDK should collect, when it collects one.
enum RecipientKind { phone, email }

/// What went wrong, in a form code can branch on.
///
/// [OtpErrorKind.notConfigured], [OtpErrorKind.unauthorized] and [OtpErrorKind.unexpected] are
/// wiring problems: show one honest sentence and put the message in your logs.
/// [OtpErrorKind.rateLimited], [OtpErrorKind.validationFailed], [OtpErrorKind.conflict] and
/// [OtpErrorKind.unavailable] are things the user can act on. [OtpErrorKind.cancelled] means they
/// closed the screen, which is not a failure of anything.
///
/// A kind this build was never told about arrives as [OtpErrorKind.unknown], for the same reason a
/// channel does.
enum OtpErrorKind {
  notConfigured,
  unauthorized,
  deviceProofRejected,
  deviceProofUnsupported,
  notFound,
  conflict,
  validationFailed,
  rateLimited,
  unavailable,
  transport,
  cancelled,
  noPresenter,
  unexpected,
  unknown,
}

/// A verification that has been started and not yet answered. Both deadlines are here, so
/// countdowns run on the device: there is nothing to poll.
final class PendingOtp {
  PendingOtp({
    required this.id,
    required this.status,
    required this.channel,
    required this.maskedRecipient,
    required this.codeLength,
    required this.expiresAt,
    required this.resendAvailableAt,
    required this.handoffUrl,
  });

  final String id;
  final OtpStatus status;

  /// Null until routing has picked a channel.
  final OtpChannel? channel;

  /// The recipient with its middle digits masked. The full recipient never reaches the device.
  final String maskedRecipient;

  /// How many characters the code has, so the input can draw the right number of boxes.
  final int codeLength;

  final DateTime expiresAt;

  /// Null when this verification can no longer be resent at all.
  final DateTime? resendAvailableAt;

  /// WhatsApp only: the link the user opens to be sent the code.
  final String? handoffUrl;
}

/// Proof that a verification succeeded. Send [token] to your own backend, which exchanges it with
/// your server key to learn which recipient was verified. A result read off a device you do not
/// control proves nothing by itself, so the token is the whole security model.
final class Verification {
  Verification({required this.otpId, required this.token, required this.tokenExpiresAt});

  final String otpId;
  final String token;
  final DateTime tokenExpiresAt;
}

/// A verification this install started and has not answered, found again after a restart.
///
/// Only the id and the deadlines, because that is all the device kept. Pass [otpId] to
/// `Otp.resume` to read the verification itself back from the API.
final class InterruptedVerification {
  InterruptedVerification({required this.otpId, required this.expiresAt, required this.locale});

  final String otpId;
  final DateTime expiresAt;

  /// The language the code was sent in. A resumed screen in another one contradicts the message.
  final String? locale;
}

/// What submitting a code produced. A wrong code is an outcome, not an error.
sealed class CodeSubmission {}

/// The code matched.
final class CodeMatched extends CodeSubmission {
  CodeMatched(this.verification);

  final Verification verification;
}

/// The code did not match.
final class CodeRejected extends CodeSubmission {
  CodeRejected({required this.attemptsRemaining, required this.reason});

  /// Set until the verification is resolved, then null.
  final int? attemptsRemaining;
  final RejectionReason reason;
}

/// Every call in this package throws this and nothing else.
class OtpException implements Exception {
  OtpException(this.kind, this.message, {this.type, this.statusCode, this.retryAfterSeconds});

  final OtpErrorKind kind;
  final String message;

  /// The API's own error type, such as `otp_resend_exhausted`. Present only when the API
  /// answered. It is what tells two failures of the same kind apart: a [OtpErrorKind.conflict] is
  /// either a recipient no channel can reach or a verification that can never be resent again.
  final String? type;

  final int? statusCode;

  /// How long to wait, when the API said. Only ever set on [OtpErrorKind.rateLimited].
  final int? retryAfterSeconds;

  @override
  String toString() => 'OtpException(kind: $kind, message: $message)';
}

const List<OtpChannel> _knownChannels = [
  OtpChannel.sms,
  OtpChannel.whatsapp,
  OtpChannel.email,
  OtpChannel.telegram,
];

const List<OtpStatus> _knownStatuses = [
  OtpStatus.pending,
  OtpStatus.approved,
  OtpStatus.failed,
  OtpStatus.expired,
];

const List<RejectionReason> _knownRejectionReasons = [
  RejectionReason.incorrectCode,
  RejectionReason.expired,
  RejectionReason.noAttemptsLeft,
];

const Map<String, OtpErrorKind> _knownErrorKinds = {
  'notConfigured': OtpErrorKind.notConfigured,
  'unauthorized': OtpErrorKind.unauthorized,
  'deviceProofRejected': OtpErrorKind.deviceProofRejected,
  'deviceProofUnsupported': OtpErrorKind.deviceProofUnsupported,
  'notFound': OtpErrorKind.notFound,
  'conflict': OtpErrorKind.conflict,
  'validationFailed': OtpErrorKind.validationFailed,
  'rateLimited': OtpErrorKind.rateLimited,
  'unavailable': OtpErrorKind.unavailable,
  'transport': OtpErrorKind.transport,
  'cancelled': OtpErrorKind.cancelled,
  'noPresenter': OtpErrorKind.noPresenter,
  'unexpected': OtpErrorKind.unexpected,
};

// An unrecognised value becomes `unknown` rather than being passed through. See the doc comments
// on [OtpChannel] and [OtpStatus] for why.
OtpChannel? _toChannel(String? value) {
  if (value == null) return null;
  for (final channel in _knownChannels) {
    if (channel.name == value) return channel;
  }
  return OtpChannel.unknown;
}

OtpStatus _toStatus(String value) {
  for (final status in _knownStatuses) {
    if (status.name == value) return status;
  }
  return OtpStatus.unknown;
}

RejectionReason _toRejectionReason(String? value) {
  if (value == null) return RejectionReason.unknown;
  for (final reason in _knownRejectionReasons) {
    if (reason.name == value) return reason;
  }
  return RejectionReason.unknown;
}

PendingOtp _toPendingOtp(PendingOtpMessage message) => PendingOtp(
  id: message.id,
  status: _toStatus(message.status),
  channel: _toChannel(message.channel),
  maskedRecipient: message.maskedRecipient,
  codeLength: message.codeLength,
  expiresAt: DateTime.parse(message.expiresAt).toUtc(),
  resendAvailableAt: message.resendAvailableAt == null
      ? null
      : DateTime.parse(message.resendAvailableAt!).toUtc(),
  handoffUrl: message.handoffUrl,
);

Verification _toVerification(VerificationMessage message) => Verification(
  otpId: message.otpId,
  token: message.token,
  tokenExpiresAt: DateTime.parse(message.tokenExpiresAt).toUtc(),
);

CodeSubmission _toCodeSubmission(CodeSubmissionMessage message) {
  final verification = message.verification;
  if (verification == null) {
    return CodeRejected(
      attemptsRemaining: message.attemptsRemaining,
      reason: _toRejectionReason(message.reason),
    );
  }
  return CodeMatched(_toVerification(verification));
}

/// Turns whatever the platform channel threw into an [OtpException].
///
/// A failure from the native SDK arrives as a [PlatformException] with `code` and `details`, and a
/// failure from anywhere else arrives as something this package never promised. Both leave here as
/// the one type the published API documents.
OtpException _toOtpException(Object error) {
  if (error is PlatformException) {
    final kind = _knownErrorKinds[error.code] ?? OtpErrorKind.unknown;
    final message = (error.message?.isNotEmpty ?? false) ? error.message! : kind.name;
    final details = error.details;
    final info = details is Map ? details : const <Object?, Object?>{};
    int? asInt(Object? value) => value is int ? value : null;
    String? asString(Object? value) => value is String ? value : null;
    return OtpException(
      kind,
      message,
      type: asString(info['type']),
      statusCode: asInt(info['statusCode']),
      retryAfterSeconds: asInt(info['retryAfterSeconds']),
    );
  }
  return OtpException(OtpErrorKind.unexpected, error.toString());
}

/// Every call goes through here, so nothing but an [OtpException] can leave this package.
Future<T> _calling<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (error) {
    throw _toOtpException(error);
  }
}

final OtpHostApi _host = OtpHostApi();

/// Phone and email verification for Flutter, over the native otp.com SDKs.
abstract final class Otp {
  /// Points the SDK at one app. Call once, before starting a verification.
  ///
  /// The publishable key is designed to sit inside an app binary: it is scoped to a single app and
  /// can only start and answer verifications. It can never read a recipient or exchange a
  /// verification.
  static Future<void> configure({required String publishableKey, String? baseUrl}) =>
      _calling(() => _host.configure(publishableKey, baseUrl));

  /// Runs a verification end to end, presenting the platform's own code screen.
  ///
  /// This is the short way to use the SDK. The screen follows the system light and dark
  /// appearance, is translated into six languages, lays itself out right to left where the
  /// language reads that way, accepts the one-time code the OS offers from the message, and
  /// handles the WhatsApp round trip.
  ///
  /// Throws an [OtpException] of kind [OtpErrorKind.cancelled] if the user closes the screen.
  ///
  /// [recipient] is a phone number in E.164 form, or an email address. The SDK does not collect
  /// it: your own screen already has it, and asking twice is worse than asking once.
  /// [locale] is a BCP-47 locale for the message and for the screen. Defaults to the device's.
  static Future<Verification> verify(String recipient, {String? locale}) async =>
      _toVerification(await _calling(() => _host.verify(recipient, locale)));

  /// Runs a verification end to end, collecting the recipient first.
  ///
  /// Use this when your own flow has no phone or email field yet. If it does, pass the value to
  /// [verify] instead.
  ///
  /// One [kind] per call, not a choice offered to the user: an app collects phone numbers or it
  /// collects email addresses.
  static Future<Verification> verifyCollecting(RecipientKind kind, {String? locale}) async =>
      _toVerification(await _calling(() => _host.verifyCollecting(kind.name, locale)));

  /// Picks up a verification that was left in flight, presenting its code screen.
  ///
  /// Call it when your app resumes. The WhatsApp handoff sends the user to another app to be given
  /// their code, and the OS may kill yours while they are away; without this they come back to a
  /// code they can no longer use anywhere.
  ///
  /// Resolves with null when there was nothing to resume, which includes a verification that has
  /// expired or been answered in the meantime, and when the user closes the screen.
  static Future<Verification?> resumeInterrupted() async {
    final message = await _calling(() => _host.resumeInterrupted());
    return message == null ? null : _toVerification(message);
  }

  /// Starts a verification and has the code delivered, for an app drawing its own screens.
  ///
  /// Everything the screen needs is on the answer, including both deadlines, so countdowns run on
  /// the device and there is nothing to poll.
  static Future<PendingOtp> start(String recipient, {String? locale}) async =>
      _toPendingOtp(await _calling(() => _host.start(recipient, locale)));

  /// Submits the code the user entered.
  static Future<CodeSubmission> submit(String otpId, String code) async =>
      _toCodeSubmission(await _calling(() => _host.submit(otpId, code)));

  /// Sends the code again, moving to the next channel in the app's routing order.
  ///
  /// [channel] names a channel instead of advancing, for when the user says the current one
  /// cannot reach them. It has to be enabled for the app.
  static Future<PendingOtp> resend(String otpId, {OtpChannel? channel}) async {
    // A resend has to name a channel the API can act on: sending "unknown" across would ask the
    // native SDK to act on a value it cannot interpret either. `async` so this surfaces as a failed
    // future like every other refusal, rather than synchronously at the call site.
    if (channel == OtpChannel.unknown) {
      throw OtpException(OtpErrorKind.validationFailed, 'resend cannot target an unknown channel');
    }
    return _toPendingOtp(await _calling(() => _host.resend(otpId, channel?.name)));
  }

  /// Picks a verification back up after the app was killed while the user was away receiving the
  /// code. Its deadlines come back with it, so a screen can rebuild its countdowns.
  ///
  /// This is not a poll. Both deadlines are on [PendingOtp] and run on the device.
  static Future<PendingOtp> resume(String otpId) async =>
      _toPendingOtp(await _calling(() => _host.resume(otpId)));

  /// The verification this install left in flight, or null.
  ///
  /// Read from the native SDK's own store, so it survives the process being killed while the user
  /// was away receiving their code. It makes no request: pass [otpId] to [resume] to read the
  /// verification back and draw your own screen for it, or call [resumeInterrupted] to let the SDK
  /// present its own.
  static Future<InterruptedVerification?> interrupted() async {
    final message = await _calling(() => _host.interrupted());
    if (message == null) return null;
    return InterruptedVerification(
      otpId: message.otpId,
      expiresAt: DateTime.parse(message.expiresAt).toUtc(),
      locale: message.locale,
    );
  }
}
