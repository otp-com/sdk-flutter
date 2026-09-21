# otp.com Flutter SDK

[![pub package](https://img.shields.io/pub/v/otp_flutter)](https://pub.dev/packages/otp_flutter)


Verifies a phone number or an email address with a one-time code. The channel is chosen by your
account routing, so you pass the recipient and nothing else.

This package is a bridge over the native otp.com SDKs, not a re-implementation. The screen your user
sees is the platform's own: UIKit-backed SwiftUI on iOS, Compose on Android.

Requires **iOS 15** and **Android API 26**. iOS 15 is the floor for the SwiftUI the drop-in screen is
written in.

Android 26, not Flutter's own floor, and the reason is worth knowing before you upgrade a project:
the Android SDK's security floor is hardware-backed key attestation, which is only guaranteed from
8.0. A project that builds against plain Flutter can therefore fail to build against this package
until you raise `minSdk`.

## Before you start

You need two keys, and they are not interchangeable.

1. Sign in at [panel.otp.com](https://panel.otp.com?utm_source=github-sdk-flutter). If you do not have
   an account yet, [create one](https://panel.otp.com/signup?utm_source=github-sdk-flutter); it takes
   a minute and comes with sandbox credit.
2. Open your app, then **API Keys**, and create two:
   - a **publishable key** (`otp_pk_live_…`) for this SDK, which goes in your app;
   - a **server key** (`otp_live_…`) for your own backend, which never leaves it.
3. While you are integrating, use the `otp_pk_test_…` and `otp_test_…` pair instead. Sandbox sends no
   real messages and costs nothing.

The publishable key is meant to be readable: it ships inside your app, it is scoped to that one app,
and it can only start and answer verifications. It cannot read a recipient and it cannot exchange a
verification, which is why the server key exists and why it stays on your server.

## Install

```sh
flutter pub add otp_flutter
```

Then raise the Android floor in `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        minSdk = 26
    }
}
```

Nothing else to register: Flutter's own plugin resolution finds the native halves on both platforms.
Swift Package Manager and CocoaPods both work on iOS, and neither needs a line added to your Podfile.

## Use it

Configure once, at launch:

```dart
import 'package:otp_flutter/otp_flutter.dart';

await Otp.configure(publishableKey: 'otp_pk_live_…');
```

Then run a verification. This presents a screen, sends the code, takes the user's input, and resolves
when it is done:

```dart
final verification = await Otp.verify('+14155552671');
```

If your flow has no phone field yet, let the SDK collect it:

```dart
final verification = await Otp.verifyCollecting(RecipientKind.phone); // or RecipientKind.email
```

The message and the screen follow the same locale, so they never disagree. It defaults to the
device's; pass one to override:

```dart
final verification = await Otp.verify('+14155552671', locale: 'tr-TR');
```

The screen speaks English, Turkish, Russian, Arabic, German and French, lays itself out right to left
where the language reads that way, follows the system light and dark appearance, and takes its accent
colour from your panel. Its one and only decision that is yours is that colour.

## The one thing to get right

**`verification.token` is the result. Nothing else is.**

Send it to your own backend, which exchanges it with your **server** key:

```
POST https://api.otp.com/api/v1/verifications/exchange
Authorization: Bearer otp_live_…

{ "verification_token": "…" }
```

It answers with what was actually verified:

```json
{
  "otp_id": "6f0d2c5e-1c3a-4f1b-9a2e-6a1f2b3c4d5e",
  "recipient": "+14155552671",
  "recipient_type": "phone",
  "channel": "sms",
  "verified_at": "2026-09-08T19:33:21Z"
}
```

Until you make that call, your backend knows nothing. A success read off a device you do not control
is not evidence, and anyone running a modified build can claim any outcome they like. The token is
short-lived and single-purpose, so treat it as the only thing you trust.

Our [backend SDKs](https://github.com/otp-com?utm_source=github-sdk-flutter) do this call for you in
Node, PHP, Go and Python.

## Resuming

On the WhatsApp channel the code is not sent until the user messages us, which means they leave your
app and the OS may kill it while they are away. Call this when your app resumes and they come back to
the screen they left:

```dart
final verification = await Otp.resumeInterrupted();
if (verification != null) {
  // finish the sign-in
}
```

It resolves with null when there was nothing in flight, which includes a verification that expired
while they were away and one they closed without answering.

## Your own screen

The drop-in screen has no view-slot API, because a screen assembled from someone else's slots is
worse than one you wrote. If you want a different screen, build it on the same calls the drop-in uses:

```dart
final pending = await Otp.start('+14155552671');

pending.codeLength;         // how many boxes to draw, and it is not always 6
pending.expiresAt;          // count down from this
pending.resendAvailableAt;  // null means it can never be resent, not "resend now"
pending.handoffUrl;         // WhatsApp only: open this, the code follows

final outcome = await Otp.submit(pending.id, entered);
switch (outcome) {
  case CodeMatched():
    // outcome.verification.token
    break;
  case CodeRejected():
    // a wrong code is an outcome, not an error
    outcome.attemptsRemaining;
}
```

Everything a screen needs is on the answer, including both deadlines, so no part of this polls.

`codeLength` is worth reading rather than assuming: it is your account's setting and it is not always
six.

After a restart you can pick a verification back up without having stored anything yourself:

```dart
final inFlight = await Otp.interrupted();     // makes no request
if (inFlight != null) {
  final pending = await Otp.resume(inFlight.otpId);
}
```

## Device integrity

The native SDK registers a hardware-backed key on first use, with App Attest on iOS and Keystore
attestation on Android, and signs every send with it. That is what stops a publishable key lifted out
of your bundle from being used outside your app.

You configure nothing for this. Two consequences worth knowing:

- **Neither an iOS simulator nor an Android emulator can produce a proof.** Where a proof is
  required, sends from them are refused with kind `OtpErrorKind.deviceProofRejected`. Test that path
  on hardware.
- **Whether a proof is required follows the key.** A sandbox key (`otp_pk_test_…`) never requires
  one, so a simulator and an emulator are fine while you integrate. A live key does, once the
  platform asks for it, and on iOS it also requires a production build: one installed from Xcode
  attests in the development environment, which only a sandbox key accepts. The last thing to test
  before going live is therefore a real device, a production build, and your live key.

## Errors

Every call in this package throws an `OtpException` and nothing else. Read `kind` to decide what to
do, and keep `message` for your logs: it is written for you, not for your user, and it is not
translated.

```dart
import 'package:otp_flutter/otp_flutter.dart';

try {
  final verification = await Otp.verify(recipient);
} on OtpException catch (error) {
  switch (error.kind) {
    case OtpErrorKind.cancelled:
      break; // the user closed the screen
    case OtpErrorKind.rateLimited:
      wait(error.retryAfterSeconds);
      break;
    case OtpErrorKind.validationFailed:
      showYourOwnFieldError();
      break;
    default:
      log(error);
  }
}
```

`kind` can be a value your build has never heard of, and arrives as `OtpErrorKind.unknown` when it
is: the list grows server-side and an app already on a phone cannot be updated to match. `OtpChannel`
and `OtpStatus` behave the same way and for the same reason, since adding a case to a Dart enum
breaks an exhaustive `switch` in an app that is already written. `error.type` carries the API's own
name for the failure, which is what tells two failures of the same kind apart.

## Example

[`example/`](./example) is a small app that calls every entry point: the presented screens, the core
calls for an app drawing its own, and reading back a verification left in flight.

```sh
cd example
flutter pub get
flutter run
```

Put your own publishable key in the field at the top and tap **configure** before anything else.

## License

This package is [Apache-2.0](./LICENSE), and the native SDKs it bridges are not. Those ship as
compiled binaries under otp.com's commercial licence, which is why the boundary is worth stating:
what you may fork and redistribute freely is the glue, not the SDK underneath.

## Support

Docs and status: [otp.com](https://otp.com?utm_source=github-sdk-flutter). Anything else:
info@otp.com.

## Issues

This repository is where the package is documented and where issues are reported. The package itself
is published to pub.dev as [`otp_flutter`](https://pub.dev/packages/otp_flutter).
