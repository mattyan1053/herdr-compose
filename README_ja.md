# herdr-compose

[English](README.md) | 日本語

[![CI](https://github.com/mattyan1053/herdr-compose/actions/workflows/ci.yml/badge.svg)](https://github.com/mattyan1053/herdr-compose/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/mattyan1053/herdr-compose?sort=semver)](https://github.com/mattyan1053/herdr-compose/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![herdr ≥ 0.7.4](https://img.shields.io/badge/herdr-%E2%89%A5%200.7.4-6f42c1.svg)](https://herdr.dev)

[herdr](https://herdr.dev) の各スペースに Docker Compose のステータス表示と操作を追加するプラグイン。

- 各スペースの compose プロジェクトの状態をサイドバーに表示します
  (`⏵ 10/10` 全部起動中 · `⏵ 8/10` 一部起動 · `⏸ 0/10` 停止中 ·
  `⏹ down` コンテナなし · compose プロジェクトを持たない workspace では
  何も表示しない)。アクションの実行中は進行中の操作が表示されます
  (`⏳ up…` / `⏳ stop…`)— image の pull で `up` が長引くときに効きます。
- スペースごとにキー1つで `toggle`(起動中なら stop、それ以外は start / `up -d`)。
  明示的な `up` / `start` / `stop` / `down` アクションも用意。
- 対話的な `ps` **ポップアップ**(`compose.ps`): フォーカス中スペースの
  `docker compose ps` をライブ表示し、サービスを選んで logs 閲覧・restart・
  start・stop・`up -d`・削除ができます — 1プロジェクトにスコープした小さな
  lazydocker のようなもの。[対話ポップアップ](#対話ポップアップ)を参照。
- worktree の checkout が削除されたら自動でスタックを片付けます
  (`docker compose -p <project> down` 方式なので、`worktree.removed` 発火時点で
  ディレクトリが消えていても動作します)。

すべて workspace の cwd と Docker の compose ラベルだけから判断するため、
リポジトリ側の設定は一切不要です。変更を入れられない(入れたくない)チームの
monorepo でもそのまま使えます。

## なぜ作ったか

複数の AI コーディングエージェントを worktree で並行稼働させるのは簡単ですが、
worktree ごとに10個のコンテナを動かすのは別問題です — ポートは衝突し、メモリは
枯渇します。現実的な答えは「実装は並行、起動中の開発スタックはほぼ排他」に
すること。`stop` はコンテナ・ボリューム・migration 状態を保ったままメモリを
解放するので、スペース間で「生きている」スタックを数秒で切り替えられます。
このプラグインはそのワークフローをキーバインドに載せ、現在の状態をスペース
ごとに可視化します。

## 動作要件

- herdr ≥ 0.7.4(`ps` ポップアップが `plugin pane open --placement popup` を使用)
- Docker Compose v2
- `bash`, `jq`
- `fzf` — 対話的な `ps` ポップアップ用のみ(ステータス表示と他のアクションは
  fzf なしでも動作します)

## インストール

```bash
herdr plugin install mattyan1053/herdr-compose
```

ローカル開発の場合:

```bash
herdr plugin link /path/to/herdr-compose
```

## 設定

`~/.config/herdr/config.toml` のサイドバー行にステータストークンを追加し、
使いたいアクションにキーを割り当てます:

```toml
[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  ["branch", "git_status", "$compose"],
]

[[keys.command]]
key = "prefix+alt+d"
type = "plugin_action"
command = "compose.toggle"

[[keys.command]]
key = "prefix+alt+shift+d"
type = "plugin_action"
command = "compose.down"

[[keys.command]]
key = "prefix+alt+p"
type = "plugin_action"
command = "compose.ps"
```

キーを割り当てていないアクションはシェルから実行できます:
`herdr plugin action invoke compose.<action>` は、フォーカス中の workspace に
対して実行されます。CLI は実行受付を JSON で表示し、アクション本体は非同期に
走ります — 結果はサイドバーのトークンと
`herdr plugin log list --plugin compose` で確認できます。

## アクション

| アクション          | 動作                                                    |
| ----------------- | ------------------------------------------------------- |
| `compose.ps`      | 対話的な `ps` ポップアップを開く(下記参照)             |
| `compose.toggle`  | 起動中 → `stop` · 停止中 → `start` · コンテナなし → `up -d` |
| `compose.up`      | `docker compose up -d`                                  |
| `compose.start`   | `docker compose start`                                  |
| `compose.stop`    | `docker compose stop`(メモリ解放、状態は保持)          |
| `compose.down`    | `docker compose down`                                   |
| `compose.refresh` | サイドバーのステータスを再報告                          |
| `compose.gc`      | 孤児プロジェクトの掃除(下記参照)                       |

## 対話ポップアップ

`compose.ps` は、フォーカス中スペースのプロジェクトの `docker compose ps -a` を
ライブ表示するセッションモーダルなポップアップ(herdr の `plugin pane open
--placement popup` 経由)を開きます。ポップアップは workspace ディレクトリで
動くので、常にそのスペースの compose プロジェクトを対象にします — 設定は不要です。

キーは**修飾なしの単キー**にしています — 端末互換性が最も高い選択です
(macOS の Option/Alt やスマホ・SSH 経由の端末は Meta キーを化けさせがちですが、
素の英字と Shift+英字はどの端末も確実に送ります)。規約は
**小文字 = 選択中の対象 / 大文字 = プロジェクト全体**:

| キー            | 対象      | 動作                                            |
| --------------- | -------- | ----------------------------------------------- |
| `Enter` / `l`   | サービス  | ページャ(`less`)で logs 閲覧                     |
| `f`             | サービス  | logs を追従(`logs -f`; `Ctrl-C` で戻る)         |
| `r`             | サービス  | `restart`                                       |
| `s`             | サービス  | `start`                                         |
| `t`             | サービス  | s`t`op(停止)                                    |
| `u`             | サービス  | `up -d`                                         |
| `x`             | サービス  | `rm -sf`(削除 — サービス単位の `down` 相当)     |
| `R` `S` `T` `U` | 全体      | 同じ操作をプロジェクト全体に                     |
| `D`             | 全体      | プロジェクト全体を `down`(確認あり)             |
| `/`             | —        | 一覧を絞り込み(`Esc` で検索を抜ける)            |
| `p`             | —        | logs プレビューの表示切替                        |
| `Ctrl-L` / `F5` | —        | 一覧を再取得                                     |
| `Tab`           | —        | 行をマーク(サービス操作はマークした全てに適用)   |
| `q` / `Ctrl-C`  | —        | ポップアップを閉じる                             |

サービス操作はマークした行(`Tab` で複数マーク)、何もマークしていなければ
ハイライト中の行を対象にします。大文字(全体)キーは選択を無視するので、
一覧が空(まだ何も起動していない)でも動きます。

既定では一覧はライブ絞り込みではなく、英字がコマンドとして働きます。絞り込みは
`/` で開始し、`Esc` でコマンドモードに戻ります。

`down` についての注意: `docker compose down` はプロジェクト全体の操作で、
サービス引数を取りません。サービス単位で「停止して削除」する相当の操作は
`x`(`docker compose rm -sf <service>`)です。

## 孤児プロジェクト

herdr 経由で worktree を削除した場合は自動的に
`docker compose -p <project> down` が走ります。しかし herdr の *外* で削除された
worktree(シェルやエージェントによる `git worktree remove`、`rm -rf`、herdr
停止中の削除)はイベントを発火しないため、コンテナが残ってしまいます。`gc` は
このケースをカバーします: ラベルに記録された `working_dir` がディスク上に
存在しない、またはディレクトリは残っていても記録された compose ファイルが
すべて消えているプロジェクトは、二度と `up` できないため片付けの対象に
なります。後者の条件が重要なのは、worktree の削除が中途半端に失敗することが
あるためです: コンテナが bind mount に root 所有のファイルを書くと、herdr が
ディレクトリを消しきれず(失敗した削除では `worktree.removed` も発火しません)、
残骸ディレクトリと稼働中コンテナが残ります。GC は worktree 削除後と
workspace フォーカス時(最大10分に1回)に自動実行され、`compose.gc` で
手動実行もできます。

消滅した checkout の片付けには `down --volumes` を使います: 匿名ボリュームは
どのみち再アタッチされることがなく、同じブランチを後日 checkout し直す場合も
古い状態を引き継ぐより新しいデータベースから始める方が正しいためです。
compose は `external: true` のボリュームを決して削除しないので、共有データは
安全です。明示的な `compose.down` アクションは標準のセマンティクスのまま
(ボリュームは残る)です。

## トラブルシューティング

- アクションが失敗すると、その space のトークンが `⚠ error` になり、詳細は
  `herdr plugin log list --plugin compose` に残ります — herdr は失敗した
  プラグインアクションのトーストを出さないため、確認先はトークンとログです。
- 新しい worktree checkout でよくある失敗: `.env` などの gitignore された
  ファイルは新しい checkout に存在しないため、compose が起動できません。
  メインの checkout からコピーしてください。

## 注意点

- ステータスは workspace/worktree のライフサイクルイベント(created, focused,
  opened)と各アクションの後に更新されます。herdr の裏側で状態が変わった
  コンテナ(クラッシュ、別の場所での `docker` 操作)は、次のフォーカスまたは
  `compose.refresh` で反映されます — 常駐 watcher は今のところありません。
- 初回の `compose.up` はイメージの pull で時間がかかることがあります。重い
  イメージの場合はペイン内で実行してください。
- コンテキスト/ペイロード JSON のフィールド名(`cwd`, `path`, `workspace_id`
  など)は、ありそうな綴りを順に試す防御的な実装にしています。お使いの herdr
  のバージョンで名前が異なる場合は `scripts/lib.sh` を確認してください。

## 開発

```bash
shellcheck -x --severity=warning scripts/*.sh   # lint
bats tests/                                       # テスト（Docker 不要）
```

テストは `docker` と `herdr` をスタブするので、デーモンなしで実行できます。
プロジェクト構成と規約は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## ライセンス

MIT
