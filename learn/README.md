# learn

`learn` 是用户主动触发的 Ctx2Skill 风格高级能力生成层。

它从指定的 `source`、`note`、`process` 或 `skill` 单文件输入生成候选：

- candidate skill
- candidate process + skill
- candidate skill improvement
- rare agent-loop rule candidate

所有候选先进入 `learn/candidates`。需要人工决策的候选同步到 `dream/review`，确认后才进入 `knowledge/skills`。

## v1 Flow

1. 用户主动运行 `learn-candidate`
2. 输入必须是一个 `.md` 或 `.txt` 文件
3. 脚本生成 deterministic candidate markdown 到 `learn/candidates`
4. 同步或复用一个 `dream/review/queue.json` item，`item_type=learn_candidate`
5. 人工在 `dream/review` 或外部流程里决定接受
6. 用户主动运行 `learn-promote`
7. 文档态 skill 发布到 `knowledge/skills`
8. 同时写一份 promotion record 到 `learn/promoted`

## Commands

```powershell
.\scripts\learn-candidate.cmd -InputPath .\library\sources\sample.md -InputType source
.\scripts\learn-candidate.cmd -InputPath .\knowledge\notes\my-note.md -InputType note -Kind process_skill
.\scripts\learn-promote.cmd -Candidate .\learn\candidates\learn-candidate-sample-1234567890.md -Decision promoted
```

Parameters:

- `learn-candidate`
  - `-InputPath <path>` required
  - `-InputType source|note|process|skill` required
  - `-Title <title>` optional; fallback order is parameter, frontmatter `title`, markdown heading, first non-empty line, filename
  - `-Kind skill|process_skill|skill_improvement|agent_rule` optional; default `skill`
- `learn-promote`
  - `-Candidate <path>` required
  - `-Decision accepted|promoted` required
  - `-InstallRuntime` is intentionally rejected in v1
  - candidate path must be a markdown file under `learn/candidates`

## Candidate Contract

Candidate path format:

```text
learn/candidates/learn-candidate-<slug>-<stableHash>.md
```

Candidate frontmatter keeps these v1 defaults:

- `type: skill`
- `status: fresh`
- `confidenceScore: 40`
- `schemaState: compliant`
- `reviewState: pending_human_review`
- `provenanceState: extracted`
- `inferenceState: inferred`
- `citationCoverage: partial`

Candidate body is deterministic and always contains:

- `Summary`
- `Source`
- `Candidate Skill`
- `Usage Draft`
- `Review Checklist`

## Review Queue Boundary

- `learn` does not create `learn/reviews`
- `dream/review` is the only review queue
- pending dedupe reuses an existing `learn_candidate` item when candidate path matches or when `source_path + kind` matches
- `dream/review/state.json` counts are refreshed after candidate creation and promotion

## Promotion Boundary

- `learn-promote` only publishes to `knowledge/skills`
- runtime install is out of scope for v1
- `-InstallRuntime` must fail before any write
- promotion also writes a readable record to `learn/promoted`
- promotion updates the matched `dream/review` item to `promoted` when the candidate path is found
- promotion never overwrites an existing `knowledge/skills/<slug>.md`; collisions use a `-2`, `-3` style suffix
- promotion refuses to publish the same candidate again after its review item is already `promoted`
- arbitrary markdown outside `learn/candidates` cannot be promoted
