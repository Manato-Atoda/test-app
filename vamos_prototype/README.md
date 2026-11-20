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
| プッシュ通知（iOS） | マイページで通知をオンにすると端末を登録。管理画面から配信し、通知をタップすると記事が開く（試作ではシミュレーターのみ。実機は有料の Apple Developer Program が必要） |
| ディープリンク | `vamos://app/interviews/<slug>`、`vamos://app/topics/<id>` で該当ページを開く |
| 保存 | インタビューを保存してマイページに一覧表示。保存した記事は本文も端末に残り、オフラインでも読める |
| 外部リンク・共有 | トピックのリンクをアプリ内ブラウザで開く。記事を端末の共有シート（LINE・X など）で共有 |
| 画面サイズ | iPhone 11 程度の画面から、iPhone Duo を開いた横長の画面まで対応。広い画面ではカードを 2〜3 列に並べ、記事の本文は読みやすい幅に収める。折りたたみの開閉や回転にも追従し、読んでいる位置は保つ。縦に並ぶステータスバーやノッチの部分は避けて表示 |
| 左右 2 画面（iPhone Duo を開いたとき） | インタビュー・トピック・検索結果は、画面の真ん中（折り目）で分けて左に一覧・右に記事を表示。閉じると右の記事がそのまま記事ページになり、開き直すと右側に戻る（読んでいた位置は保つ） |
| リキッドグラス（iOS 26 以降） | 下部のタブバーは iOS 本物の UITabBar（選択のレンズが滑る・指でなぞって切り替え）、ヘッダーのボタン（戻る・検索・共有・保存）は iOS 本物のガラスボタン（押すと反応）。ヘッダーの背景はスクロールエッジ風のぼかし。Android・古い iOS・「透明度を下げる」がオンのときは、Vamos デザインで表示 |

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
├── ios/Runner/AppDelegate.swift  # 通知（VamosPushPlugin）とリキッドグラス（VamosGlassPlugin）
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

## 自分の iPhone で動かす（無料の Apple ID）

有料の Apple Developer Program に入っていなくても、Mac とケーブルでつないだ自分の iPhone には入れられます。
ただし、入れたアプリは 7 日で起動できなくなるので、そのときはもう一度入れ直します（保存した記事などは残ります）。プッシュ通知は使えません。

1. Xcode の Settings → Accounts に自分の Apple ID を追加し、チーム ID を確認する。
2. 署名チームを `ios/Flutter/Signing.xcconfig` に書く（Git には含めない）。

   ```bash
   echo "DEVELOPMENT_TEAM = <チームID>" > ios/Flutter/Signing.xcconfig
   ```

3. iPhone の「設定 → プライバシーとセキュリティ → デベロッパモード」をオンにする。
4. モックAPIを、同じ Wi-Fi の端末からも接続できるようにして起動する。

   ```bash
   python3 -I -u tool/mock_api_server.py --port 8787 --host 0.0.0.0
   ```

5. Mac の IP アドレスを接続先にして、リリース版で入れる（リリース版なら Mac から外しても起動できる）。

   ```bash
   flutter run --release --dart-define=VAMOS_API=http://$(ipconfig getifaddr en0):8787
   ```

6. 初めて開くときは、iPhone の「設定 → 一般 → VPN とデバイス管理」で開発元を信頼する。
7. 「ローカルネットワーク上のデバイスの検索」を求められたら許可し、ホームを引っ張って更新する。

Mac と別の Wi-Fi にいるときや、モックAPIを止めているときは、前回取得したデータで表示します。

## 通知を試す

1. アプリのマイページで「新着のお知らせ」をオンにして、通知を許可する。
2. パソコンのブラウザで http://localhost:8787/admin を開き、記事の「通知で配信」を押す。
3. アプリをホーム画面に戻しておくと、通知が届く。タップするとその記事が開く。

試作版では、確認コードを画面に表示します（本番ではメールでのみ届きます）。
`assets/vamos/` には VAMOS の記事本文と写真のコピーが入るため、Git には含めません。
