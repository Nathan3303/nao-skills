# T554 · QA 一轮复核（舰队模型 v2 · 加速档）

- 分支 `feat/554-fleet-model-v2` · HEAD `e7e80aa` · 复核日 2026-11-22 · 角色 QA
- 判据单源：PRD `2026-11-20-fleet-model-v2` · ADR `2026-11-20-workspace-as-binding-unit` · `554-lite-spec` v2
- 范围：PM 圈定 6 点。全量门禁未重跑（PM 已跑 `test:t4:full:dual` 两组 rc=0）；本轮对 17 例逐一 `--case` 单跑 HEAD，17/17 rc=0。
- 断言对比法：`git worktree` 出 `b0982c8` 基线与 HEAD 各跑一遍，计 `[PASS]`（case 12 自用 `PASS` 格式，单独计数）。
- **结论：CONDITIONAL**（1 个阻塞 P1；其余 5 点通过，P3 见末）。

## 六点判定

1. **迁移未「删断言换绿灯」**：下降的 4 例逐条可归因到 D7 行为反转/旧语义退休，无一条是为变绿而删。
   上升：06 327→329 · 22 61→62 · 30 19→21 · 31 16→18。
   持平：09 35 · 12 36 · 15 41 · 19 60 · 20 109 · 23 107 · 24 78 · 32 79 · 38 27。
   下降：28 435→431 · 33 83→67 · 37 33→32 · 39 91→78（总 1637→1610，−27）。
   - 28 −4：J2② 10→7（旧布局迁移断言改 v2 tab 结构，见 P3-2）· P3-b −1（fleet 段退场，卡 role+task 预算保留）· P2-1 −1 / P2-1② +1（close 文案随槽位名）· B3⑧ +1。另 C1 子测 108→86（表 15→11 行、⑤ fleet 三档 20+ 条退役、补 4 条 legacy 只读与 9 条新形反例）——不进顶层计数。
   - 33 −16：AC11 −4（legacy 裸名≡`pm@slug` 单例语义退役）· AC12 −5（名字不再含 scope，旧 48/16 截短态退役）· AC13 −6（路径归一负控整块退役 + 「已在运行」改槽位递增）· AC6 −3（legacy 回收移交 37/40 S11）· 前提/AC9/D4/U5/N2 各 −1；U1/U2/U4a/U4b/AC3 共 +6。
   - 37 −1：c2 的「已回收」单独断言折入 `v_other_repo`（D4 由回收改为不回收+指路）。39 −13：C −1/E −1/G −1/H −2/M5 −1（四来源弃用反转）· F 33→26（11 条非法字段中 3 条 slug 语义退役，其余 8 条保留）。
   - 证据：`/tmp/qa554/{base,head}-<N>.log`（本轮已随临时目录清理）。
2. **v2 名字面通过**：`ensure pm`→pm、二次→pm2、派生 `qa(T554)`、冲突 `qa2(T554)`、`N>9` 结构不可解析（`pm10` ERR）且 ensure 耗尽 `die`（:5215「先 close」）。单测实测：`parse(pm2)=OK resident,pm,,2` · `parse(rd-be2(T553))=OK derived,rd-be,T553,2` · `parse(rd-be(T553)2)=ERR`。
   字符集四处齐：标题 sed `[A-Za-z0-9_@()-]`(:3058) · pane cwd awk 同集(:3918) · parse 吃 `(...)`(:2116) · `--as` 拒 `(`/`@`(:3991)。实跑带括号标题 `π - arch-designer(T554) - repo` ⇒ status 两处均可见（他仓节 + 派生节），未整条消失。
3. **放置键 = 仓通过**：`place_key_label`(:2054) 单源；case/40 S1/S2/S5 绿（ws label=fx40-api、二次角色同 ws、同名两仓 fx40-dup/fx40-dup2 各落自己 ws）；case/33 U1–U3/U5 绿。复用判据 = 目标 label 且 pane cwd ⊆ 仓（空 ws 关旧建新）；不按角色/fleet 开 ws。
4. **default 放行基本通过，但 `--force` 为死路（P1）**：`_term_herdr_require` 已放行 default(:472)；case/40 S8 ensure/status rc=0、S9 无 `--force` 打印影响面+rc=2+零动作。三护栏未旁路：09 AC3h③（自面板）· 38 b3（忙闲）· 38 g2/37（归属不可判定不猜）均绿。**缺陷**：`cleanup --session default --force` 在打印影响面后仍命中 `case ""|"default") return 2`(:915-917)，实测 rc=2、零动作（探针 `[FAIL] S9b default --force rc≠2`）。
5. **弃用面通过**：`--fleet`/`--scope` 各恰一行 warn 后忽略且不校验（`_fleet_deprecated_warn` :2025；33 AC5 双 warn、`--fleet BAD` rc=0）；`fleet.yaml` 的 `slug:` 恰一行 warn 后忽略（:2273；39 F 绿）；`fleet-scope` 文件恰一行（33 U4b、39 G）。legacy `@` 名仍可回收（40 S11 `已回收 pm@todo`；37 c/c2/d3、39 J 绿）。
6. **禁改区 + 卫生通过**：`tests/t4/lib-backend.sh`、`docs/tasks-state.md` 均未在 diff 内；改动的禁区函数仅 `_term_herdr_busy` 一行（加 `$repo`，见记录）；`self_refuse`/`pane_cwd_snapshot`/`repo_contains_path` 逐字未动；敏感值扫描（家目录/token/私钥）0 命中。我的探针缓存已清；仓外另有 92 个早于本轮、非本轮产出的 `/tmp/nao-t4.*` 未动（按规则不删他人）。

## 缺陷与遗留（非阻塞均给修法）

- **P1（阻塞）** `cleanup --session default --force` 不执行：修法 = default+force 时跳过 `""|"default"` 守卫（或 case 只留 `""`），补 case/40 S9b（有 `--force` ⇒ 执行 + 「将被终止」）。
- **P3-2** 布局迁移覆盖缩水：28 J2② 的「共享 tab → `pane move --new-tab` / pane_id 不变」fixture 被替换，`_term_herdr_layout_converge` 迁移分支（复用路径仍调用 :1422）现无断言；修法 = 用新名恢复一例共享 tab ghost 复用。
- **P3-3** check 文案过期：:3805「HERDR_SESSION 空/default ⇒ status 将 exit 3」与 AC5 冲突；修法 = 空→exit 3、default→可用 两行分开。
- **P3-4** S4 槽位耗尽未测：40 S4 只测非法字面量；补「2..9 全占 ⇒ rc≠0 + 先 close + 零 pane」（实现已 fail loud）。
- **P3-5** manifest `slug:` 的 warn 在 status/close 被 `2>/dev/null` 吞（:4240/:4789），与 D7「恰一行」字面有差；修法 = 写明「仅 ensure 写路径 warn」或改为不吞。
- **记录（非缺陷）** `_term_herdr_busy` 落在判据 §五「禁改区」，但改动仅为按仓收窄且闸门未被旁路；建议 ADR 补一句，免下轮误判。

## 下一批（纯 herdr 化）工作量线索（未动）

- 7 个 `term-impl-tmux` 区间共 **615 行**（:2594–3922 内）+ 门面 `term_*` 的 tmux 分支（`_term_tmux_*` / `spawn_tmux` / `prod_sock_candidates` 等引用 33 处）⇒ 约 **700 行量级**可随 tmux 后端一并移除。
