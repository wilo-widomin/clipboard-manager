//
//  AppInfo.swift
//  ClipboardManager
//
//  Human-readable info extracted from the bundle.
//

import Foundation

enum AppInfo {

    /// The app's display name, from the bundle.
    static let name: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Clipboard Manager"
    }()

    /// The short version string (e.g. "1.0.2").
    static let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }()

    /// The build number (e.g. "1").
    static let build: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }()

    /// Combined version label, e.g. "Version 1.0.2 (build 1)".
    static var versionDescription: String {
        "Version \(version) (build \(build))"
    }

    /// Author / developer credit.
    static let author: String = "widomin.com"
}