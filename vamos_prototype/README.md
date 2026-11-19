# VAMOS アプリ試作（Flutter）

Web マガジン「Vamos」をアプリにできるかを、ざっくり確かめるための試作です。
デザインと記事データは [RE_VAMOS](https://github.com/VAMOS-Community/RE_VAMOS) を**参照するだけ**で、RE_VAMOS 側は変更しません。

## 画面

| タブ | 内容 |
| --- | --- |
| ホーム | 最新インタビューのスライド、インタビュー、トピック、Vamos の紹介 |
| インタビュー | 企業インタビュー一覧と詳細（吹き出しの対談形式） |
| トピック | 就活・転職・ニュースの絞り込みと詳細 |
| マイページ | ゲスト表示、状況の選択（オンボーディング風）、保存したインタビュー |

試作のため、通信・ログイン・プッシュ通知・保存内容の永続化はしていません。

## ディレクトリ構成

```
vamos_prototype/
├── lib/
│   ├── main.dart            # アプリの入口と下部タブ
│   ├── theme/               # 色・角丸・影（RE_VAMOS の style.css に合わせたもの）
│   ├── data/                # データの型と読み込み
│   ├── widgets/             # 共通部品（カード、ボタン、本文の描画）
│   └── screens/             # 各画面
├── tool/
│   └── import_vamos_data.py # RE_VAMOS からサンプルデータを書き出す
├── assets/vamos/            # 書き出したデータと画像（Git 管理外）
└── test/
```

## 動かし方

1. RE_VAMOS を手元にクローンし、サンプルデータを書き出す。

   ```bash
   python3 -I tool/import_vamos_data.py <RE_VAMOS のクローン> --count 10
   ```

2. iPhone シミュレーターで起動する。

   ```bash
   flutter run -d "iPhone 17"
   ```

`assets/vamos/` には VAMOS の記事本文と写真のコピーが入るため、Git には含めません。
