# diary

`diary` 是 A-Brain 的自动工作日记。它记录 agent 工作过程中发生过什么，并把细粒度 event 派生为 turn 和 session。

## Layers

```text
events    append-only JSONL event stream
turns     task action units derived from events
sessions  continuous topic contexts derived from turns
```

## Commands

```powershell
.\scripts\diary-event.cmd -Type task_start -Summary "Start task"
.\scripts\diary-query.cmd -Limit 5
.\scripts\diary-derive.cmd
```

`diary-event` appends validated JSONL events. `diary-query` reads the event stream with filters such as `-Type`, `-Since`, `-Until`, `-Limit`, and `-Contains`. `diary-derive` creates v1 `turns.json` and `sessions.json` views from the event stream.

For payloads, `-PayloadJson` must be strict JSON object text. When calling through `.cmd` and the shell may strip JSON quotes, use `-PayloadJsonBase64` with UTF-8 JSON encoded as base64.

## Event Shape

```json
{
  "id": "evt_20260625_000001",
  "timestamp": "2026-06-25T10:00:00+08:00",
  "type": "task_start",
  "summary": "Initialize A-Brain",
  "actor": "agent",
  "source": "diary-event",
  "workspace": "<WORKSPACE_ROOT>",
  "payload": {}
}
```

Every event must have a timestamp. Turns and sessions should keep `start_time`, `end_time`, and source event ids.

## V1 Derivation

- A turn is normally a `task_start` through the next `task_end`.
- Isolated workflow or service events become `auto_turn` entries.
- A session is one batch view over the local event stream in v1.
- Future session adapters belong under `diary/adapters`.
