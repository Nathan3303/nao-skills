# #161 派单投递寻址硬化（多仓同名 ⇒ 协议层是唯一防线）

- 状态：待验收 · 更新：2026-11-23 · Owner：rd-infra
- 指针：Issue #161 · 任务 T559 · 分支 `fix/161-dispatch-addressing`（基线 `06756b7`）
- 事故实例：`rd-infra(T557)` 两次 `to: "pm"` 裸名回执 ⇒ 落进 nue-ui 的 `pm` 会话，nao-skills 的 PM 未收到

## TL;DR

- 根因不是插件缺陷：**每仓一个常驻 `pm` 是机制设计**，裸名按**精确名全局解析**；当机器上恰有**一个**该名时
  既不歧义也不报错，**静默投到那个仓**。⇒ 上游 `fail loud` 不覆盖此形态，**协议层是唯一防线**。
- 硬化 5 处（全是既有文本的增量，零新增正文文件）：派单/回执 `to` 一律用**会话 id**（或 `to`+`cwd`），禁裸名跨仓。
- AC5：`pi-intercom` **没有「同名不同仓自动拒投」能力**（歧义拒投 ≠ 跨仓同名拒投）；最接近的是
  `PI_INTERCOM_SCOPE_ID` / `/intercom-pool`（opt-in 命名池），**非按仓自动判定** ⇒ 登记为上游建议，本批不写成「已修」。
- 门禁：`check` rc=0 · `npm test` rc=0（`npm test` 数字见回执）。零角色卡改动 ⇒ 无 bump / 无广播。

## 一、上游事实复核（PM 给的三条，逐条自测，未采信转述）

1. **`to` + `cwd` 语义** ✓ —— `pi-intercom@0.18.1` `README.md:387`：`Without cwd, send/ask resolve it
   globally. With cwd, send/ask require the target to be in that directory.`（同 `README.md:418` `send` 段）。
2. **「歧义拒投」存在** ✓ —— `README.md:643`：`sends to ambiguous names fail`；
   实现 `index.ts:1657-1661`：同名命中 >1 ⇒ `throw new Error('Multiple sessions named ...')`。
3. **本次事故不是歧义** ✓（实测，非推理）—— `intercom list` 现状：
   - 精确名 `pm` 的会话**恰好 1 个**：`01a207c7` @ `~/Projects/nue-ui`
   - nao-skills 的 PM 名为 `pm(T555)`（`01a20244`），nao-todo 为 `pm@nao-todo`（`01a1f926`）
   ⇒ 裸名 `pm` 只命中 neu-ui 那个，`matches.length == 1`，**不触发歧义路径**，静默投递。

   精度补充（比 PM 的表述更硬）：解析顺序是 **id 精确 → 名称精确（case-insensitive）→ id 前缀**，
   **名称前缀回退只在「精确名不存在（E_TARGET_NOT_FOUND）」时启用**（`index.ts:1655-1671` 解析 ·
   `index.ts:1690` 名称前缀回退）。所以只要他仓的 `pm` 在线，`pm` **永远不会**落到 `pm(T555)` —— 该误投是
   **确定性**的，不是偶发。

   取数命令（源码位置在 `~/.pi/agent/npm/node_modules/pi-intercom/`，下称 `<IC>/`；行号均为 `0.18.1` 实测）：
   - `grep -n 'Without .cwd' <IC>/README.md` → `387`（`send` 段在 `grep -n 'to. plus .cwd. requires' <IC>/README.md` → `418`）
   - `grep -n 'sends to ambiguous names fail' <IC>/README.md` → `643`
   - `grep -n 'PI_INTERCOM_SCOPE_ID' <IC>/README.md` → `490`（池命令 `grep -n 'intercom-pool <name>' <IC>/README.md` → `492`）
   - `grep -n 'byName.length > 1' <IC>/index.ts` → `1657` · `grep -n 'byNamePrefix = ' <IC>/index.ts` → `1690`
   - 会话现状 = `intercom list`

## 二、范围（5 处改动位置）

行号为现文件实测值；取数命令：`grep -n '<锚文本>' <文件>`。

1. `.agents/skills/pm-operations.md` §一「投递寻址」新增一条（`grep -n '投递寻址'`）：`to` = 会话 id（8 位）
   或 `to`+`cwd`，禁裸名跨仓；**派单与终态回执同规**；并写明「同名是机制使然，不是异常」。
2. `.agents/checklists/comm-templates.md`：派发模板首行 `to=` 改形（`grep -n 'to=<会话 id'`）；模板下加一条
   「`to=` 只写形态不写裸名」；`done(lite)` / `done(full)` 两档回执各加 `to=` 字段 + 一条形态注
   （**只改字段形态，规则不复写**，指针回 pm-operations §一）。
3. `.agents/skills/pm-routing.md` §一：加一条同句 + 指针（防双源）。
4. `.agents/checklists/pm.md` §「派单纪律核对」：加第 5 条可勾选项「投递寻址是 id 不是裸名」。
5. 本报告（单源；站点清单即本节，不另开页）。

**未改**：`.agents/prompts/**`（角色卡）· `nao-fleet.sh` · `bin/` · `pi-intercom` 源码。

## 三、AC5 调研：有没有「同名不同仓拒绝投递」的能力？

结论：**没有自动按仓拒投**。逐项核实（`pi-intercom@0.18.1`）：

- **歧义拒投**只对「同名多命中」生效（`README.md:643` / `index.ts:1657`）——本次事故只有 1 个 `pm`，**不触发**。
- **`cwd` 是目录护栏**（`README.md:387/418`）：`to`+`cwd` 要求目标在该目录 ⇒ 可**人工**用它兜住跨仓，
  但**不给 `cwd` 时不参与解析**（`to` alone = global）。
- **邮箱重连按「名 + 目录」匹配**（`README.md:643`）：那是**离线邮件恢复**的归属判据，
  **不影响在线解析**，不能当防护。
- **`PI_INTERCOM_SCOPE_ID` / `/intercom-pool <name>` 是真实存在的路由域**（`README.md:490`；
  `broker/broker.ts:185` `sameScope` · `broker/broker.ts:1428` `findSessions` 按 scope 过滤）：
  不同 scope **互相看不见**、裸名解析不到 ⇒ 事实上「跨仓同名拒投」。
  **但**：① 值是**人工命名**的池名，**不从 `cwd`/仓库推导**；② opt-in，fleet 当前**未注入**该变量
  （改 `nao-fleet.sh` 属他批范围）⇒ 本批**不启用**，只登记。

**登记（未解决 · 靠协议规避）**：上游建议 = 增加「同名但不同 `cwd` 时默认拒绝（或需显式 `allowCrossCwd`）」，
或提供 `scope` 从 `cwd` 自动派生的模式。本批**不**写成「已修」——`fail loud` 这一层由协议（用 id）承担。

## 四、判据形态决策：选 (b) 人工可判 —— 机械不可判，反例已构造

**机械不可判的理由（不是省事，是假绿来源）**：路由事实在**工具调用参数**里（`intercom({ to: ... })`），
不在任何仓库文本、也不在消息正文里。而 `to=` 字段是**正文里的自述**，两者可分离：

- **反例 A（假绿）**：正文写 `to=01a20244`（8 位，通过 `^to=[0-9a-f]{8}` 断言），实际调用
  `intercom({ to: "pm", message: ... })` ⇒ 断言全绿，**照样误投**。
- **反例 B（假红）**：调用 `intercom({ to: "01a20244" })` 完全正确，但正文没写 `to=`（回执用的 `reply`
  根本无 `to` 参数）⇒ 机械断言必红，正确行为被判不合格。
- 另有形态分叉：`send` / `ask` 有 `to`，`reply` / `handover` 形态不同；且**读取工具调用参数需会话
  JSONL**（机器本地、路径不属仓库契约），`check` 是**零网络 / 仓库内**闸门，装不进去。

**人工判据（可执行、低成本）**：收到派单/回执时按两问核 ——
① 正文 `to=` 是 8 位 id 或「名称 + cwd」？（裸名 ⇒ 打回）
② **正文 `to=` 是否等于「我自己」**？（我是 `pm(T555)`=`01a20244`，正文写 `01a207c7` ⇒ 立即反弹，不代转）
第②问是本次事故的最短拦截路径：**收件人天生知道自己是谁**，误投在收件侧零成本可发现。

（`check` 里能做的只有「模板/文档是否写了规则」这种存在性断言 —— 那是文档完整性，**不是**投递合规判据，
本批不做，以免制造「有断言 = 有防护」的错觉。）

## 五、计数变化自报

| 载体 | 改前 | 改后 | 取数命令 |
| :--- | ---: | ---: | :--- |
| `checklists/pm.md` §硬性红线 | 34 | **34（不变）** | `awk '/^## 硬性红线/{f=1;next}/^## 交付检查清单/{f=0}f&&/^- \[ \]/{n++}END{print n}'` |
| `checklists/pm.md` §交付检查清单 | 44 | **44（不变）** | 同上，区间换 `^## 交付检查清单` → `^## 派单纪律核对` |
| `checklists/pm.md` §派单纪律核对 | 4 | **5（+1）** | 区间 `^## 派单纪律核对` → `^## \`fix\` 通道核对` |

因 34 / 44 两处**未变**，`.agents/prompts/product-manager.md` 卡尾「完整红线（34 项）/ 交付检查清单（44 项）」
引用仍准确 ⇒ **无需改卡、无 bump、无广播**（该类目表头本身不声明条数）。

## 六、边界与未做

- 不改 `pi-intercom` 源码、不给上游提 PR；不改 v0.27.0 命名契约（`<role>@<repo>` 属破坏性提案，仅登记）。
- 不动 `nao-fleet.sh` / `bin/` / 角色卡；不新增正文文件（本报告 = 唯一新文件）。
- 未启用 `scope/pool`（需 fleet 注入环境变量，属他批）。
- 已知边界：本硬化是**协议层**约束，无法阻止「有 id 却写错 id」——那属人为错误，靠收件侧第②问拦截。
