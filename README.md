# I'm a teapot

HTTP `418 I'm a teapot` をネタにした静的ページです。

gopher（Go言語のマスコット）と ferris（Rustのマスコット）がお茶を飲んでいるイラストとともに、ステータスコード418の元ネタ（[RFC 2324](https://developer.mozilla.org/ja/docs/Web/HTTP/Reference/Status/418)）にリンクしています。

## ファイル構成

```
.
├── index.html
├── i_am_a_teapot.webp   # gopherとferrisがお茶してる画像（要配置）
└── functions/
    └── index.js          # Cloudflare Pages Functions（418を返す）
```

## セットアップ

`i_am_a_teapot.webp` をリポジトリ直下に配置してください。`index.html` から相対パスで参照しています。



### ステータスコードを418にする

Cloudflare Pages自体はレスポンスのステータスコードを変更できないため、`functions/index.js` で [Pages Functions](https://developers.cloudflare.com/pages/functions/) を使い、ルート（`/`）へのレスポンスを418に書き換えています。

デプロイ後、以下で確認できます。

```bash
curl -I https://<your-project>.pages.dev/
```

`HTTP/2 418` が返ってくれば成功です。

## ライセンス

特になし（お好きにどうぞ）
