# 命令说明

## 自检

```powershell
.\scripts\smoke-test.cmd
.\scripts\smoke-test.cmd -KeepTemp
```

在项目临时副本中运行完整自检，验证 diary event/query/derive、think refresh/query/health、ingest、dream lint/review/maintain、learn candidate/promote、JSON 解析，以及关键边界约束。

默认在成功后删除临时副本。排查问题时可以使用 `-KeepTemp` 保留现场。

## 日常循环

这些命令适合接入每一轮任务循环。

```powershell
.\scripts\diary-event.cmd -Type task_start -Summary "<task>"
.\scripts\think-query.cmd "<query>"
.\scripts\diary-event.cmd -Type task_end -Summary "<outcome>"
```

Payload 必须是 JSON object。跨 shell 场景下如果 JSON 引号容易出错，可以通过 `-PayloadJsonBase64` 传递 UTF-8 JSON。

```powershell
.\scripts\diary-query.cmd -Limit 5
```

读取最近的 diary events。可选过滤参数包括 `-Type`、`-Since`、`-Until`、`-Limit` 和 `-Contains`。

```powershell
.\scripts\diary-derive.cmd
```

从 event stream 派生 `diary/turns/turns.json` 和 `diary/sessions/sessions.json`。这些文件属于运行时视图，不是手写知识源。

## Think

```powershell
.\scripts\think-query.cmd "怎么处理当前项目状态"
```

搜索本地 `diary`、`knowledge` 和 `library`。当前版本使用本地 text index 和意图路由。

```powershell
.\scripts\think-query.cmd -Mode brief "当前项目状态"
.\scripts\think-query.cmd -Mode normal "最近做过什么"
.\scripts\think-query.cmd -Mode deep "这个流程的证据和相关笔记"
.\scripts\think-query.cmd -Mode auto "think-query.ps1"
```

输出模式：

- `brief`: 紧凑输出少量高置信结果
- `normal`: 按 layer 分组展示结果
- `deep`: 按 layer 分组展示更多结果，并显示 `exact` / `terms` / `layerBonus`
- `auto`: 默认模式；检索后自动选择 `brief`、`normal` 或 `deep`。若存在候选但 `topScore < 4`，会走 low-confidence 分支并切到 `deep`

路由层级：

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

输出 header 会带 routing 指标，便于解释 `auto` 当前为什么选择 `brief`、`normal` 或 `deep`。

`think-query` 可能在 index 缺失时自动调用 `think-embed`，因此会写入 `think/indexes/text-index.json`。该文件属于运行时输出，不应当被当作手写知识源。

```powershell
.\scripts\think-sync.cmd
```

跟踪本地文件变化，并写入 `think/indexes/sync-state.json`。

```powershell
.\scripts\think-embed.cmd
```

构建 `think/indexes/text-index.json`。当前版本提供的是 text index，后续可以替换或扩展为 embedding 方案。

```powershell
.\scripts\think-refresh.cmd
```

运行 sync + embed。适合在初始化、批量导入、集中写入知识后，或检索效果异常时使用。

```powershell
.\scripts\think-health.cmd
```

写入 `think/reports/health-report.json`，包含五个维度的健康报告：

- `sourceCoverage`: `library/sources` 数量、knowledge `notes/projects/processes/concepts/skills` 数量、以及 knowledge 页面 `sourceIds` / `sourceHashes` 覆盖率
- `indexFreshness`: `think/indexes/text-index.json` 与 `think/indexes/sync-state.json` 是否存在、`updatedAt`、`ageMinutes`、以及 text index entry count vs. indexable file count
- `citationCoverage`: knowledge 页面 `citationCoverage: none|partial|good|full` 统计，以及 `claim` / `citation(s)` 关键词辅助计数
- `reviewBacklog`: `dream/review/queue.json` 的 `human_review.state` 分布、总数与 `pending_human_review`
- `querySaveRate`: diary event stream 中 `think_query` 与 `note_written` 的保存比率

写入边界：

- `think-query.cmd` 通常是读操作，但在缺少 index 时可能触发一次 `think-embed`
- `think-sync.cmd` 写 `think/indexes/sync-state.json`
- `think-embed.cmd` 写 `think/indexes/text-index.json`
- `think-refresh.cmd` 会组合触发上述写入
- `think-health.cmd` 写 `think/reports/health-report.json`

## Dream

```powershell
.\scripts\dream-maintain.cmd
```

运行四步维护流程：

1. `think-refresh.ps1`
2. `think-health.ps1`
3. `dream-lint.ps1`
4. `dream-review.ps1 -Report`

它会写入 `dream/reports/dream-maintain-<timestamp>.md`，其中包含 `Apply: false`、四步命令输出，以及可用时的 JSON 汇总：

- `Health Summary` from `think/reports/health-report.json`
- `Lint Summary` from `dream/lint/lint-report.json`
- `Review Summary` from `dream/review/state.json`

`dream-maintain` 不会自动修复内容，也不会直接写入稳定知识。

```powershell
.\scripts\dream-fix.cmd
.\scripts\dream-fix.cmd -ReportPath .\dream\lint\lint-report.json
.\scripts\dream-fix.cmd -OutDir .\dream\correction
```

根据 lint 报告生成仅预览的 correction report。默认参数如下：

- `ReportPath`: `dream/lint/lint-report.json`
- `OutDir`: `dream/correction`

输出文件：

- `dream/correction/dream-fix-preview-<timestamp>.json`
- `dream/correction/dream-fix-preview-<timestamp>.md`

说明：

- `dream-fix` does not modify source markdown, `dream/review/queue.json`, or stable knowledge.
- Preview items include `issueType`, `severity`, `path`, `target`, `suggestedAction`, `applyable=false`, and `reason`.
- If the lint report is missing, the command exits 0 with a clear prompt to run `dream-lint` first.
- `-OutDir` must stay inside `dream/correction`; paths such as `.\knowledge\notes` are rejected before any preview file is written.
- `dream/correction` is runtime output and should not be treated as hand-authored source content.

```powershell
.\scripts\dream-review.cmd -Report
```

从 `dream/review/queue.json` 刷新 review summary/state，并写入 review report。这个命令不是纯读操作。

```powershell
.\scripts\dream-review.cmd -Item review-20260625-001 -Decision accepted -Comment "证据足够"
```

更新一个 review item，并向 diary 写入 `review_decision` event。

## Ingest

```powershell
.\scripts\ingest-library.cmd
.\scripts\ingest-library.cmd -SourcePath .\library\sources\sample.md
.\scripts\ingest-library.cmd -SourcePath .\library\sources -Limit 5
.\scripts\ingest-library.cmd -SourcePath .\library\sources -DryRun
```

当前 ingest 入口是 `ingest-library`。它会扫描单个 `.md` / `.txt` 文件，或 `library/sources` 下的目录，计算 source hash，对比最新的 `ingest/manifests/library-manifest-*.json`，并写入候选和运行时输出。

参数：

- `-SourcePath <path>`: 单个 `.md` / `.txt` 文件或目录；默认 `library/sources`
- `-Limit <n>`: 目录扫描上限；默认 `20`
- `-DryRun`: 只打印计划，不写文件

写入内容：

- `ingest/manifests/library-manifest-<run-token>.json`
- `ingest/runs/ingest-library-run-<run-token>.json`
- `knowledge/notes/ingest-<source-id-slug>-<stable-path-hash>.md`
- `ingest/candidates/concepts/concept-candidate-<source-id-slug>-<stable-path-hash>.md`
- `dream/review/queue.json`
- `dream/review/state.json`

说明：

- manifest entry 会记录 `contentHash`、`previousHash`、`diffStatus`、`hashChanged`
- manifest entry 和 run source 都会记录 `stablePathHash`
- 缺失 frontmatter `sourceId` 时，fallback identity 基于 repo-relative `sourcePath`，不依赖 mtime 或内容
- run `sources` 也会带 `diffStatus`
- `<run-token>` 默认包含毫秒，必要时追加唯一后缀，避免快速重复执行覆盖 manifest/run

审核边界：

- `ingest-library` 只生成 note candidate 与 source-driven concept candidate
- 不直接写稳定 `knowledge/concepts`
- 候选默认走 `dream/review`，`reviewState` 为 `pending_human_review`
- 重复 ingest 同一 `sourceId` 或同一 `source_path` 时会复用已有 pending review item，避免 review queue 无限制重复堆积

## Learn

`learn` 是用户主动触发的能力。适合在用户明确要求“根据某个 source、note、process 或 skill 学习”时运行。当前版本使用 `learn/candidates` 保存候选，并通过 `dream/review` 处理人工决策。

```powershell
.\scripts\learn-candidate.cmd -InputPath .\library\sources\sample.md -InputType source
.\scripts\learn-candidate.cmd -InputPath .\knowledge\processes\weekly-close.md -InputType process -Kind process_skill
```

从一个 `.md` 或 `.txt` 文件生成一份确定性的 candidate 文档，并同步一个 `learn_candidate` item 到 `dream/review/queue.json`。

参数：

- `-InputPath <path>`: required single file path
- `-InputType source|note|process|skill`: required
- `-Title <title>`: optional override; otherwise infer from frontmatter title, heading, first non-empty line, or file name
- `-Kind skill|process_skill|skill_improvement|agent_rule`: optional; default `skill`

写入内容：

- `learn/candidates/learn-candidate-<slug>-<stableHash>.md`
- `dream/review/queue.json`
- `dream/review/state.json`

说明：

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

把一个通过 review 的 candidate 发布到 `knowledge/skills`，并写入一份可读的 promotion record。

参数：

- `-Candidate <path>`: required candidate markdown path
- `-Decision accepted|promoted`: required; only these values can publish
- `-InstallRuntime`: rejected in v1 before any write
- candidate must be a markdown file under `learn/candidates`

写入内容：

- `knowledge/skills/<slug>.md`
- `learn/promoted/<slug>-<timestamp>.md`
- `dream/review/queue.json`
- `dream/review/state.json`

说明：

- promoted knowledge document preserves the candidate body
- promoted knowledge frontmatter sets `reviewState: promoted`, `status: promoted`, and `schemaState: compliant`
- matched `dream/review` item is updated to `promoted` when found by candidate path
- the command never writes `.codex/skills` or any runtime skill install directory
- the command refuses arbitrary markdown outside `learn/candidates`
- the command never overwrites an existing `knowledge/skills/<slug>.md`; collisions use a `-2`, `-3` style suffix
- the command refuses to publish the same candidate again after its review item is already `promoted`
