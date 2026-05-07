<p align="center">
  <img src="docs/images/banner.png" alt="OpenQuack — 話す。送る。プライベートに。録音オーバーレイには 'Listening' とライブレベルメーター、メニューバーのポップオーバーには 'Pasted at cursor' と直近の文字起こし、フッターに Settings / Quit ボタンが表示されている。">
</p>

<div align="center">

**OpenQuack** *話す。送る。プライベートに。*

macOS 向けの音声入力。何もデバイスから出ない —— 音声もテキストも、何も。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](docs/INSTALL.md)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)](docs/ROADMAP.md)

</div>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <strong>日本語</strong> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a>
</p>

> 🌐 **機械翻訳です。** ネイティブの方からの貢献を歓迎します —— PR を送るか、[`CONTRIBUTING.md`](CONTRIBUTING.md) を参照してください。

---

> 📢 **新着 — [v2.0.0-alpha.9](https://github.com/larryxiao/openquack/releases/tag/v2.0.0-alpha.9):** 長いクリップでも爆速の音声入力。さらに新しい外観も。気に入ってもらえると嬉しいです!

## これは何?

OpenQuack は macOS 向けの小さなメニューバーアプリ。ホットキーを押して話し、もう一度押す —— 文字起こしがカーソル位置に現れる。タイプできる場所なら、どこでも話せる。

音声認識は Mac の中で完結。クラウドなし、アカウントなし、サインアップなし、テレメトリなし。

## なぜ作ったか

**ローカル。** すべてがデバイス上で動く —— 録音、文字起こし、オプションの整形まで。何も外に出ない:音声、テキスト、テレメトリ、サインアップ、すべてなし。機密の作業は、設計レベルで機密のまま。フローに API コールがないので、ずっと動き続ける —— オフラインでも、飛行機の中でも、企業ファイアウォールの後ろでも。

**速い。** Apple Silicon 上の Whisper は、話した時間のおよそ 5 分の 1 で文字起こしする。ベースラインの M4 / 16 GB で、リアルな人間の音声に対する単語誤り率はおよそ 2.6%。多くの場合、タイプより速い。フルベンチマークは [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)。

**オープン。** MIT ライセンス。すべての行が監査可能で、すべての変更は公開で行われる。メニューバーで動いているバージョンが、このリポジトリにあるバージョン。

## 使えるもの

- **ワンキー入力。** ホットキーを選ぶ(デフォルトは ⌃⇧Space)。トグル式またはプッシュ・トゥ・トーク。
- **すべてローカル。** 音声認識は Mac で動く。入力にネット接続は不要 —— オフライン、飛行機、トンネル、企業ファイアウォールの後ろでも動く。API キーなし、レート制限なし、サービス停止もなし。個人でも仕事でも、同じ音声入力。
- **多言語対応。** Whisper は 99 言語に対応 —— 英語、中国語、日本語、韓国語、スペイン語、フランス語、ドイツ語、イタリア語、ポルトガル語は設定からそのまま選べる;自動検出はデフォルトでオン。
- **カーソル位置に自動ペースト**、どんなアプリでも。(自分で貼りたければクリップボードにフォールバック。)
- **スマートフォーマット** —— 大文字化、文末の句読点、「えー / あのー」のクリーンアップ。
- **カスタム辞書** —— あなたが実際に使う固有名詞やプロジェクト名を覚えさせられる。
- **無音で自動停止。** 話し終われば、OpenQuack が自分で締めくくる。
- **ライブのマイクレベル表示**、ちゃんと聞いてるのが見える。
- **初回起動の高速セットアップ** —— 権限とホットキー、1 分で完了。
- **小さい。** 8 MB のメニューバーアプリ、プラス初回起動時に音声モデル。
- **オープンソース**、MIT。

## プライバシー、1 画面で

1. **何もデバイスから出ない —— 音声、テキスト、何も。** 録音と文字起こしは完全にローカル。常に。
2. **アナリティクスなし、テレメトリなし、サインアップなし。**

プライバシーの完全な契約は [`docs/VISION.md`](docs/VISION.md#privacy-contract)。

## 次に来るもの

控えている機能のプレビュー。どちらも今日出荷されている音声入力の土台の上に乗っている。

**コンテキスト対応の文字起こし。** OpenQuack は、これからペーストする周辺のテキストを読む —— カーソル上の行、いま中にいる関数、返信中のチャットスレッド —— そしてそれをコンテキストとして音声モデルに渡す。専門用語は、いま実際にやっていることに基づいて曖昧さが解消される(ターミナルにいるとき、「cloud code」は「Claude Code」になり、その逆ではない)。カスタム辞書をいじる頻度が減る。

**シンキングモード。** 文字起こしの後にもう一段、小さなローカル LLM を通して、話した生の文を、実際に送信ボタンを押せる書き言葉に変える。フィラーをカット、構造を引き締め、大事な言葉に正しい大文字化。デフォルトはオフ、ワンクリックで有効化。完全ローカル —— Ollama または MLX-LM、お好みで。

スケジュールと SPEC の詳細は [`docs/ROADMAP.md`](docs/ROADMAP.md)。

このアヒルにはもっと大きな計画がある。向かう先は [`docs/VISION.md`](docs/VISION.md)。

## インストール

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

または [DMG をダウンロード](https://github.com/larryxiao/openquack/releases) して Applications にドラッグ。初回起動:右クリック → **開く** → **開く**(Gatekeeper を一回だけバイパス)。

macOS が聞いてきたら **マイク** を許可、**設定 → ショートカット** でホットキーを選ぶ(デフォルトは ⌃⇧Space)。

ガイド付きの手順がほしい? [`docs/TUTORIAL.md`](docs/TUTORIAL.md) を見てください —— インストールから最初の音声入力まで 5 分。

### または AI エージェントに任せる

これを Claude Code、Codex、opencode、Hermes などに貼り付ける:

```text
Install OpenQuack on this Mac:

  brew tap larryxiao/openquack https://github.com/larryxiao/openquack
  brew install --cask openquack

(Or grab the DMG from https://github.com/larryxiao/openquack/releases
and drag it into /Applications; first open right-click → Open → Open.)

Then launch /Applications/OpenQuack.app, grant Microphone, and pick a
hotkey in Settings → Shortcut. Default ⌃⇧Space.
```

その他のオプション(アンインストール、ソースからのビルド、初回起動でダウンロードされるもの):[`docs/INSTALL.md`](docs/INSTALL.md)。

## 謝辞

OpenQuack は、寛大なオープンソースの仕事の肩の上に立っている。深く感謝します:

- [**OpenAI Whisper**](https://github.com/openai/whisper) —— これすべてを可能にした音声モデル。
- [**WhisperKit**](https://github.com/argmaxinc/WhisperKit) by Argmax —— Apple Silicon 上で速くネイティブに動く Whisper。
- [**KeyboardShortcuts**](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus —— 毎日押しているホットキーの仕組み。
- [**voxt**](https://github.com/hehehai/voxt) —— 同じ志を持つプロジェクト、技術面でたくさん学ばせてもらった。
- [**Typeless**](https://www.typeless.com/) と [**Wispr Flow**](https://wisprflow.ai/) —— クローズドソースのアプリだが、音声優先の入力がどれほど気持ちよくなれるかを示してくれた;同じ感触を、ローカルでオープンに目指している。

そして、issue を立ててくれた人、PR を送ってくれた人、友人に教えてくれた人、みんなに:ありがとう。このアヒルがクワッと鳴くのは、あなたたちがいるから。

## コントリビュート

OpenQuack は **AI ネイティブのオープンソース** —— すべての PR が SPEC を参照し、アトミックなタスクはロードマップから来る。ワークフローはコーディングエージェントにも(同じ道を行く人間にも)優しい設計。

[`AGENTS.md`](AGENTS.md) から始めて、[`docs/ROADMAP.md`](docs/ROADMAP.md) で 🔵 のタスクを選び、ドラフト PR を開く。

裏側:[`TUTORIAL`](docs/TUTORIAL.md) · [`DEVELOPMENT`](docs/DEVELOPMENT.md) · [`ARCHITECTURE`](docs/ARCHITECTURE.md) · [`BENCHMARKS`](docs/BENCHMARKS.md) · [`DESIGN`](docs/DESIGN.md) · [`INSTALL`](docs/INSTALL.md) · [`BLOG`](docs/blog/README.md)。

## ライセンス

MIT —— [LICENSE](LICENSE) を参照。

(翻訳のフィードバックは PR か [GitHub Discussions](https://github.com/larryxiao/openquack/discussions) で歓迎。)
