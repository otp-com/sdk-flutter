require 'yaml'

pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name         = 'otp_flutter'
  s.version      = pubspec['version']
  s.summary      = pubspec['description']
  s.description  = pubspec['description']
  s.homepage     = 'https://otp.com'
  s.license      = { type: 'Commercial', file: '../LICENSE' }
  s.authors      = { 'otp.com' => 'support@otp.com' }
  s.source       = { path: '.' }

  # The floor is the iOS SDK's, not Flutter's. See the README: it is the minimum the drop-in
  # screen's SwiftUI needs, and a published minimum is a promise rather than a detail.
  s.platform     = :ios, '15.0'
  # Sources live under the Swift Package Manager layout, which both systems read: CocoaPods compiles
  # them from here and Swift Package Manager builds the same directory as its target.
  s.source_files = 'otp_flutter/Sources/otp_flutter/**/*'

  # Load-bearing. The Otp xcframework is a static binary, and without this CocoaPods refuses it as a
  # transitive dependency under the `use_frameworks!` every Flutter app template ships with. Saying
  # it here is what keeps an app's Podfile untouched.
  s.static_framework = true

  s.dependency 'Flutter'

  # The native SDK this plugin is a bridge over. A version bound rather than the exact version: the
  # three platforms move their minor together, and a patch of the iOS SDK is not a release of this.
  s.dependency 'Otp', "~> #{s.version.to_s.split('.').first(2).join('.')}"

  s.swift_version = '5.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
