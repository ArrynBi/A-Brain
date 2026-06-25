# dream

`dream` 是 A-Brain 的维护与健康系统。它不在每轮对话前运行，而是在导入资料、检索质量下降、需要整理记忆或审核候选时主动运行。

## Subsystems

```text
reports     维护报告
candidates  usage-driven process/concept candidates
lint        结构 lint 和语义 lint 候选
correction  思考纠错候选
review      唯一审核队列
```

`review` 是 `dream` 的子系统，不是一等模块。

## Commands

- `scripts\dream-lint.cmd`: 运行纯扫描结构检查，默认写出 `dream/lint/lint-report.json` 和 `dream/lint/lint-report.md`。
- `dream/lint/` 下的 report 文件属于 runtime output，不应作为源资料维护；源树只保留 `.gitkeep` 占位。
- `dream-lint` 只报告 broken links、frontmatter、slug、status/confidenceScore、citation 等结构问题，不做自动修复；普通 fenced code example 仍跳过，但 `## Claims` 下的 fenced `yaml` / `yml` 会继续扫描独立 `path:` citation key。
- `scripts\dream-fix.cmd`: 基于 `dream/lint/lint-report.json` 生成 preview-only 修复建议，默认写到 `dream/correction/` 下的 `dream-fix-preview-<timestamp>.json` 和 `.md`。
- `dream-fix` 不自动写源文档，不修改 review queue，不写 stable knowledge；它只是给 `dream-maintain` 后的人类可审修复入口。
- `dream-fix -OutDir` 只能写到 `dream/correction/` 内部；像 `.\knowledge\notes` 这样的稳定区域路径会直接报错且不写文件。
- `dream/correction/` 下的 preview 文件属于 runtime output，不应作为源资料维护；源树只保留 `.gitkeep` 占位。
