# A-Brain Agent Rules

把本文件内容合并到目标 workspace 的 `AGENTS.md` 或等价 agent 指南中。路径请按实际 clone 位置调整。

## Reply Language

Unless the user explicitly asks otherwise, reply primarily in Chinese. Keep file paths, commands, API names, and code identifiers in their original form when clearer.

## A-Brain First

Before coding, research, planning, or debugging work, check A-Brain first:

```powershell
<A_BRAIN_ROOT>\scripts\think-query.cmd "<query>"
```

Use relevant hits before model memory. If no useful hit exists, say the gap briefly and continue normally.

When the query is meaningful enough to affect the task, log it as a diary event:

```powershell
<A_BRAIN_ROOT>\scripts\diary-event.cmd -Type think_query -Summary "<query>"
```

## Diary Loop

At task start, write a lightweight event:

```powershell
<A_BRAIN_ROOT>\scripts\diary-event.cmd -Type task_start -Summary "<short task summary>"
```

During execution, record durable workflow actions when they matter:

```powershell
<A_BRAIN_ROOT>\scripts\diary-event.cmd -Type workflow_action -Summary "<what changed>"
```

At task end, record the result:

```powershell
<A_BRAIN_ROOT>\scripts\diary-event.cmd -Type task_end -Summary "<outcome>"
```

## Knowledge Writeback

When the work creates durable facts, decisions, reusable procedures, root causes, or project summaries, write them to `knowledge/notes` or the appropriate `knowledge` subfolder. Skip only trivial status-only turns or facts already written into project files.

## Maintenance Boundaries

- Do not run `dream-maintain` at every task start.
- Run `think-refresh` after bootstrap, large imports, many knowledge writes, or search quality problems.
- Run `dream-review` only when processing review queues or explicitly asked.
- Run `learn` only when the user asks to learn from a source, note, process, or skill.

## Runtime Skill Boundary

`knowledge/skills` stores document-state skills. Do not install runtime skills into an agent-specific runtime directory unless the user explicitly approves that install.
