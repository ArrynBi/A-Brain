# Resolver

`think-query` 通过 intent routing 决定哪一层内容应该优先回答当前问题。

## Layer Mapping

这里需要区分：

- `scope`：用户侧的检索范围概念，用来描述“这次问题更像是在问哪类内容”。
- `layer`：当前 `local-text` 实现内部按路径推断出的分组 id。

当前 index 不包含显式的 `scope` / `layer` 字段；脚本是在查询阶段按路径临时推断 `layer`。当前集合如下：

```text
process        knowledge/processes/*
concept        knowledge/concepts/*
project        knowledge/projects/*
note           knowledge/notes/*
diary_session  diary/sessions/*
diary_turn     diary/turns/*
diary_event    diary/events/*
library        library/*
other          其他路径
```

## Intent Routing

```text
怎么做 / 如何 / 流程 / 步骤              -> intent=process
是什么 / 为什么 / 原则 / 概念 / 定义      -> intent=concept
项目 / 状态 / 进展                       -> intent=project
最近 / 上次 / 昨天 / 今天 / 做过 / 时间    -> intent=diary
证据 / 来源 / 引用 / 原文                 -> intent=source
其他                                      -> intent=general
```

各 intent 的优先 layer 顺序与脚本一致：

```text
process -> process, note, concept, project, diary_session, library, diary_turn, diary_event, other
concept -> concept, note, process, project, library, diary_session, diary_turn, diary_event, other
project -> project, diary_session, note, process, concept, diary_turn, diary_event, library, other
diary   -> diary_session, diary_turn, diary_event, note, project, process, concept, library, other
source  -> library, note, concept, process, project, diary_session, diary_turn, diary_event, other
general -> note, concept, process, project, diary_session, library, diary_turn, diary_event, other
```

如果查询中出现路径、扩展名、命令样式、代码串等特征，header 会追加 `exact-lean` 标记，表示更偏向精确定位。

## Ranking Logic

排序分数由三部分组成：

- `exact`：整句级或强精确命中
- `terms`：查询词项命中数
- `layerBonus`：当前 intent 下的 layer 优先加分

只有 `exact + terms > 0` 的真实文本候选才会进入结果；`layerBonus` 只对当前 intent 排名前几层生效，用来把稳定知识、项目上下文、时间线记录或原始材料按问题类型重新排前，不能单独制造候选。

## Output Modes

```text
brief   紧凑输出少量高置信结果
normal  按 layer 分组输出
deep    按 layer 分组，并显示 exact / terms / layerBonus
auto    默认模式；检索后自动选择 brief、normal 或 deep
```

`auto` 的选择规则是：

- 命中强且集中在很少的 layer，上倾向 `brief`
- 存在候选但 `topScore < 4` 时，走 low-confidence 分支并上倾向 `deep`
- 命中跨多层、结果较多，或查询偏分析时，上倾向 `deep`
- 其余情况使用 `normal`

输出 header 会固定带一行 routing 指标，例如 `topScore`、`strongLayers`、`analysisLean`、`lowConfidence` 与 `reason`，用于解释当前模式选择。

## Stability Notes

- 当用户问稳定原则或可复用流程时，`concept` / `process` 通常应高于普通 `note`。
- 当用户问最近发生了什么时，`diary_session` / `diary_turn` / `diary_event` 通常应高于旧笔记。
- `library` 主要提供原始材料与证据，不自动替代稳定知识层。
