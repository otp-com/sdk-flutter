## 0.4.1

Device registration now repairs itself. An install whose stored device key the API no longer
accepted had every send refused with a 403 on a live publishable key until its app data was
cleared. This happened after an Android backup restored onto a new phone, an Android or iOS
reinstall, an iOS restore, or a key registered under another app. The SDK now drops that key,
registers a fresh one and repeats the call, at most once per app launch.

No API change. Both native SDKs carry the fix, so all four platforms move to 0.4.1 together.

## 0.4.0

Adds the inbound WhatsApp mode, where the user's own WhatsApp message approves the verification and
there is no code to enter. `PendingOtp` gains `completion` (`code` or `inbound`) and `verification`,
and `Otp.awaitApproval(otpId)` waits for an inbound verification the way `submit` answers a code. The
drop-in screen shows a waiting state instead of the code field on such a verification, and
`resumeInterrupted` returns the proof directly when the approval happened while the app was away.

Which WhatsApp mode an account runs is set on our side; read `completion` rather than assuming one.
The two new `PendingOtp` fields default to `code` and null, so a fake built in a test keeps compiling.

Both native SDKs carry the same change, so all four platforms move to 0.4.0 together.

## 0.3.1

Fixes the Android screens ignoring the window insets. The close cross sat against the status bar,
and the country list ran under the navigation bar, on any host that draws edge to edge. iOS is
unchanged and carries the version so all four platforms stay on one number.

Also documents `compileSdk = 37`, which the Android SDK requires and the Flutter template does not
set. Without it the first Android build fails on `checkDebugAarMetadata`.

## 0.3.0

First release of the Flutter SDK. It starts at 0.3.0 rather than at 0.1.0 because the version tracks
the iOS and Android SDKs: all four platforms carry one version number, and 0.3.0 is where this
package joins them.
