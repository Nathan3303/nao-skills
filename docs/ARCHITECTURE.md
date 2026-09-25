# 架构与设计取舍（总览）

> 本文件是**总览**，不是条款出处：协作 / 回执 / 调度这些**会变的条款**以 `.agents/` 为准（单一事实来源）。
> 这里只回答两件事：**为什么这样分层**、**每个机制属于哪一类工程问题**。
> 面向：接手维护者、想改机制的人、要写介绍/文章的人。

## 整体架构

```text
┌──────────────────────────────────────────────────────────────────┐
│ 项目级上下文   AGENTS.md（PM 维护 · pi 自动注入所有会话 · 最高优先级）│
├──────────────────────────────────────────────────────────────────┤
│ 协作层    pi-intercom：派发 / ask-reply / 终态回执闸门             │
│          PM=状态权威：忙闲闸门 → 排队/抢占 → 验收 → 归档 → 回收     │
├──────────────────────────────────────────────────────────────────┤
│ 单一事实来源   roles.yaml（aliases→id→card）· 卡片 frontmatter     │
├──────────────────────────────────────────────────────────────────┤
│ 常驻层（每轮计费，刻意精简）                                      │
│          角色卡：身份/职责/2-3 条最硬红线/按需指针                  │
│          common/：output-format + intercom-protocol              │
├──────────────────────────────────────────────────────────────────┤
│ 按需层（渐进式披露，零常驻 token）                                │
│          skills/   DDD 细节 · codegraph · commit · research      │
│          checklists/（独立于 skills/，避 pi 注册；含回执模板）      │
│          templates/   frontend-ui · AGENTS.md · tasks-state 骨架 │
├──────────────────────────────────────────────────────────────────┤
│ 工具层    nao-fleet.sh（check/status/ensure/close）+ ui-tokens-check│
├──────────────────────────────────────────────────────────────────┤
│ 外部能力  CodeGraph 索引（代码定位，替代 grep 全文扫描）           │
└──────────────────────────────────────────────────────────────────┘
```

### 分层职责

| 层 | 内容 | Token 特性 |
| --- | --- | --- |
| **项目级** | 项目根 `AGENTS.md`（PM 维护 §七）：项目属性/约束，pi 自动注入所有会话 | 常驻（限 <120 行） |
| **协作层** | pi-intercom：`--name` 注册身份，send/ask/reply 线程化；终态回执闸门（`[编号] done(lite\|full)` 必回）；`close` 回收派生会话 | 消息短、详情落盘 |
| **单一事实来源** | `roles.yaml` 管别名→角色；卡片 frontmatter `version` 管版本；两处互相校验（`check`） | 无重复维护 |
| **常驻层** | 6 张角色卡（65–198 行）+ 2 份 common 规范——每轮每会话计费，**刻意保持最小** | 最贵，最小化 |
| **按需层** | skills + checklists + templates：只有 description 常驻，完整指令按需读取（Agent Skills 标准渐进式披露） | 常态零成本 |
| **工具层** | fleet 拉起/体检/状态（含残留检测）/回收；ui-tokens-check 硬编码色值扫描（可接 CI） | 一次性执行 |
| **外部能力** | CodeGraph：`context` 一次返回相关符号+代码块（实测约 1/17 于 grep+全文） | 查找精准化 |

## 核心设计：Token 优先

1. **常驻最小化**：红线/清单/速查表/派发·回执模板全部按需化到 `checklists/`（独立目录，避开 pi skill 扫描），卡片与 common 只留最硬红线 + 指针。
2. **按需加载**：Agent Skills 渐进式披露——DDD 细节、官方 frontend-design、checklists、回执模板均按需读，不占常驻。
3. **缓存友好**：system prompt 稳定 = 前缀缓存命中（cacheRead 约 1/10 价）；改卡**批量一次到位**，易变内容放消息体不进卡片；`cacheWarming: "idle"` + `/session` 观察。
4. **查找精准**：CodeGraph `context`/`node`/`callers`/`impact` 替代 grep+cat 全文；不可用时降级 grep + `sed` 行段读取（禁 cat 全文）。
5. **上下文生命周期**：worker 任务闭环 → `ensure --force` 重开会话；**PM 是唯一常驻长寿会话，按批次边界重开 + 接续快照落盘**（长上下文丢的是纪律而非事实）。自动压缩只作兜底（摘要不可审计、额外花 token、禁用该次 prompt-cache 写）。

## 上下文三层分层

| 层 | 载体 | 维护者 | 内容 |
| --- | --- | --- | --- |
| **项目级（最高）** | 项目根 `AGENTS.md` | PM（§七） | 项目属性/约束/机制衔接；pi 自动注入所有会话，**优先于角色默认习惯** |
| **团队级** | `roles.yaml` + `common/` | nao-skills 仓库 | 角色清单、协作协议、终态回执、缓存纪律 |
| **角色级** | `prompts/` + `skills/` + `checklists/` | nao-skills 仓库 | 角色身份/边界、按需技能、交付清单 |

各层各写各的、不互相复制；项目已有非空 `AGENTS.md` 时**合并追加**（保留原文 + `## nao 舰队接入` 区块，可回退），不覆盖。

## 机制归属（哪些属于上下文工程）

| 层 | 机制 | 学科归属 |
| --- | --- | --- |
| **上下文工程（内核）** | 三层分层、常驻最小化、渐进式披露、前缀缓存纪律、上下文生命周期（worker 任务闭环重开 / PM 批次边界重开 + 接续快照）、状态外部化（tasks-state.md 五栏 + 接续快照）、CodeGraph 精准检索、两级回执模板（按需）、外部调研（按需，research.md：产品形态归 PM / 模式对照归 arch） | 推理期 token 集合最优 |
| **会话编排** | pi-intercom 派发·ask/reply、忙闲闸门、任务状态机、离线检测重拉、`ensure --task` 派生隔离、`close` 回收（在跑 turn / tasks-state 双闸门） | 多 Agent 协调 |
| **交付治理** | 开工确认闸门、架构签字、AC 五覆盖验收、终态回执硬闸门、GitHub Flow 流水线（Issue / 需求分支 / PR、验收后 RD squash 合并）、发布与仓库治理（Tag Release，gh 优先）、ui-tokens-check | 流程可信性 |

> 上下文工程是**主轴**（「Token 优先」的收益都在这一层）；编排与治理是「让多会话可靠交付」的必要补充。

## 机制细节在哪（本文件不复制）

| 主题 | 出处（单一事实来源） |
| --- | --- |
| 派发 / 忙闲闸门 / 回执闸门 / 回收 / 会话生命周期 | `.agents/common/intercom-protocol.md`、`.agents/skills/pm-operations.md` §一·§三（PM 卡 §六 为硬纪律摘要） |
| 输出与回执红线、可复制模板 | `.agents/common/output-format.md`、`.agents/checklists/comm-templates.md` |
| 任务状态与 PM 接续快照 | `.agents/templates/tasks-state.md.example` |
| Git 提交时机 / 需求分支 / 信息可读性 | `.agents/skills/commit.md` |
| 新需求落地流水线（Issue / 分支 / PR / squash 合并 / 发布 / 离线降级） | `.agents/skills/github-flow.md`、`.agents/skills/pm-operations.md` §一、PM 卡 §十三 |
| 角色红线与交付清单 | `.agents/checklists/*.md` |
| 外部调研（产品形态 / 架构模式对照） | `.agents/skills/research.md`、`.agents/skills/arch-patterns.md` |
| 工具命令与闸门 | `bash .agents/scripts/nao-fleet.sh --help` |
