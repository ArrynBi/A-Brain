# A-Brain

A-Brain `v0.1.0-beta.1` 是首个试用版本。

A-Brain 是面向 AI coding agent 的本地知识与记忆系统。它把工作记录、资料、知识、检索、维护和学习整合在同一套本地目录中，让 agent 在工作中持续查、持续写、持续沉淀。

它适合这样的场景：

- 你希望 agent 在开始任务前先查本地知识，而不是只靠上下文窗口。
- 你希望项目资料、长期知识和工作日志留在本地，并保持人类可读。
- 你希望逐步把一次次任务经验沉淀成可复用的流程、概念和技能。

当前版本提供七个一等模块：

```text
diary      记录 agent 工作事件，并派生 turn / session
library    保存外部资料、原始证据和导入内容
ingest     将 library 编译为可追溯 notes 和 concept candidates
knowledge  保存人类可读的 notes / projects / processes / concepts / skills
think      进入 agent 对话循环的检索与路由层
dream      维护、健康检查、lint、review、纠错和晋升候选
learn      用户主动触发的 Ctx2Skill 风格高级能力生成层
```

第一版旨在提供一个可运行、可配置、可扩展的本地知识与记忆模板，并为后续检索与能力扩展保留清晰入口。

## 可以做什么

- 用 `diary` 记录任务事件，并派生 turn / session 视图。
- 用 `think` 在回答前搜索本地日志、知识和资料。
- 用 `ingest` 把 `library` 中的原始材料编译成 note candidate 和 concept candidate。
- 用 `dream` 做健康检查、lint、review 和维护报告。
- 用 `learn` 把资料或笔记提升为可复用的技能候选。

## Quick Start

1. 查看默认配置：

```powershell
Get-Content .\config\a-brain.json
```

v1 命令默认读取 `config/a-brain.json`。如需保存本地私有覆盖配置，可另建 `config/a-brain.local.json`；该文件会被忽略，但当前脚本不会自动合并它。

2. 把 `AGENTS.example.md` 中的规则合并到当前 workspace 的 agent 指南中，并把 `<A_BRAIN_ROOT>` 替换成实际 clone 路径。

3. 跑一轮初始化：

```powershell
.\scripts\bootstrap-init.cmd -ProjectTitle "Main Workspace" -ProjectPath "C:\path\to\workspace"
```

如果你希望顺手导入样例内容来体验完整链路，可以加上 `-UseExamples`：

```powershell
.\scripts\bootstrap-init.cmd -ProjectTitle "Main Workspace" -ProjectPath "C:\path\to\workspace" -UseExamples
```

4. 查询当前知识库：

```powershell
.\scripts\think-query.cmd "当前项目状态"
```

5. 首次导入资料或写入知识后刷新检索层：

```powershell
.\scripts\think-refresh.cmd
```

6. 主动维护：

```powershell
.\scripts\dream-maintain.cmd
.\scripts\dream-review.cmd -Report
```

7. 跑一遍自检：

```powershell
.\scripts\smoke-test.cmd
```

`smoke-test` 会复制一份临时项目并在临时目录里验证 diary、think、ingest、dream、learn 的关键命令，不会覆盖当前仓库里已有的运行产物。

## 第一次运行

下面的命令会把样例复制到当前项目的 `library` 和 `knowledge` 内容目录，用来快速体验 `ingest`、`learn` 和 `think` 的联动流程。

```powershell
Copy-Item .\examples\sample-source.md .\library\sources\sample-source.md
Copy-Item .\examples\sample-note.md .\knowledge\notes\sample-note.md
.\scripts\ingest-library.cmd -SourcePath .\library\sources\sample-source.md
.\scripts\learn-candidate.cmd -InputPath .\knowledge\notes\sample-note.md -InputType note
.\scripts\think-refresh.cmd
.\scripts\think-query.cmd "local memory workflow"
```

## 模块说明

- `diary`: 工作事件与会话视图。
- `library`: 原始资料与导入内容。
- `ingest`: 从资料到候选知识的编译层。
- `knowledge`: 长期保存的人类可读知识。
- `think`: 每轮任务开始时的检索入口。
- `dream`: 健康检查、lint、review 和维护。
- `learn`: 从资料或笔记生成可复用技能候选。

## Safety Defaults

- 不把 `dream-fix` 放进默认维护链。
- 不让 `learn` 自动扫描所有资料。
- 不把 `ingest` 的 concept candidate 直接写入稳定 `knowledge/concepts`。
- 不把 `knowledge/skills` 直接等同于 agent runtime skill 安装目录。
- 不把 `confidenceScore` 当成事实正确率或自动覆盖依据。

## 当前能力

当前版本已经可以独立运行，当前范围包括：

- `diary` 支持 event 写入、查询和 turn/session 派生。
- `think` 支持本地 text index、scope routing 和 `brief|normal|deep|auto` 输出。
- `ingest` 支持从 `library` source 生成 note candidate、concept candidate、manifest 和 review item。
- `dream` 支持 health、lint、review、maintain report 和 preview-only fix。
- `learn` 支持用户主动触发 candidate -> review -> promote，不自动安装 runtime skill。

后续版本会继续增强 session adapter、chunk / embedding adapter、更强的 ingest compiler，以及更完整的 learn 工作流。
