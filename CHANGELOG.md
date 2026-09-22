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
