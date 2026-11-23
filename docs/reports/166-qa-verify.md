# #166 QA 复核（v1 命名口径清理 · 只读验证）

- 状态：已复核 · 更新：2026-11-23 · Owner：qa · 复核对象 HEAD：`ff4a846`（分支 `fix/166-naming-v1-cleanup`，基线 `ccaf373` / `607aa6e`）
- 指针：Issue [#166](https://github.com/Nathan3303/nao-skills/issues/166) · 任务 T561 · 上游 ADR `2026-11-20-workspace-as-binding-unit`
- 范围：文档↔实现一致性、golden 变更归因、断言/冻结快照零降、判据自证、全量门禁。**未改任何功能文件**；本文件为唯一新增。

## TL;DR

**0 P1 / 0 P2 / 3 P3**。三条核心结论均独立复现：golden 位移**精确**归因到那 2 行分节标题（无稀释）；断言数与冻结快照**零变化**；弃用四项**实测**只 warn 不生效、放置键仍为仓基键。建议合并。

## 一、golden 位移：两树对照（最关键项）

方法：`git worktree add /tmp/qa561-old ccaf373`；在该旧树跑 `tests/t4/run.sh --case 28`；再把**仅那 2 行** `echo "== 任务派生会话…"` 从新树逐字打回旧树，重跑。

- 旧树干净（`123bf85b…` 记录值）：`RESULT: PASS`，日志出现 `123bf85ba92783fb4210b19126849c42` 两条（记录值 + 断言文本）· 380 条 `[PASS]`（`/tmp/qa561-old-case28.log`）。
- 旧树 + 仅 2 行标题：`RESULT: FAIL` · **379 PASS / 1 FAIL**，唯一条：

  ```
  [FAIL] P2① herdr golden == 记录的 golden（herdr 渲染零漂移；123bf85ba92783fb4210b19126849c42）
         （期望=123bf85ba92783fb4210b19126849c42 实际=8b50475296f4bd5880fe37b9f454f73a）
  ```

  ⇒ 新增记录值 `8b504752…` **完全**由这 2 行标题产生，其余断言零变化（`/tmp/qa561-old-patched-case28.log`）。**不判 P1**。
- 反向确认：`ff4a846` 全量里 case 28 `PASS`（`/tmp/qa-t561-test.log:2807`）。

## 二、断言数与冻结快照（零降断言）

- `grep -cE '^[[:space:]]*t4_(assert|ok|bad)' tests/t4/cases/28-naming-contract.sh` ⇒ **340**；`git diff ccaf373..ff4a846 -- tests/t4/cases/28-naming-contract.sh | grep -cE '^[-+][[:space:]]*t4_(assert|ok|bad)'` ⇒ **0**（断言行零增删，只改 golden 常量 + 注释）。
- `git diff --stat ccaf373..ff4a846 -- tests/t4/fixtures/` ⇒ **空**（`nao-fleet-baseline-*.sh` 冻结快照零改动）。

## 三、弃用表四行：实测（自建临时仓 + 隔离 herdr session `qa561-dep`，非生产 session）

夹具：`/tmp/qa561ws`（git init、`.agents/` 全量拷贝）、`.agents/fleet-scope` 写 `legacy-slug`。

- **`.agents/fleet-scope`**：`ensure qa` ⇒ stderr **恰 1 行** `[fleet] 弃用：.agents/fleet-scope 本版忽略…放置键恒为仓基键`；`herdr workspace list` ⇒ `label = "qa561ws"`（=仓基键，**不是** `legacy-slug`）。
- **`--fleet <slug>`**：`ensure --fleet legacy-slug qa` ⇒ **恰 1 行** warn；workspace label 仍 `qa561ws`。
- **`--scope <slug>`**：同上恰 1 行 warn（实现同一单源 `_fleet_deprecated_warn`，`:2011`）。
- **`fleet.yaml` 的 `slug:`**：写 `slug: legacy` + 空 `repos:` ⇒ 恰 1 行 `…slug 字段本版忽略…`，不 fail（随后按未知角色退出）。
- **空值守卫**：`ensure --fleet "" qa` / `ensure --scope "" qa` ⇒ `--fleet 需要值（给参但空 ⇒ 拒绝）` rc=1（与文档「给参但空 ⇒ 用法错」一致）。
- `status` 对 `.agents/fleet-scope` **不**打印 warn（`:2865` 只在 `check` 给信息行、不计 rc）；文档「读到时只 warn」指的是 ensure 路径 —— 语义无碍，但「status 也 warn」的读者预期不成立（见 P3-3）。

## 四、文档↔实现逐条（对照实现，不采信 RD 报告）

- **名字契约**：`fleet_core_build`（`:2069`）= `role + num + (task)`，`num` 空 = 槽位 1、仅 `^[2-9]$`，task `^[A-Za-z0-9_-]+$` ⇒ 与 README:83 / INSTALL:118-121 / 用法头 `:41` 一致；`>9` 由解析/构造 fail loud。
- **「@<段>」四步解析**：`fleet_repo_resolve`（`:2365`）实测 = ① `code` 精确命中 ⇒ linked；② `@main` ⇒ manifest 根；③ 同时命中且 `_fleet_phys` 不同 ⇒ fail loud（**不猜**）；④ 都未命中 ⇒ fail loud + 列可用 code。**无前缀猜测**；与 INSTALL:125 逐字相符。
- **放置键**：`place_key_label`（`:2040`）= git-common-dir 的目录名 → 小写、非 `[a-z0-9]`→`-`、折叠、截 16；`_ensure_place_label`（`:4091`）同基名让号 `${base:0:15}$n`（n=2..9），段满 fail loud。与用法头 `:13-16` 一致。
- **`send`/`handover` 遇 `@` 走跨机、`ask` 不走**：`deliverMessage` 开头 `crossMachineTarget = Boolean(to?.includes("@"))`（pi-intercom `index.ts:1827`，send/handover 共用）；`ask` 分支走 `resolveSessionTarget`（`:2860`）**不查跨机**。INSTALL:135 该行**仍准确**。
- **旧形只读**：`ensure` 不生成旧形（构造点唯一 `fleet_core_build`）；`status`/`close` 接受（`usage` `:44` 明示）—— 与实现一致。
- **`pm-operations:28`**：`ensure --task <编号> <角色>[@<仓>]` → `<角色>(<编号>)`、同 ws 该角色已在 ⇒ `<角色><N>(<编号>)`；对 `_ensure_task_name_in_ws` + `_ensure_pick_num` 实测一致。

## 五、判据：机械部分 + 变体注入（自造违规，在 `/tmp` 副本内做，不碰仓库）

§四 机械判据复算（`ff4a846` 真件）：用法头 1-60 行 `@<fleet>`=0 · `恒带`=0 · `<-task>@`=0 · `label=fleet`=0 · 等价 `--fleet`=0；`2026-11-17-fleet-identity-source` 在 `.agents/scripts/*.sh`=0、`.agents/`（非 adr/checklists）=0（仅 `docs/adr/README.md` 历史行与 ADR 正文保留）；`--help` rc=0。

变体注入结果（两违规）：
- 用法头塞 `名字带 @<fleet>（恒带）` ⇒ 五条判据命中 **1**（会红）✓。
- README 塞 `会话名带 @<fleet>` ⇒ **不在任何判据作用域**（§四 只写「用法头 1-60」+ `.agents/**`）；只有把 grep 扩到仓库根才命中。`check` 对该 README 违规仍 `rc=0`（无命名 lint）。
- 用法头塞 `--fleet 决定放置键` ⇒ 五条 pattern **均不命中**（该类「语义违规」无机械判据，只能人工`--help` 逐行扫）。

**裁定**：#166 的 AC 只要求「判据 = grep 0 命中」，**未要求进 `check`**；本批**未新增**机械闸。缺口可接受（本批为一次性清理，五条 pattern 覆盖了实际出现过的四种字面形态），但 README（npm 首页）无任何机械保护 ⇒ 见 P3-1。

## 六、门禁（HEAD `ff4a846`，日志落盘未过滤）

- `bash .agents/scripts/nao-fleet.sh check` ⇒ **rc=0** · `check: OK · roles=7 · files=53`（`/tmp/qa-t561-check.log`）。
- `npm test` ⇒ **rc=0** · **40 例 · 2513 PASS / 0 FAIL** · SKIP=0 · DEGRADE=0 · NOTE=17（全白名单）（`/tmp/qa-t561-test.log`）。本轮 0 FAIL，未命中 RD 报的偶发 FAIL。

## 七、P3（不阻塞合并）

1. **机械判据的作用域缺口**：README / INSTALL 不在任何判据作用域，`--fleet 决定放置键` 这类语义违规也无 pattern；`check` 不含命名 lint。建议后续在 `check` 加一条「README 命名契约」lint（README 是 npm 首页，#161 已证明文档漂移会复发）。本批**接受**不改。
2. **归一化/让号细节未写**：`place_key_label` 实际做「小写 + 非 `[a-z0-9]`→`-` + 截 16」，让号按 `base` 前 15 字符 + N。文档只写「仓基键 / 同机同基名让号」⇒ 两个不同长名前 15 字符相同时也会让号，读者无从预期。建议 INSTALL「会话命名与多仓」补一句。
3. **README 安装示例仍 pin `0.28.0`**（`README.md:59/63`），而当前 `package.json` 已是 `0.29.0`、本批将发 v0.29.1 ⇒ 发版时一并更新示例 pin（否则首页示例落后两个版本）。

## 八、方法与收尾

- 隔离 herdr session `qa561-dep`（`session-start` 起、`cleanup` 拆；`effect=已消失`，无残留 server）；临时仓 `/tmp/qa561ws`、`/tmp/qa561-dep.*`、`/tmp/qa561-viol` 已删；`git worktree` 临时树已 remove（保留 PM 的 `/tmp/wt-t561` 未动）。
- 未向任何会话发消息、未触碰生产 `nao-skills` session；仓库内仅新增本报告。
