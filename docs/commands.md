# Commands

## Smoke Test

```powershell
.\scripts\smoke-test.cmd
.\scripts\smoke-test.cmd -KeepTemp
```

Runs a release-oriented smoke test in a temporary copy of the project. It verifies diary event/query/derive, think refresh/query/health, ingest, dream lint/review/maintain, learn candidate/promote, JSON parsing, and key safety boundaries.

By default the temporary copy is removed after success. Use `-KeepTemp` when debugging a failure.

## Daily Agent Loop

These commands are intended for every task loop.

```powershell
.\scripts\diary-event.cmd -Type task_start -Summary "<task>"
.\scripts\think-query.cmd "<query>"
.\scripts\diary-event.cmd -Type task_end -Summary "<outcome>"
```

Payloads must be JSON objects. For cross-shell calls where JSON quoting is fragile, pass UTF-8 JSON through `-PayloadJsonBase64`.

```powershell
.\scripts\diary-query.cmd -Limit 5
```

Reads recent diary events. Optional filters: `-Type`, `-Since`, `-Until`, `-Limit`, and `-Contains`.

```powershell
.\scripts\diary-derive.cmd
```

Derives `diary/turns/turns.json` and `diary/sessions/sessions.json` from the event stream. These are runtime views and should not be treated as hand-authored source files.

## Think

```powershell
.\scripts\think-query.cmd "怎么处理当前项目状态"
```

Searches local `diary`, `knowledge`, and `library`. Current scaffold mode uses a local text index and intent routing.

```powershell
.\scripts\think-query.cmd -Mode brief "当前项目状态"
.\scripts\think-query.cmd -Mode normal "最近做过什么"
.\scripts\think-query.cmd -Mode deep "这个流程的证据和相关笔记"
.\scripts\think-query.cmd -Mode auto "think-query.ps1"
```

Modes:

- `brief`: 紧凑输出少量高置信结果
- `normal`: 按 layer 分组展示结果
- `deep`: 按 layer 分组展示更多结果，并显示 `exact` / `terms` / `layerBonus`
- `auto`: 默认模式；检索后自动选择 `brief`、`normal` 或 `deep`。若存在候选但 `topScore < 4`，会走 low-confidence 分支并切到 `deep`

Routing layers:

```text
process, concept, project, note,
diary_session, diary_turn, diary_event,
library, other
```

说明：

- `scope` 是用户侧的检索范围概念。
- `layer` 是当前 `local-text` 里按路径推断出的内部 id。
- 当前 index 还没有显式的 `scope` / `layer` 字段。
- 只有 `exact + terms > 0` 的文本命中才会成为候选，`layerBonus` 只负责重排，不负责造候选。

输出 header 会带 routing 指标，便于解释 `auto` 当前为什么选 `brief` / `normal` / `deep`。

`think-query` 可能在 index 缺失时自动调用 `think-embed`，因此会写入 `think/indexes/text-index.json`。该文件属于 runtime output，不应当被当作手写知识源。

```powershell
.\scripts\think-sync.cmd
```

Tracks changed local files and writes `think/indexes/sync-state.json`.

```powershell
.\scripts\think-embed.cmd
```

Builds `think/indexes/text-index.json`. In v1 scaffold this is a text index. Future versions can replace or augment it with embeddings.

```powershell
.\scripts\think-refresh.cmd
```

Runs sync + embed. Use after bootstrap, large imports, many knowledge writes, or search quality issues.

```powershell
.\scripts\think-health.cmd
```

Writes `think/reports/health-report.json` with a Phase 5 five-dimension report:

- `sourceCoverage`: `library/sources` 数量、knowledge `notes/projects/processes/concepts/skills` 数量、以及 knowledge 页面 `sourceIds` / `sourceHashes` 覆盖率
- `indexFreshness`: `think/indexes/text-index.json` 与 `think/indexes/sync-state.json` 是否存在、`updatedAt`、`ageMinutes`、以及 text index entry count vs. indexable file count
- `citationCoverage`: knowledge 页面 `citationCoverage: none|partial|good|full` 统计，以及 `claim` / `citation(s)` 关键词辅助计数
- `reviewBacklog`: `dream/review/queue.json` 的 `human_review.state` 分布、总数与 `pending_human_review`
- `querySaveRate`: diary event stream 中 `think_query` 与 `note_written` 的保存比率

Write boundary:

- `think-query.cmd` 通常是读操作，但在缺少 index 时可能触发一次 `think-embed`
- `think-sync.cmd` 写 `think/indexes/sync-state.json`
- `think-embed.cmd` 写 `think/indexes/text-index.json`
- `think-refresh.cmd` 会组合触发上述写入
- `think-health.cmd` 写 `think/reports/health-report.json`

## Dream

```powershell
.\scripts\dream-maintain.cmd
```

Runs a Phase 5 four-step maintenance orchestration:

1. `think-refresh.ps1`
2. `think-health.ps1`
3. `dream-lint.ps1`
4. `dream-review.ps1 -Report`

It writes `dream/reports/dream-maintain-<timestamp>.md` with `Apply: false`, embedded command output sections for all four steps, and JSON-backed summaries when available:

- `Health Summary` from `think/reports/health-report.json`
- `Lint Summary` from `dream/lint/lint-report.json`
- `Review Summary` from `dream/review/state.json`

`dream-maintain` does not auto-fix content and does not write stable knowledge.

```powershell
.\scripts\dream-fix.cmd
.\scripts\dream-fix.cmd -ReportPath .\dream\lint\lint-report.json
.\scripts\dream-fix.cmd -OutDir .\dream\correction
```

Generates a preview-only correction report from a lint report. Defaults:

- `ReportPath`: `dream/lint/lint-report.json`
- `OutDir`: `dream/correction`

Outputs:

- `dream/correction/dream-fix-preview-<timestamp>.json`
- `dream/correction/dream-fix-preview-<timestamp>.md`

Behavior notes:

- `dream-fix` does not modify source markdown, `dream/review/queue.json`, or stable knowledge.
- Preview items include `issueType`, `severity`, `path`, `target`, `suggestedAction`, `applyable=false`, and `reason`.
- If the lint report is missing, the command exits 0 with a clear prompt to run `dream-lint` first.
- `-OutDir` must stay inside `dream/correction`; paths such as `.\knowledge\notes` are rejected before any preview file is written.
- `dream/correction` is runtime output and should not be treated as hand-authored source content.

```powershell
.\scripts\dream-review.cmd -Report
```

Refreshes runtime review summary/state from `dream/review/queue.json` and writes a review report. This is not a pure read operation.

```powershell
.\scripts\dream-review.cmd -Item review-20260625-001 -Decision accepted -Comment "证据足够"
```

Updates one review item and writes a `review_decision` event to diary.

## Ingest

```powershell
.\scripts\ingest-library.cmd
.\scripts\ingest-library.cmd -SourcePath .\library\sources\sample.md
.\scripts\ingest-library.cmd -SourcePath .\library\sources -Limit 5
.\scripts\ingest-library.cmd -SourcePath .\library\sources -DryRun
```

Current ingest entrypoint is `ingest-library`. It scans one `.md` / `.txt` file or a directory under `library/sources`, computes source hashes, compares against the latest `ingest/manifests/library-manifest-*.json`, and writes candidate/runtime outputs.

Parameters:

- `-SourcePath <path>`: 单个 `.md` / `.txt` 文件或目录；默认 `library/sources`
- `-Limit <n>`: 目录扫描上限；默认 `20`
- `-DryRun`: 只打印计划，不写文件

Writes:

- `ingest/manifests/library-manifest-<run-token>.json`
- `ingest/runs/ingest-library-run-<run-token>.json`
- `knowledge/notes/ingest-<source-id-slug>-<stable-path-hash>.md`
- `ingest/candidates/concepts/concept-candidate-<source-id-slug>-<stable-path-hash>.md`
- `dream/review/queue.json`
- `dream/review/state.json`

Behavior notes:

- manifest entry 会记录 `contentHash`、`previousHash`、`diffStatus`、`hashChanged`
- manifest entry 和 run source 都会记录 `stablePathHash`
- 缺失 frontmatter `sourceId` 时，fallback identity 基于 repo-relative `sourcePath`，不依赖 mtime 或内容
- run `sources` 也会带 `diffStatus`
- `<run-token>` 默认包含毫秒，必要时追加唯一后缀，避免快速重复执行覆盖 manifest/run

Review boundary:

- `ingest-library` 只生成 note candidate 与 source-driven concept candidate
- 不直接写稳定 `knowledge/concepts`
- 候选默认走 `dream/review`，`reviewState` 为 `pending_human_review`
- 重复 ingest 同一 `sourceId` 或同一 `source_path` 时会复用已有 pending review item，避免 review queue 无限制重复堆积

## Learn

`learn` is user-initiated. It should run only when the user asks to learn from a source, note, process, or skill. In this scaffold pass, use `learn/candidates` for candidate documents and route human decisions through `dream/review`.

```powershell
.\scripts\learn-candidate.cmd -InputPath .\library\sources\sample.md -InputType source
.\scripts\learn-candidate.cmd -InputPath .\knowledge\processes\weekly-close.md -InputType process -Kind process_skill
```

Creates one deterministic candidate document from one `.md` or `.txt` file and syncs a `learn_candidate` item into `dream/review/queue.json`.

Parameters:

- `-InputPath <path>`: required single file path
- `-InputType source|note|process|skill`: required
- `-Title <title>`: optional override; otherwise infer from frontmatter title, heading, first non-empty line, or file name
- `-Kind skill|process_skill|skill_improvement|agent_rule`: optional; default `skill`

Writes:

- `learn/candidates/learn-candidate-<slug>-<stableHash>.md`
- `dream/review/queue.json`
- `dream/review/state.json`

Behavior notes:

- only one markdown/text file is supported per run
- candidate body is deterministic and contains `Summary`, `Source`, `Candidate Skill`, `Usage Draft`, and `Review Checklist`
- candidate frontmatter defaults to `type: skill`, `status: fresh`, `confidenceScore: 40`, `schemaState: compliant`, `reviewState: pending_human_review`, `provenanceState: extracted`, `inferenceState: inferred`, and `citationCoverage: partial`
- pending dedupe reuses an existing `learn_candidate` review item when the candidate path matches or when `source_path + kind` matches
- no stable write occurs under `knowledge/skills` during candidate generation
- no runtime install directory is touched

```powershell
.\scripts\learn-promote.cmd -Candidate .\learn\candidates\learn-candidate-sample-1234567890.md -Decision promoted
.\scripts\learn-promote.cmd -Candidate .\learn\candidates\learn-candidate-sample-1234567890.md -Decision accepted
```

Publishes one reviewed candidate into `knowledge/skills` and stores a readable promotion record.

Parameters:

- `-Candidate <path>`: required candidate markdown path
- `-Decision accepted|promoted`: required; only these values can publish
- `-InstallRuntime`: rejected in v1 before any write
- candidate must be a markdown file under `learn/candidates`

Writes:

- `knowledge/skills/<slug>.md`
- `learn/promoted/<slug>-<timestamp>.md`
- `dream/review/queue.json`
- `dream/review/state.json`

Behavior notes:

- promoted knowledge document preserves the candidate body
- promoted knowledge frontmatter sets `reviewState: promoted`, `status: promoted`, and `schemaState: compliant`
- matched `dream/review` item is updated to `promoted` when found by candidate path
- the command never writes `.codex/skills` or any runtime skill install directory
- the command refuses arbitrary markdown outside `learn/candidates`
- the command never overwrites an existing `knowledge/skills/<slug>.md`; collisions use a `-2`, `-3` style suffix
- the command refuses to publish the same candidate again after its review item is already `promoted`
