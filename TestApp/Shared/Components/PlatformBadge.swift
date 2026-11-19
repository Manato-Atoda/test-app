import SwiftUI

/// 実行中のプラットフォーム名と OS バージョンを表示するバッジ。
struct PlatformBadge: View {
    let platform: DevicePlatform

    var body: some View {
        VStack(spacing: 4) {
            Label("Running on \(platform.rawValue)", systemImage: platform.symbolName)
                .font(.headline)
            Text(DevicePlatform.osVersionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.tint.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("platformBadge")
    }
}

#Preview {
    VStack {
        ForEach(DevicePlatform.allCases, id: \.self) { platform in
            PlatformBadge(platform: platform)
        }
    }
    .padding()
}
