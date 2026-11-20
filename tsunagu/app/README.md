# つなぐ（社内SNS）アプリ

社員向けの Flutter アプリです（iOS / Android / macOS / Windows）。
アカウント発行などの管理機能はサーバーの Web 管理コンソール（`{サーバー}/admin`）で行い、
アプリでは管理者にだけ「管理コンソールを開く」を表示します。API は `../docs/API.md` を参照。

## 起動

サーバー（`../server`）を `http://localhost:8790` で起動してから:

```bash
flutter run                         # 既定の接続先: http://localhost:8790（Android エミュレーターは http://10.0.2.2:8790）
flutter run -d macos
flutter run --dart-define=TSUNAGU_API=https://sns.example.co.jp   # 接続先を固定する場合
```

接続先はログイン画面の「詳細設定（接続先）」からも変更できます（端末に保存）。

## 画面

- ログイン（企業コード + 社員コード/メールアドレス + パスワード、またはパスキー）
- 初回パスワード設定（仮パスワードでログインしたとき。規則をリアルタイムで表示）
- 利用ガイドラインへの同意（会社がガイドラインを更新したときも再表示）
- ホーム / チャンネル / お知らせ / 通知 / メニュー（幅 840px 以上は左のレール、未満は下のバー）
- 投稿・コメント・リアクション・お知らせの「確認しました」・確認状況・通報・検索・社員名簿・プロフィール
- パスキー管理・パスワード変更・ログイン中の端末・全端末からログアウト

## 構成

```
lib/
  main.dart / app.dart       起動とログイン状態による画面の切り替え
  config.dart                接続先・URL スキーム・端末名
  theme.dart                 配色（シード #3355D1）
  api/                       API クライアントとモデル
  state/                     AppState（ログイン状態・未読数）
  services/                  安全な保存領域、パスキー連携（ブラウザ ↔ アプリ）
  screens/ widgets/ utils/   画面・部品・小さな処理
test/logic_test.dart         パスワード規則・PKCE・本文解析などのテスト
```

## 企業向けの配慮

- ログイントークンは OS の安全な保存領域のみ（キーチェーン / Keystore / 資格情報マネージャー）。
  仮パスワードと再設定用の限定トークンはメモリだけに置き、保存しない。
- Android は自動バックアップを無効化。平文 HTTP はデバッグビルドだけ許可（リリースは HTTPS のみ）。
- 外部への共有ボタンは置かない。本文のリンクは確認ダイアログを出してから開く。
- パスキーはサーバーの Web ページ（WebAuthn）で扱い、PKCE 付きの一回限りのコードでアプリに戻す。
  iOS / macOS は ASWebAuthenticationSession、Android は Auth Tab / Custom Tabs、
  Windows は既定のブラウザ + `http://localhost:43823/` で受け取る。

## プラットフォーム設定（`flutter create` 後に変更した点）

- iOS: 表示名「つなぐ」、日本語ローカライズ、`NSAllowsLocalNetworking`（開発用）
- Android: 表示名、INTERNET 権限、`allowBackup=false`、パスキー連携の `CallbackActivity`（`tsunagu://`）、
  デバッグビルドのみ `usesCleartextTraffic`
- macOS: `com.apple.security.network.client`（Debug / Release）、表示名
- Windows: ウィンドウタイトル「つなぐ」、製品名

本番でパスキーを使うには、サーバーを HTTPS の独自ドメインで公開し、`TSUNAGU_RP_ID` をそのドメインにしてください。
