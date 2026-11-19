# TestApp

macOS / iOS / iPadOS で動作する SwiftUI のマルチプラットフォーム テストアプリです。
1 つのターゲット (`TestApp`) で 3 つのプラットフォームすべてに対応しています。

## 動作環境

| 項目 | バージョン |
| --- | --- |
| Xcode | 27.2 以降 |
| Swift | 6.x (Swift 6 言語モード) |
| macOS | 15.0 以降 |
| iOS / iPadOS | 18.0 以降 |

## ディレクトリ構成

```
test-app/
├── TestApp.xcodeproj/            # Xcode プロジェクト
│   └── xcshareddata/xcschemes/   # 共有スキーム (TestApp)
├── TestApp/                      # アプリ本体のソースコード
│   ├── App/                      # エントリーポイントとルート画面
│   │   ├── TestAppApp.swift
│   │   └── ContentView.swift
│   ├── Features/                 # 機能ごとの画面とロジック
│   │   └── Counter/
│   │       ├── CounterView.swift
│   │       └── CounterViewModel.swift
│   ├── Shared/                   # 複数の機能で使う共通コード
│   │   ├── Components/           # 共通 UI 部品
│   │   │   └── PlatformBadge.swift
│   │   └── Platform/             # プラットフォーム判定など
│   │       └── DevicePlatform.swift
│   └── Resources/                # アセット (アイコン・色など)
│       └── Assets.xcassets/
├── TestAppTests/                 # ユニットテスト (Swift Testing)
│   └── Features/Counter/
│       └── CounterViewModelTests.swift
└── scripts/
    └── build.sh                  # コマンドラインでのビルド / テスト用
```

`TestApp/` と `TestAppTests/` は Xcode の「フォルダ同期グループ」として登録されています。
Finder や Xcode でこれらのフォルダに `.swift` ファイルを追加すると、プロジェクトに自動で反映されます
(`project.pbxproj` を手で編集する必要はありません)。

新しい機能を追加するときは `TestApp/Features/<機能名>/` に View と ViewModel をまとめ、
対応するテストを `TestAppTests/Features/<機能名>/` に置いてください。

## Xcode で開く

```bash
open TestApp.xcodeproj
```

ツールバーの実行先で以下を選び、▶︎ (⌘R) で実行します。

- **My Mac** … macOS アプリとして実行
- **iPhone 17 など** … iOS シミュレーターで実行
- **iPad Pro など** … iPadOS シミュレーターで実行

## コマンドラインでビルド / テスト

```bash
scripts/build.sh          # macOS と iOS Simulator 向けにビルド
scripts/build.sh macos    # macOS 向けのみ
scripts/build.sh ios      # iOS Simulator 向けのみ
scripts/build.sh test     # iOS Simulator でユニットテストを実行
```

ビルド成果物は `build/` に出力されます (Git の管理対象外)。

> **注意:** `xcode-select -p` が `/Library/Developer/CommandLineTools` を返す場合は、
> 一度だけ次のコマンドで Xcode を既定に切り替えてください。
> ```bash
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> ```

## 実機 (iPhone / iPad) で動かす場合

実機にインストールするには Apple ID による署名が必要です。

1. Xcode で `TestApp` ターゲット → **Signing & Capabilities** を開く
2. **Team** に自分の Apple ID (Personal Team で可) を選択
3. 必要に応じて **Bundle Identifier** (`io.github.manato-atoda.TestApp`) を一意な値に変更

macOS 版はローカル実行用に「Sign to Run Locally」(アドホック署名) が設定済みです。
