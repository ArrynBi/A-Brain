# 审核与置信度

A-Brain 将 `confidence` 视为审核与使用信号。它用于决定哪些内容需要复审、检索结果如何排序，以及什么时候需要给出额外提醒。它不是事实真伪的绝对分数。

## 分数区间

```text
0-39    enter dream review; do not cite as stable fact
40-69   usable with caution and evidence warning
70-84   reliable enough for normal claim use
85-100  high confidence; usually needs human accepted/promoted or strong evidence
any     unresolved contradictedBy means disputed
```

## 计算方式

```text
z = -0.40
  + 1.20 * ln(1 + independentWeightedSupport)
  + citationCoverageWeight
  + reviewStateWeight
  + userConfirmationWeight
  + inferenceStateWeight
  - 1.40 * unresolvedConflictWeight
  - 0.80 * (1 - freshness) * freshnessSensitivity
  + modelJudgeWeight

confidenceScore = round(100 / (1 + exp(-z)))
```

权重配置保存在 `config/a-brain.json` 中，不直接写在 claims 里。

## 因子与事件

`confidenceFactors` 用来保存一个 claim 当前的因子数值，`confidenceEvents` 用来记录这些因子为什么发生变化。

常见来源：

- `ingest` 会增加 source support 和 citation coverage。
- `think` 会在用户明确认可结果时增加 user confirmation。
- `dream-review` 会在人工决策后更新 review state。
- `dream-fix` 会在预览流程中加入 contradiction、stale claim 或 broken citation 之类的负向审核信号。
- `learn` 会在知识进入 promoted skill 时增加复用信号。

## 页面与 claim

页面 frontmatter 建议保持精简：

```yaml
confidenceScore: 72
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25
claimSetPath: knowledge/.claims/example.claims.json
confidenceClaimRefs: [claim-001, claim-003]
```

更细的因子和事件建议放在 claim block 或 sidecar JSON 中。

## Dream Review

所有可审核内容都通过 `dream/review` 处理。A-Brain 不提供独立的 `review` 模块，也不会为 `learn` 单独维护第二套审核队列。

审核状态：

```text
draft
pending_auto_review
pending_human_review
needs_source
needs_revision
accepted
promoted
rejected
stale
disputed
superseded
```

重要的人工决策应写入 diary event。
