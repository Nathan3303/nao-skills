# 96a-naming-scope 观察项台账（BR8 · #96 步 2a）

- 编号：#96 步 2a（分支 `feat/96a-naming-scope`）· 类型：机制型（命名契约）· 交接口径：`docs/reports/96a-naming-contract.md`
- 本批范围：报告 §0 契约四符号 · §1–§2 13 必改点 · §4 文案 6 处 · §6 C1/C2/C3（用例 `tests/t4/cases/28-naming-contract.sh`）
- 本文件只记**本批不修**的观察项；已修项见 PR #99 描述与用例 28 断言。

## 一、观察项

- `O1`｜现象 = `ensure` 的判重不看下游卡 role：`fleet_roles_init` 不带 `--cards`（避免为判重引入 glob/IO 与 `CARD_SET_MAX` 告警）⇒ 卡会话名在 `running_verdict` 里 parse 成 `ERR` ⇒ 同 core 的跨仓卡会话**不判重**（首仓已起 `sec-review`，第二仓再 `ensure --card` 仍会拉起第二个）。｜来源 = #96 步 2a 第二轮 QA 的 P3-1｜严重度 = P3（静默重复而非崩溃；**旧行为延续、非回归**——`2692b42` 同样不判）｜出口 = **观察**（本批不动：修它会改卡路径初始化与判重语义，需单独测 `--cards` 对 `running_verdict`／`CARD_SET_MAX` 告警面的影响）｜到期 = **2027-01-31**（复核触发：步 2b herdr 后端落地后，或任一仓实际出现「卡会话跨仓重复」；届时优先在 `running_verdict` 里改用「目标 role 临时登记」而非全局 `--cards`）。
- `O2`｜现象 = `fleet_scope_slug` 目前只被用例 28 与契约单测消费，生产路径**尚未**自动取 slug（scope 只来自 `--scope` / `.agents/fleet-scope`）。｜来源 = 报告 §0「可换面仅后两个符号」｜严重度 = —（设计内：二期才允许替换 scope 的**来源**与归一化）｜出口 = **观察**（二期若做「自动按仓名生成 slug」，直接接本函数；其 worktree 不分裂判据已由用例 28 ⑤b 守住）｜到期 = **2027-01-31**。

> 字段固定顺序：编号 / 现象+来源 / 严重度 / 出口 / 到期（一行一条；技能 @.agents/skills/task-completion.md §三）。

## 二、已在本批修掉的同族问题（防重复报）

- 命名预算不自洽（QA P2-1）：卡 core 32 + `@` + scope 16 = 49 > 48 时名字可拉起但 `status` 整条消失 ⇒ 已改为 `ensure` 相位 1 用 `fleet_name_parse` 复核 builder 输出，非 `OK` 且建 pane 之前 `die`（用例 28「P2-1」组：49 拒 / 48 起 + 可见）。
- 常驻「裸名 + 带 scope」同场时带 scope 那条不显示（QA P3-2）⇒ 已改为两条都显示（用例 28「P3-2」组）。
- `status` 显示行手拼名字（QA P3-3①）⇒ 已改走 `fleet_name_build`。
- C3② lint 对 `core=` 盲区（QA P3-3②）⇒ 已扩展扫描面到 `(name|disp|core)`，并把所有 core 拼接收进 `fleet_core_build`。
- **上一条第一版仍「声明比判据强」**（QA P3-a）：判据只认花括号形 `${x}-${task}`，而历史缺陷的真实写法是 `core="$NAME-$task"`（无花括号）⇒ 对 `7b08214` 只报 1 条。现已改为 `(^|[^A-Za-z0-9_])(name|disp|core)="?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?-\$(\{)?(task|TASK)`，六种拼接写法**全抓**（用例 28 的「形态矩阵」断言），真脚本仍 0；负控 A2 已改成**无花括号形**（与历史缺陷同形）。
- 超预算 die 文案的事实错（QA P3-b）：卡 core 32 + `--task T1` 曾被写成「35 字符 > 48」并指路「缩 scope」（死路）⇒ 现按原因分支：卡 `core > 32` 走独立文案（只提示缩短 `--task` / 换更短的卡 role），总长超限才提示缩 scope。
