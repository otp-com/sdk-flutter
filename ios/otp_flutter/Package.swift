// swift-tools-version: 6.0
import PackageDescription

// swift-tools-version is 6.0 because the Otp framework's public interface uses typed throws,
// which only a Swift 6 compiler can read. See sdk-ios/Package.swift for the same reasoning.
//
// The 0.2.0 version below and the podspec's `~>` bound are one number, moved together by the
// release tooling.
let package = Package(
  name: "otp_flutter",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "otp-flutter", targets: ["otp_flutter"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
    // Package identity is derived from the URL's last path component, hence "sdk-ios" rather than "Otp".
    .package(url: "https://github.com/otp-com/sdk-ios.git", from: "0.3.0"),
  ],
  targets: [
    .target(
      name: "otp_flutter",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        .product(name: "Otp", package: "sdk-ios"),
      ],
      // The Swift 6 language mode, which swift-tools-version 6.0 would otherwise select, does not
      // compile Pigeon's own generated Messages.g.swift. The CocoaPods path builds in this mode as
      // well, so the two ways of consuming this plugin stay the same build.
      swiftSettings: [.swiftLanguageMode(.v5)]
    )
  ]
)
