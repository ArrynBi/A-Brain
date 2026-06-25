# ingest

`ingest` 是从 `library` 到 `knowledge` 的可信编译管线。

## Responsibilities

- 扫描新增或变更的 source。
- 记录 source contract、hash、manifest 和 run state。
- 生成 `knowledge/notes` 候选。
- 生成 source-driven concept candidates。
- 对低置信、缺 citation、冲突或推断过强的内容写入 `dream/review`。

`ingest` 不直接写入稳定 `knowledge/concepts`。

## `ingest-library`

Phase 4 提供了最小可运行执行器：

```powershell
.\scripts\ingest-library.cmd
.\scripts\ingest-library.cmd -SourcePath .\library\sources\sample.md
.\scripts\ingest-library.cmd -SourcePath .\library\sources -Limit 5
.\scripts\ingest-library.cmd -SourcePath .\library\sources -DryRun
```

参数：

- `-SourcePath <path>`: 单个 `.md` / `.txt` 文件或目录；默认 `library/sources`
- `-Limit <n>`: 目录扫描上限；默认 `20`
- `-DryRun`: 只输出计划，不写任何文件

当前行为：

- 扫描 `.md`、`.txt`
- 读取 UTF-8 文本，必要时回退到系统默认编码
- 计算 `sha256`、`bytes`、`chars`、relative path、`lastWriteTimeUtc`
- 为每个 relative path 计算稳定 `stablePathHash = sha256(relativePath).Substring(0,10)`
- 尝试解析简单 YAML frontmatter 单行 `key: value`
- 对比最新 `ingest/manifests/library-manifest-*.json`，为每个 source 计算 `previousHash`、`diffStatus`、`hashChanged`
- 生成 note candidate、source-driven concept candidate、manifest、run 记录
- 更新 `dream/review/queue.json` 与 `dream/review/state.json`

写入位置：

- `ingest/manifests/library-manifest-<run-token>.json`
- `ingest/runs/ingest-library-run-<run-token>.json`
- `knowledge/notes/ingest-<source-id-slug>-<stable-path-hash>.md`
- `ingest/candidates/concepts/concept-candidate-<source-id-slug>-<stable-path-hash>.md`
- `dream/review/queue.json`
- `dream/review/state.json`

其中 `<run-token>` 默认是 `yyyyMMdd-HHmmss-fff`，如果极短时间内再次执行仍命中同名文件，会自动追加唯一后缀，避免覆盖已有 manifest/run。

manifest entry 现在额外包含：

- `previousHash`: 最新上一版 manifest 里同 `sourceId`，或同 `sourcePath` 的 hash；没有历史时为空字符串
- `diffStatus`: `new | changed | unchanged`
- `hashChanged`: 布尔值；仅当存在上一版且 hash 不同时为 `true`
- `stablePathHash`: 基于 repo-relative `sourcePath` 的稳定路径 hash

## Review Boundary

- `ingest-library` 只生成候选，不直接写稳定 `knowledge/concepts`
- note candidate 与 concept candidate 默认 `reviewState: pending_human_review`
- dream review queue item 使用 `item_type: ingest_candidate`
- 缺失 frontmatter `sourceId` 时，fallback identity 使用 `source-path-<slug>-<stablePathHash>`，只依赖 repo-relative path，不依赖 mtime 或内容
- 重复 ingest pending item 时，若 `item_type=ingest_candidate` 且 `source_id == SourceId` 或 `source_path == RelativePath`，会复用已有 review item
- review item 会保存 `source_path`
- review id 默认是 `review-<timestamp>-<source-id-slug>-<stablePathHash>`；若同一 batch 内碰撞，会自动追加 `-2`、`-3`
- candidate note / concept 文件名同样带 `stablePathHash`；若同一 batch 内仍碰撞，也会自动追加 `-2`、`-3`

## Dry Run

`-DryRun` 会打印：

- 将处理的 source
- 将写入的 manifest / run 路径
- 每个 source 的 `diffStatus`
- 将覆盖的 note / concept candidate 路径
- 将复用或创建的 review item id

它不会创建目录，也不会修改 queue、state、manifest、run 或候选 Markdown。
