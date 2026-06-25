# 初始化

本文件说明用户刚 clone A-Brain 后，如何把它从空模板启动成可用的 agent memory 系统。

## 1. 配置

检查默认配置文件：

```powershell
Get-Content .\config\a-brain.json
```

v1 命令默认读取 `config/a-brain.json`。如需保存本地私有覆盖配置，可另建 `config/a-brain.local.json`；该文件会被 `.gitignore` / `.ignore` 忽略，但当前脚本不会自动合并它。

把 `AGENTS.example.md` 合并到当前 workspace 的 agent 指南中，并确认其中的 `<A_BRAIN_ROOT>` 指向实际 A-Brain 目录。

## 2. 初始化 diary

`diary` 是自动记录层，不是用户手动笔记。先写一个启动事件：

```powershell
.\scripts\diary-event.cmd -Type task_start -Summary "Bootstrap A-Brain"
```

后续建议由 agent task-start / task-end 自动调用。

## 3. 导入项目

如果用户有多个 workspace 或多个项目，初始化时只需要记录基础信息：

- 项目名
- 项目 path
- 当前是否活跃
- README / docs / AGENTS 等可见入口

没有阶段总结也没关系。可以先从 `templates/project.md` 复制到 `knowledge/projects/<slug>.md`。

## 4. 导入历史会话

历史会话优先进入 `diary`，不是 `library`。

v1 建议流程：

```text
detect   探测常见 agent 会话目录或用户给定路径
inspect  读取少量样本，判断 timestamp / role / message / tool / path / command
confirm  用户确认导入来源、时间范围和 workspace 过滤
import   硬编码导入 diary/events，默认不调用 LLM
derive   后续派生 turns / sessions
extract  显式要求时再从 session 中抽取 notes
```

不同 agent 的会话路径和格式差异很大，所以这一阶段更适合优先做 adapter：

```text
diary/adapters/
  codex/
  claude-code/
  cursor/
  trae/
  hermes/
  openclaw/
  generic-jsonl/
  generic-sqlite/
  generic-markdown/
```

## 5. 导入 library

外部资料、网页、PDF 转写、研究材料、项目资料原文放入：

```text
library/sources
library/projects
library/imports
```

每份高价值资料应尽量补 source contract，可从 `templates/source.md` 开始。

## 6. 建立初始检索状态

导入任何 diary / knowledge / library 内容后运行：

```powershell
.\scripts\think-refresh.cmd
.\scripts\think-health.cmd
```

当前 `think-refresh` 会建立本地 text index。后续版本会接入 chunk、embedding 和更强的路由。

## 7. 启动维护循环

按需运行：

```powershell
.\scripts\dream-maintain.cmd
.\scripts\dream-review.cmd -Report
```

`dream-maintain` 默认只报告，不自动修复文件。后续 `dream-fix` 必须先预览，再由用户确认写入。

## 8. 运行发布自检

```powershell
.\scripts\smoke-test.cmd
```

自检会复制一份临时项目，验证 diary、think、ingest、dream、learn 的关键命令，并检查不会创建 `learn/reviews` 或 `.codex/skills`。
