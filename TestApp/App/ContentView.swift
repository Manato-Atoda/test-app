import SwiftUI

/// アプリのルート画面。各機能 (Features) の画面をここから表示する。
struct ContentView: View {
    var body: some View {
        NavigationStack {
            CounterView()
                .navigationTitle("Test App")
        }
    }
}

#Preview {
    ContentView()
}
