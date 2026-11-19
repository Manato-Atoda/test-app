import SwiftUI

/// アプリのエントリーポイント。
/// macOS / iOS / iPadOS で共通の 1 ターゲットとしてビルドされる。
@main
struct TestAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 480, height: 560)
        #endif
    }
}
