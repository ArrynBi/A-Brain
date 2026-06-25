# A-Brain Schema

This file defines the v1 document contracts used by `knowledge`, `ingest`, `think`, `dream`, and `learn`.

## Page Frontmatter

Page frontmatter should stay compact and human-readable.

```yaml
---
title: 页面标题
type: note | project | process | concept | skill
tags: [topic]
source: local | url | mixed
updated: 2026-06-25
summary: 一句话说明
status: fresh | validated | promoted | superseded | archived
confidenceScore: 0-100
confidenceFormulaVersion: a-brain-confidence-v1
confidenceAggregation: p25 | min_critical | manual_reviewed
claimSetPath:
confidenceClaimRefs: []
provenanceState: extracted | merged | inferred | ambiguous | imported | human-confirmed
inferenceState: direct | inferred | speculative | mixed
citationCoverage: none | partial | good | full
reviewState: draft | pending_auto_review | pending_human_review | needs_source | needs_revision | accepted | promoted | rejected | stale | disputed | superseded
schemaState: compliant | legacy | partial
sourceIds: []
contradictedBy: []
supersedes: []
promoted_to:
reviewQueueRefs: []
modelId:
promptVersion:
contentHash:
sourceHashes: []
---
```

Page-level `confidenceScore` is aggregated from claims. Do not store full `confidenceFactors` or `confidenceEvents` in frontmatter unless the document has only one tiny claim.

## Claim Block

Small documents can embed claims in Markdown. Larger documents should use sidecar JSON under `knowledge/.claims`.

```yaml
claims:
  - id: claim-001
    text: A-Brain 应将 knowledge 作为长期知识的 source of truth。
    claimType: architecture
    confidenceScore: 86
    confidenceFormulaVersion: a-brain-confidence-v1
    confidenceFactors:
      sourceSupport: 0.80
      citationCoverageWeight: 0.55
      reviewStateWeight: 0.90
      userConfirmationWeight: 0.00
      inferenceStateWeight: 0.35
      unresolvedConflictWeight: 0.00
      freshnessPenalty: 0.00
      modelJudgeWeight: 0.00
    confidenceEvents:
      - type: human_review_accepted
        at: 2026-06-25T10:00:00+08:00
        actor: human
        factor: reviewStateWeight
        delta: 0.90
    provenanceState: extracted
    inferenceState: direct
    reviewState: accepted
    citations:
      - sourceId: source-001
        path: library/sources/example.md
        startLine: 42
        endLine: 58
    contradictedBy: []
```

## Numeric Confidence

`confidenceScore` is a governance score, not a proof of truth.

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

Recommended interpretation:

```text
0-39    enter dream review; do not cite as stable fact
40-69   usable with caution and evidence warning
70-84   reliable enough for normal claim use
85-100  high confidence; usually needs human accepted/promoted or strong evidence
any     unresolved contradictedBy means disputed
```

## Source Contract

```yaml
---
title: Source title
sourceId: source-20260625-001
sourceType: web | pdf | markdown | chat | code | manual
sourcePath: library/sources/example.md
sourceUrl:
ingestedAt: 2026-06-25T10:00:00+08:00
contentHash: sha256
originalChars: 12000
truncated: false
sourceQuality: primary | secondary | tertiary | unknown
---
```

## Dream Review Item

```json
{
  "id": "review-20260625-001",
  "created_at": "2026-06-25T10:00:00+08:00",
  "item_type": "claim",
  "path": "knowledge/notes/example.md",
  "claim_id": "claim-001",
  "priority": "high",
  "reason": ["low_confidence_score", "missing_citation"],
  "auto_review": {
    "model": "",
    "verdict": "",
    "risk": ""
  },
  "human_review": {
    "state": "pending_human_review",
    "reviewer": "",
    "reviewed_at": "",
    "decision": "",
    "comment": ""
  }
}
```

## Migration

Existing documents may use `schemaState: legacy`. New ingest outputs and new concepts should use `schemaState: compliant` and include claim-level data.
