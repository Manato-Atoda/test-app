# M（マル）— 社内SNS アプリ

社員向けの Flutter アプリです（iOS / Android / macOS / Windows）。見た目と機能は Galaxia（参照のみ）に合わせています。
API は `../docs/API.md`（v1）と `../docs/API-v2.md`（差分）を参照。
アカウント発行などの管理機能はサーバーの Web 管理コンソール（`{サーバー}/admin`）で行い、
アプリでは管理者にだけ「管理コンソールを開く」を表示します。

## 起動

サーバー（`../server`）を `http://localhost:8790` で起動してから:

```bash
flutter run                         # 既定の接続先: http://localhost:8790（Android エミュレーターは http://10.0.2.2:8790）
flutter run -d macos
flutter run --dart-define=TSUNAGU_API=https://sns.example.co.jp   # 接続先を固定する場合
```

接続先はログイン画面の「詳細設定（接続先）」からも変更できます（端末に保存）。

## 画面

- ログイン（企業コード + 社員コード/メールアドレス + パスワード、またはパスキー）・初回パスワード設定・ガイドライン同意
- スマホ: 下のタブ「ホーム / 森 / 通知 / COMMIT / メニュー」（メニューは下から開く画面）。
  Mac・Windows・iPad 横（幅 768px 以上）: 左のサイドバー＋中央＋右の欄（1100px 以上で「今日のメンバー」「盛り上がってる投稿」「最近のリアクション」）
- ホーム: 投稿欄「いま、なにしてる？」、確認が必要なお知らせのバナー、20 秒ごとに「n 件の新しい投稿」、引っ張って更新
- 投稿: 画像（最大 4 枚）、発信者（実名 / 部署 / 匿名あだ名）、@メンション候補、下書きストック、送る前の「ひと呼吸」
- 投稿カード: ハートのいいね（弾む＋「+1」）、コメント、シェア（そのまま / 引用 / 取り消し）、保存、閲覧数
- 投稿詳細: コメント（発信者・定型コメント・いいね・編集・削除・長文の折りたたみ）
- わからんの森: カテゴリ、答え待ち（程度で点の色が変わる）、質問する、回答・回答へのいいね・回答へのコメント
- COMMIT: 「何を、いつまでに、どこまでやる？」の宣言、メンバー・期間で絞り込み
- 通知（アプリ表示中は上からバナー）、お知らせ、ブックマーク（投稿 / COMMIT）、チャンネル（絵文字・未読数）、社員名簿、検索
- プロフィール（カバー・アイコン・投稿 / COMMIT / 質問）、プロフィール編集（画像・あだ名・自己紹介）
- 企業設定でオンのとき、スマホでは画面に「氏名 / 社員コード」の透かし

## リキッドグラス（iOS 26 以降）

iOS 26 以降で「透明度を下げる」がオフのときは、iOS 本物の部品でリキッドグラスにする
（`lib/widgets/glass.dart` と `ios/Runner/AppDelegate.swift` の `TsunaguGlassPlugin`）。

- 下のタブバー: `UITabBar`（選択のレンズが滑る・押すと反応する・指でなぞって切り替え・未読バッジ）
- 上部のボタン（戻る・閉じる・検索・参加する・保存・投稿するなど）: `UIButton` のガラス
- 右下の「投稿」: 色つきのガラス
- 上部バーの背景: 下を流れる内容をぼかす（スクロールエッジ効果）。内容は上下のバーの下まで流れる

Android・macOS・Windows・iOS 25 以前、「透明度を下げる」がオンのときは、今までどおりの Material のデザインで表示する。

## 構成

```
lib/
  main.dart / app.dart       起動とログイン状態による画面の切り替え
  config.dart                接続先・URL スキーム・端末名
  theme.dart                 Galaxia の配色（MPalette）・グラデーション
  api/                       API クライアントとモデル
  state/                     AppState（ログイン状態・バッジ・閲覧記録・アプリ内通知）
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
