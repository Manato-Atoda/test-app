# VAMOS アプリ試作（Flutter）

Web マガジン「Vamos」をアプリにできるかを確かめるための試作です。
デザインと記事データは [RE_VAMOS](https://github.com/VAMOS-Community/RE_VAMOS) を**参照するだけ**で、RE_VAMOS 側は変更しません。

## できること

| 機能 | 内容 |
| --- | --- |
| 記事の表示 | ホーム・企業インタビュー（吹き出しの対談形式）・トピック。API から取得し、引っ張って更新できる |
| オフライン表示 | API に接続できないときは、前回取得したデータ（なければ同梱データ）で表示し、取得日時を帯で知らせる |
| 検索 | インタビューとトピックをキーワードで検索 |
| 会員登録・ログイン | メールアドレスと6桁の確認コード（RE_VAMOS と同じ方式）。続けてプロフィールを3ステップで設定。ログイン状態は次回起動時も続く |
| プッシュ通知（iOS） | マイページで通知をオンにすると端末を登録。管理画面から配信し、通知をタップすると記事が開く |
| ディープリンク | `vamos://app/interviews/<slug>`、`vamos://app/topics/<id>` で該当ページを開く |
| 保存 | インタビューを保存してマイページに一覧表示。保存した記事は本文も端末に残り、オフラインでも読める |
| 外部リンク・共有 | トピックのリンクをアプリ内ブラウザで開く。記事を端末の共有シート（LINE・X など）で共有 |

## 使っているライブラリ

| ライブラリ | 用途 |
| --- | --- |
| shared_preferences | ログイン状態・保存した記事・前回のデータを端末に保存（本番ではトークンを Keychain に保存する） |
| url_launcher | 外部サイトをアプリ内ブラウザで開く |
| share_plus | 共有シート |

## 構成

```
アプリ（Flutter） ──HTTP──▶ モックAPI（tool/mock_api_server.py）
                               ├ 記事・画像の配信
                               ├ 会員・確認コード・プロフィール
                               └ 通知の配信（iOS シミュレーターへは xcrun simctl push）
```

モックAPIは、本番で想定しているサーバー（XServer 上の PHP）の代わりに、API の形を確かめるためのものです。
本番のプッシュ通知は Firebase Cloud Messaging（FCM）を使う想定で、試作では iOS の仕組みを直接使っています。

## ディレクトリ構成

```
vamos_prototype/
├── lib/
│   ├── main.dart              # 入口・下部タブ・リンクからの起動
│   ├── app_router.dart        # ディープリンク・通知からの画面遷移
│   ├── config.dart            # 接続先（モックAPI）の設定
│   ├── theme/                 # 色・角丸・影（RE_VAMOS の style.css に合わせたもの）
│   ├── data/                  # API クライアント・データの型・リポジトリ
│   ├── services/              # プッシュ通知（ネイティブとの橋渡し）
│   ├── widgets/               # 共通部品（カード、ボタン、本文の描画）
│   └── screens/               # 各画面（ホーム・インタビュー・トピック・検索・会員・マイページ）
├── ios/Runner/AppDelegate.swift  # 通知の許可・タップを Dart へ渡す VamosPushPlugin
├── tool/
│   ├── import_vamos_data.py   # RE_VAMOS からサンプルデータを書き出す
│   └── mock_api_server.py     # モックAPI（標準ライブラリのみ）
├── assets/vamos/              # 書き出したデータと画像（Git 管理外）
└── test/
```

## 動かし方

1. RE_VAMOS を手元にクローンし、サンプルデータを書き出す。

   ```bash
   python3 -I tool/import_vamos_data.py <RE_VAMOS のクローン> --count 10
   ```

2. モックAPIを起動する（起動しなくても、アプリは同梱データで動く）。

   ```bash
   python3 -I -u tool/mock_api_server.py --port 8787
   ```

3. iPhone シミュレーターで起動する。

   ```bash
   flutter run -d "iPhone 17"
   ```

## 通知を試す

1. アプリのマイページで「新着のお知らせ」をオンにして、通知を許可する。
2. パソコンのブラウザで http://localhost:8787/admin を開き、記事の「通知で配信」を押す。
3. アプリをホーム画面に戻しておくと、通知が届く。タップするとその記事が開く。

試作版では、確認コードを画面に表示します（本番ではメールでのみ届きます）。
`assets/vamos/` には VAMOS の記事本文と写真のコピーが入るため、Git には含めません。
