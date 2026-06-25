# A-Brain

A-Brain `v0.1.0-beta.1` 是首个公开试用版。

A-Brain 是面向 AI coding agent 的本地知识与记忆系统。它把工作记录、资料库、知识库、检索路由、维护审查和技能学习拆成七个一等模块：

```text
diary      记录 agent 工作事件，并派生 turn / session
library    保存外部资料、原始证据和导入内容
ingest     将 library 编译为可追溯 notes 和 concept candidates
knowledge  保存人类可读的 notes / projects / processes / concepts / skills
think      进入 agent 对话循环的检索与路由层
dream      维护、健康检查、lint、review、纠错和晋升候选
learn      用户主动触发的 Ctx2Skill 风格高级能力生成层
```

第一版目标不是替换你现有的所有后端，而是提供一个可运行、可配置、可公开分享的模板。底层检索、embedding 或兼容能力可以通过 `think/adapters` 接入，产品层对外统一叫 `think`。

## Release Tracks

- `Public`: 面向 GitHub 公开试用，强调通用模板、文档、examples 和 smoke-test。
- `Personal`: 面向你自己的长期工作流，承载私有 adapter、真实会话导入、实验能力和更快的迭代节奏。

当前仓库默认对外发布的是 `Public` 轨。

## Quick Start

1. 检查默认配置：

```powershell
Get-Content .\config\a-brain.json
```

v1 命令默认读取 `config/a-brain.json`。如需保存本地私有覆盖配置，可另建 `config/a-brain.local.json`；该文件会被忽略，但当前脚本不会自动合并它。

2. 把 `AGENTS.example.md` 中的规则合并到当前 workspace 的 agent 指南中，并把 `<A_BRAIN_ROOT>` 替换成实际 clone 路径。

3. 记录第一个事件：

```powershell
.\scripts\diary-event.cmd -Type task_start -Summary "Initialize A-Brain"
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

7. 跑一遍发布自检：

```powershell
.\scripts\smoke-test.cmd
```

`smoke-test` 会复制一份临时项目并在临时目录里验证 diary、think、ingest、dream、learn 的关键命令，不会把运行产物写进当前源树。

## First Sample

下面的命令会把公开样例复制到当前项目的 `library` 和 `knowledge` 内容目录，用来体验 ingest、learn 和 think 流程。

```powershell
Copy-Item .\examples\sample-source.md .\library\sources\sample-source.md
Copy-Item .\examples\sample-note.md .\knowledge\notes\sample-note.md
.\scripts\ingest-library.cmd -SourcePath .\library\sources\sample-source.md
.\scripts\learn-candidate.cmd -InputPath .\knowledge\notes\sample-note.md -InputType note
.\scripts\think-refresh.cmd
.\scripts\think-query.cmd "local memory workflow"
```

## What Goes Where

- `diary`: 自动记录“发生了什么”，包括 task start/end、检索、写回、命令、文件变更和 review 决策。
- `library`: 原始资料、网页、PDF、外部项目材料、会话导入原文或导出包。
- `ingest`: 把 `library` 中的资料编译成 notes 和 source-driven candidates。
- `knowledge`: 已整理、可长期复用的人类可读知识。
- `think`: agent 每轮任务开始时使用的检索入口。
- `dream`: 不每轮自动运行，用于健康检查、维护、lint、review、纠错和晋升候选。
- `learn`: 用户主动要求“根据某资料学习”时运行，生成高级 skill/process+skill 候选。

## Safety Defaults

- 不把 `dream-fix` 放进默认维护链。
- 不让 `learn` 自动扫描所有资料。
- 不把 `ingest` 的 concept candidate 直接写入稳定 `knowledge/concepts`。
- 不把 `knowledge/skills` 直接等同于 agent runtime skill 安装目录。
- 不把 `confidenceScore` 当成事实正确率或自动覆盖依据。

## Status

当前版本是 v1 runnable template：

- `diary` 支持 event 写入、查询和 turn/session 派生。
- `think` 支持本地 text index、scope routing 和 `brief|normal|deep|auto` 输出。
- `ingest` 支持从 `library` source 生成 note candidate、concept candidate、manifest 和 review item。
- `dream` 支持 health、lint、review、maintain report 和 preview-only fix。
- `learn` 支持用户主动触发 candidate -> review -> promote，不自动安装 runtime skill。

后续版本会继续增强 session adapter、chunk/embedding adapter、更强 ingest compiler 和 Ctx2Skill 风格 learn engine。
