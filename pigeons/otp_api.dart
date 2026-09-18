// The contract between Dart and the two native SDKs. Pigeon reads this file to generate the
// platform channel code, so it is limited to what the channel can carry: strings, numbers,
// booleans, and objects of those. Three consequences show up in every shape below.
//
// Dates cross as ISO 8601 strings, because the channel has no date type. The wrapper in
// `otp_flutter.dart` turns them back into `DateTime`, so the published API is not the channel's
// API.
//
// Failures cross as a `PlatformException` carrying a machine-readable code, because the channel
// has no error type either. `otp_flutter.dart` turns that back into an `OtpException`.
//
// Nothing here is stateful. The native SDKs hold a session object; this surface deliberately does
// not, and passes the verification's id on every call instead. A Dart hot restart throws away the
// Dart half of the world while the native half survives, so any state kept on one side only would
// come back out of step with the other.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut: 'ios/otp_flutter/Sources/otp_flutter/Messages.g.swift',
    kotlinOut: 'android/src/main/kotlin/com/otp/sdk/flutter/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.otp.sdk.flutter'),
    dartPackageName: 'otp_flutter',
  ),
)
class PendingOtpMessage {
  PendingOtpMessage({
    required this.id,
    required this.status,
    this.channel,
    required this.maskedRecipient,
    required this.codeLength,
    required this.expiresAt,
    this.resendAvailableAt,
    this.handoffUrl,
  });

  final String id;

  /// `pending`, `approved`, `failed`, `expired`, or `unknown` for a status this build cannot name.
  final String status;

  /// Null until routing has picked a channel.
  final String? channel;

  final String maskedRecipient;
  final int codeLength;
  final String expiresAt;
  final String? resendAvailableAt;

  /// WhatsApp only: the link the user opens to be sent the code.
  final String? handoffUrl;
}

class VerificationMessage {
  VerificationMessage({required this.otpId, required this.token, required this.tokenExpiresAt});

  final String otpId;
  final String token;
  final String tokenExpiresAt;
}

class InterruptedMessage {
  InterruptedMessage({required this.otpId, required this.expiresAt, this.locale});

  final String otpId;
  final String expiresAt;
  final String? locale;
}

class CodeSubmissionMessage {
  CodeSubmissionMessage({this.verification, this.attemptsRemaining, this.reason});

  /// Present when the code matched. The token is the only part your backend may trust.
  final VerificationMessage? verification;

  /// Set when the code did not match, and null once the verification is resolved.
  final int? attemptsRemaining;

  /// `incorrectCode`, `expired`, `noAttemptsLeft`, or `unknown`. Null when the code matched.
  final String? reason;
}

// Status, channel and rejection reason cross as strings rather than as Pigeon enums. Routing and
// error handling gain new values over time and an app already on a phone cannot be updated to
// match, so a value this build was never told about must not fail decoding. This is the same
// reason the generated native transport carries `enumUnknownDefaultCase`. Mapping to a Dart enum,
// including the `unknown` fallback, happens in the public API layer instead.
@HostApi()
abstract class OtpHostApi {
  @async
  void configure(String publishableKey, String? baseUrl);

  // The drop-in screens, presented by the platform. They are the reason this package exists: an
  // app that builds its own screen on the calls below has to rewrite six languages, right-to-left
  // layout, one-time-code autofill and the WhatsApp handoff, all of which are already here.
  //
  // Each resolves with the proof, or fails with `cancelled` when the user closes the screen.

  /// Presents the code screen for a recipient your own screen already collected.
  @async
  VerificationMessage verify(String recipient, String? locale);

  /// Presents the recipient screen, then the code screen. `kind` is `phone` or `email`.
  @async
  VerificationMessage verifyCollecting(String kind, String? locale);

  /// Presents the code screen for a verification left in flight, if there is one.
  ///
  /// Resolves with null when there was nothing to resume, which includes a verification that has
  /// expired or been answered in the meantime, and when the user closes the screen.
  @async
  VerificationMessage? resumeInterrupted();

  // The core, for an app that wants its own screens. Everything above is built on exactly this.

  @async
  PendingOtpMessage start(String recipient, String? locale);

  @async
  CodeSubmissionMessage submit(String otpId, String code);

  @async
  PendingOtpMessage resend(String otpId, String? channel);

  @async
  PendingOtpMessage resume(String otpId);

  /// The verification this install left in flight, or null. Reads what the device kept and makes
  /// no request, so it is safe to call on launch.
  ///
  /// Read from the native SDK's own store rather than from Dart, so it survives the process being
  /// killed while the user was away in WhatsApp receiving their code. Without it an app would have
  /// to persist the id itself to be able to call `resume`.
  @async
  InterruptedMessage? interrupted();
}
