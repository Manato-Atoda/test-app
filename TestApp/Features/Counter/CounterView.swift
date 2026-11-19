import SwiftUI

/// カウンター画面。どのプラットフォームで動いているかも合わせて表示する。
struct CounterView: View {
    @State private var viewModel = CounterViewModel()

    var body: some View {
        VStack(spacing: 32) {
            PlatformBadge(platform: .current)

            Text("\(viewModel.count)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(viewModel.count)))
                .accessibilityIdentifier("counterValue")

            HStack(spacing: 16) {
                Button {
                    withAnimation { viewModel.decrement() }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 28)
                }
                .disabled(!viewModel.canDecrement)
                .accessibilityLabel("減らす")

                Button("リセット") {
                    withAnimation { viewModel.reset() }
                }
                .disabled(!viewModel.canReset)

                Button {
                    withAnimation { viewModel.increment() }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 28)
                }
                .disabled(!viewModel.canIncrement)
                .accessibilityLabel("増やす")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CounterView()
}
