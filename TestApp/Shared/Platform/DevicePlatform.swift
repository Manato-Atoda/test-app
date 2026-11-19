import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 実行中のプラットフォーム。
/// 1 つのコードベースで macOS / iOS / iPadOS を判別するためのヘルパー。
enum DevicePlatform: String, CaseIterable {
    case mac = "macOS"
    case iPhone = "iOS"
    case iPad = "iPadOS"
    case other = "Other"

    /// 現在アプリが動いているプラットフォーム
    static var current: DevicePlatform {
        #if os(macOS)
        return .mac
        #elseif os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return .iPhone
        case .pad: return .iPad
        case .mac: return .mac
        default: return .other
        }
        #else
        return .other
        #endif
    }

    /// SF Symbols のアイコン名
    var symbolName: String {
        switch self {
        case .mac: "desktopcomputer"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .other: "questionmark.circle"
        }
    }

    /// OS バージョン (例: "Version 27.2 (Build 27C52)")
    static var osVersionDescription: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
