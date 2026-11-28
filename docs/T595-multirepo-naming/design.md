# T595 设计定稿 · 多仓同名角色（方案 F：名字唯一 + label 承载归属 + 显示层分离）

- 状态：已定稿 · 更新：2026-11-28 · Owner：arch-designer
- 指针：Issue nao-fleet#273（用户 2026-11-27 拍板方案 F）· 派单 T595 · 代码基线 `8b1afe1`

## TL;DR

- **名字** = `<role>[<slot>]`，slot 取自**仓的放置槽位**（盘上已存在的分配），不是「谁先起」。
- **归属** = label `nao.repo`（机读）→ pane cwd（回退）→ 冲突即 `unknown`（fail-closed）。
- **显示** = `tab.rename` 是**唯一**能改 app tab 条文字的手段（实测：hc name / OSC title / 自定义 label 全都不渲染）。
- 身份稳定性：同一仓第二次启动**必同名**（分配持久）；归属不依赖名字 ⇒ 两仓会话各自可复现。

## 九项骨架（不适用项给理由）

- **流程**：适用 —— 见末节实现顺序。**状态**：适用 —— tab 条三态（无名 / 角色名·space / 已 rename）。
- **降级产物**：适用 —— 无 app（TUI）走 herdr `tab create --label`，显示串同源。
- 信息架构 / 视觉规范 / token / 断点 / 无障碍 / 可用性：不适用：只复用 app 既有 chrome，不新增颜色、尺寸、键位与交互元素。

## 1 命名形态：`<role>[<slot>]`，slot = 仓的放置槽位（裁：数字让号）

- **判据**：`_ensure_place_label()`（`ensure.sh:143`）已把「仓 → workspace label」持久化（首仓 = 基键，后续 `base:0:15<N>` 让号），且解释权在盘上（workspace label），**不是启动顺序** ⇒ 复用它当名字槽位，则「仓 ↔ 槽位」是可复现事实。
- **反例 1（为什么不用 `<仓基键>-<角色>`）**：`place_key_label` 归一后**截 16 字符**（`nao-omarchy-plugins` → `nao-omarchy-plug`）；拼 `arch-designer` = 30 未超 32，但**基键已不可读且会撞**（两个 `nao-omarchy-plug*` 仓同名）⇒ 名字成为不可判来源，且仓改名即全舰队改名。
- **反例 2（为什么不保留现状「本 workspace 计数」）**：`_ensure_pick_num` 的 `[[ "$_sr" == "$wsid" ]] || continue`（`ensure.sh:221`）只看本 space ⇒ **跨 Space 必撞 `name_taken`**，这就是今天的 bug。
- **诚实的边界**：首仓拿 1 / 次仓拿 2 仍取决于「谁先建 workspace」，但落盘后固定；要让新克隆仓也拿固定号，需把分配写进 `.agents/fleet.yaml`（本仓当前**无**该文件）—— 留 B 批，不在本设计假装已闭环。

## 2 label schema

- 新增 **`nao.repo`** = `place_key_label` 值（仓基键，≤16，**不含路径**）。理由：与放置键同源、离线可读、仓搬家不失效；**禁写绝对路径**（家目录泄漏 + 移动即失效）。
- 新增 **`nao.role`** + **`nao.slot`**：名字一旦出现 `--as` 后缀形或 `-<hash4>` 合法化（`term-app.sh:662`，撞名时 backend 名 ≠ nao 名），名字就解析不出角色/槽位 ⇒ status 必须有结构化事实，不能靠名字文法。
- 保留 `nao.name` / `nao.task`。**`where` 禁入解析**：它是 app 回写的派生字段（实测随 tab 改名而变）。
- 写入时机：`ensure` spawn 时一次写全（`hc run --label`）；迁移不回填（见 §5）。

## 3 解析顺序与 fail-closed

判定「终端属于哪个仓」：① `nao.repo` → ② pane cwd（`repo_contains_path`，现状）→ ③ 名字（仅 legacy 形）。

- **一致 ⇒ 采信；冲突 ⇒ `unknown`**（保持 T551/T552「不猜、不误杀」）。理由：label 可陈旧/手改，cwd 可不可读，任一方都无资格单向覆盖。
- **唯一例外**：label 在、cwd **不可读**（pane 死 / 权限）⇒ 采信 label —— 这是 label 相对 cwd 的唯一增益，也是加它的理由。
- cwd 判 `other` 而 label 指本仓（真实场景：终端 cd 到别的仓）⇒ `unknown` + 两侧证据入提示行，**不给回收命令**（与现状一致）。

## 4 显示映射（**实测**，非推断）

命令与产物（截图含用户会话内容，**不入库**，路径为现场证据）：

1. `hc run --bg --no-parent --keep --name pm2 --label nao.repo=demo-repo --label herdr.space=<sp> -- bash -c 'printf "\033]0;DEMO-TITLE-pm2\007"; sleep 600'`
   ⇒ `hc get pm2`：`name=pm2`、`title=DEMO-TITLE-pm2`、`labels.where="nao-skills / 2"`。
2. `herdr-app shot /tmp/t595-app.png` ⇒ tab 条显示 **`sleep`**（foreground 程序名）：**hc name 与 OSC title 都不参与渲染**。
3. `herdr-app do tab.rename --id <tab> --name "pm2 · demo-repo"` → `herdr-app shot /tmp/t595-app2.png`
   ⇒ tab 条**逐字** `pm2 · demo-repo`；同终端 `labels.where` 随之变为 `nao-skills / pm2 · demo-repo`。
4. 无名 tab 的默认串 = `<agent 名> · <space 名>`（`π · pm · nao-skills`）；space 名取该 space **首个终端的仓基键**（fallback folder，`herdr-app` 的 `Space.name` 契约）。

结论：**显示层唯一杠杆 = `tab.rename`**；`nao.repo` label 不会被渲染，因此「`pm · xxx`」必须由 rename 实现，不能指望 label。
实现：`ensure` 成功后 `herdr-app do tab.rename --name "<nao 名> · <仓基键>"`（本仓也写，避免「看位置才知道哪个仓」）；命名失败只 warn（不影响 spawn 成败）。

## 5 兼容与迁移

- 现有会话无 `nao.repo` ⇒ 走 ②（cwd），行为与今天一致；**不回填 label**（写别人终端属越权，且 cwd 已可判）。
- `logs <role>` 的仓过滤已走 cwd → `place_key_label`（`sessions.sh:117`），**不依赖名字** ⇒ 无需改；`.retention.log` 与 `fleet_sessions_note_spawn` 按**nao 名**记录，因不改名策略而无需改。
- **不做「版本别名期」**：同 role 两名会同时命中前缀匹配，歧义成本 > 迁移收益；改名唯一路径 = 用户显式 `ensure --force`。

## 6 与 TUI 的一致性

- 一套解析（§3）、两套显示 API（app `tab.rename` / herdr `tab create --label`）、同一个显示串 `<名> · <仓基键>`。
- TUI tab 标题会变长；herdr tab label 的**上限未实测** ⇒ 保守按 ≤32（与 hc name 同预算）。

## PASS / REJECT 自评

- **PASS**：六条均有判据 + 反例；§4 为实测（命令 + 截图路径）；不引入新依赖；不破坏 T551/T552 fail-closed；显示与机读彻底分离。
- **REJECT（自评未闭环）**：`fleet.yaml` 固化「仓 → 槽位」未做 ⇒ 「新克隆仓拿固定号」不成立；清理 workspace 后重建的号段复用仅在 label 既存时可保证。

## 推荐实现顺序

1. **A（解阻塞）**：`_ensure_pick_num` 去掉 `_sr == wsid` 过滤 ⇒ 槽位在 core 内全局唯一；`name_taken` 只重试一次换槽（其余错误不重试）。验收：两个 Space 各起 `pm` 不撞。
2. **B（归属）**：spawn 写 `nao.repo`/`nao.role`/`nao.slot`；status 解析加 label 层（冲突 = unknown）；先于显示落地（机读优先于人读）。
3. **F 显示部分**：`tab.rename` + TUI `--label` 同串，失败 warn。
4. **可选**：`.agents/fleet.yaml` 固化仓 → 槽位号，消除「先建者拿 1」。
