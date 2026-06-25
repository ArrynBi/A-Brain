# think

`think` 是 A-Brain 在 agent 对话循环中的检索与路由层，负责从 `knowledge`、`diary`、`library` 等本地内容里找候选结果，并按查询意图决定优先展示哪一层。

## Commands

```text
think-query.cmd    查询与路由入口
think-refresh.cmd  一键刷新入口，内部执行 sync + embed
think-sync.cmd     同步新增、修改、删除内容
think-embed.cmd    建立或刷新本地 text index
think-health.cmd   检查检索层健康
```

默认 task-start 只运行 `think-query`。`think-refresh` 只在 bootstrap、大量写入、检索异常或 dream 维护时运行。

## Query Usage

```powershell
.\scripts\think-query.cmd [-Mode brief|normal|deep|auto] "<query>"
```

- `auto` 是默认值。
- 旧调用 `.\scripts\think-query.cmd "<query>"` 仍兼容，本质上等价于 `-Mode auto`。

## Output Modes

- `brief`：紧凑输出，最多展示较少的高置信命中；适合 task-start 或命中非常集中时快速看结果。
- `normal`：按 layer 分组展示，平衡紧凑度与上下文；适合大多数普通查询。
- `deep`：按 layer 分组，展示更多结果，并额外给出 score breakdown（`exact`、`terms`、`layerBonus`）；适合分析型、跨层问题或排查检索路由。
- `auto`：先完成检索，再根据结果分布自动选择 `brief`、`normal` 或 `deep`。若命中强且集中，会偏向 `brief`；若命中跨多层、结果较多，或查询偏分析，会偏向 `deep`；若存在候选但 `topScore < 4`，会走 low-confidence 分支并切到 `deep`；其余情况走 `normal`。

## Routing Layers

这里要区分两个概念：

- `scope`：用户侧理解的检索范围概念，比如“更像是在问 process / concept / project / diary / source 哪一类内容”。
- `layer`：当前 `local-text` 检索实现里，脚本仅根据文件路径推断出的内部分组 id。

当前 text index 里还没有显式的 `scope` / `layer` 字段；`layer` 是查询时按路径临时推断出来的。

`think-query` 会先根据路径把命中归到以下 layer：

```text
process        knowledge/processes/*
concept        knowledge/concepts/*
project        knowledge/projects/*
note           knowledge/notes/*
diary_session  diary/sessions/*
diary_turn     diary/turns/*
diary_event    diary/events/*
library        library/*
other          其他未命中的路径
```

随后再根据 query intent 调整优先级：

- `process` 意图：优先 `process`，再看 `note`、`concept`、`project`
- `concept` 意图：优先 `concept`，再看 `note`、`process`
- `project` 意图：优先 `project`，再看 `diary_session`、`note`
- `diary` 意图：优先 `diary_session`、`diary_turn`、`diary_event`
- `source` 意图：优先 `library`
- `general`：使用通用默认顺序

优先级来源不是单一规则，而是三部分叠加：

- `exact`：整句或强精确命中
- `terms`：分词后的词项命中数
- `layerBonus`：当前 intent 下该 layer 的优先加分

只有 `exact + terms > 0` 的真实文本候选才会进入结果集；`layerBonus` 只能给已经命中文本的候选加分，不能单独制造候选。

如果查询里带路径、扩展名、命令样式或代码串，输出 header 里会标记 `exact-lean`，表示这次查询更偏精确定位。

header 还会输出 `routing: topScore=... strongHits=... strongLayers=... analysisLean=... lowConfidence=... threshold=... reason=...`，用于解释 `auto` 当前为什么选中对应输出模式。

## Runtime Output

`think-query` 依赖 `think/indexes/text-index.json`。如果 index 缺失，它可能自动调用 `think-embed` 先补索引，然后再查询。

这意味着：

- `think-query` 在“缺 index”场景下可能产生写入；
- 写入目标是 `think/indexes/text-index.json`；
- 该文件属于 runtime output，不是公开源树里的手写知识文档。
