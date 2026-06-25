# Review And Confidence

A-Brain treats confidence as a governance signal. It helps decide what to review, how to rank search results, and when to warn the user. It is not an absolute truth score.

## Score

```text
0-39    enter dream review; do not cite as stable fact
40-69   usable with caution and evidence warning
70-84   reliable enough for normal claim use
85-100  high confidence; usually needs human accepted/promoted or strong evidence
any     unresolved contradictedBy means disputed
```

## Formula

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

Weights live in `config/a-brain.json`, not inside claims.

## Factors And Events

`confidenceFactors` stores current factor values for a claim. `confidenceEvents` records why factors changed.

Examples:

- `ingest` adds source support and citation coverage.
- `think` adds user confirmation when a user explicitly accepts an answer.
- `dream-review` updates review state after human decision.
- `dream-fix` adds negative-event review inputs for contradiction, stale claim, or broken citation in its preview workflow.
- `learn` can add reuse support when knowledge becomes part of a promoted skill.

## Page Vs Claim

Page frontmatter should remain compact:

```yaml
confidenceScore: 72
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25
claimSetPath: knowledge/.claims/example.claims.json
confidenceClaimRefs: [claim-001, claim-003]
```

Detailed factors and events belong in a claim block or sidecar JSON.

## Dream Review

All reviewable items go through `dream/review`. There is no standalone `review` module and no separate review queue owned by `learn`.

Review states:

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

Important human decisions must write a diary event.
