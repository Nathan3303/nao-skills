# ADR：舰队绑死「tmux 内 + pi ≥1.4.0」，删净宿主阶梯

- 状态：已接受（待落地）
- 更新：2026-10-27
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-10-27-strict-tmux-pi.md` · 评审报告 `docs/reports/48-arch-review.md` · 被取代 `docs/adr/2026-10-12-non-tmux-host-spawn.md`

## 背景

- 舰队脚本 1947 行中约 215 行只服务「宿主选择」：5 档阶梯 + `NAO_TERMINAL` 五值白名单 + `xdg-terminal-exec` 启动器 + 四种窗口 class 探针 + screen 分支。
- 代价已显形：T523/T524/T525 三批都在同一缝上打补丁——`close` 的「无法确认在线状态」护栏本质是「宿主句柄可能查不到」的副产物。
- 真实使用面：本机与下游三仓的实际运行方式均为「tmux 内常驻 + 派生 pane/window」；阶梯 ③/④ 从未作为常态路径使用。
- 约束：只删「为宿主选择而存在」的代码；`spawn_tmux` 与 pane/window 显式目标寻址（T517）是唯一路径，必须保留。

## 决策

舰队唯一运行前提 = **tmux 会话内**（`$TMUX` 非空且 `tmux` 命令可用）**+ `pi` ≥ 1.4.0**。不满足时 `ensure`/`status`/`close` 以 **rc=3**（前提不满足 ⇒ 命令未执行）单行提示失败且零副作用，`cleanup` 豁免（非 tmux 是其正常场景，保持 rc=2 用法守卫 + 幂等 0）。宿主阶梯及其配套件（screen / `--background` / app-id 句柄 / 四种 class 探针）整组删除，`check` 新增 pi 版本断言（失败 rc=1 聚合并跑完全部体检）。

## 理由

1. 业务匹配：常态路径只有一条（tmux 内派生窗口）；兼容层为「可能有人不用 tmux」付了常态成本，而该可能性无真实用户验证。
2. 成熟度：tmux `split-window` + 显式 `-t` 目标与 pi-intercom 名册契约已在 T517/T525 验证完整，单宿主无未知边界。
3. 团队能力：删净后「怎么起 / 怎么收」只有一种答案，新维护者读本 ADR 即知，无需维护兼容矩阵与降级矩阵。
4. 成本：净减约 356 行、删除 21 个只为宿主选择而存在的函数；一次性破坏换后续批次不再出现「无法确认」类补丁。

## 对照过的备选模式

1. **维持现状（保留 5 档阶梯 + screen/background/xdg）** —— 适用：真实存在多宿主用户；代价：约 215 行兼容面 + 每批都要给「句柄查不到」打补丁；不采纳：无任一真实用户走 ③/④，成本换不到收益。
2. **只删 screen，保留 xdg 直开窗** —— 适用：想让非 tmux 用户仍「看得见」；代价：仍需 app-id/class 四种探针 + `status` 降级语义；不采纳：留下的是最不可移植的一段（合成器相关），且与 `close` 收窄目标相反。
3. **保留 `NAO_TERMINAL` 但只留 `tmux` 一个值** —— 适用：想保留「显式声明宿主」的自证能力；代价：单一宿主下该变量无自由度，反而诱发「以为还能切」的误用；不采纳：单一事实由 `$TMUX` 判定承担。
4. **绑死 tmux + pi ≥1.4.0（采纳）** —— 适用：本机与下游三仓的既有运行方式；代价：一次性破坏（非 tmux 环境直接不可用）；采纳：出口是「装 tmux / 起会话」，发布说明一句可交代。

## 后果与风险

- 正面：运行前提单点可判（`$TMUX` + `tmux` + pi 版本）；`close` 不再有「不可判定」分支；脚本净减约 356 行。
- 负面（有意破坏性）：非 tmux 环境 `ensure`/`status`/`close` 一律 rc=3；旧版用 `--background` / screen 拉起的会话本版不可见、不可回收（发布说明交代 `screen -ls` 手工清理）。
- rc 语义边界：**3 = 前提不满足且命令未执行**（仅 `ensure`/`status`/`close`）；rc=2 仅剩 `cleanup` 用法守卫；历史 `resolve_action` 的 **11/12 只是内部 return 码**，随其退役，**无任何已发布的外部可见退出码消失**。

## 限制与已知边界

- 不追溯改写历史 ADR 正文：`2026-10-12-non-tmux-host-spawn.md` 只改状态（已废弃），`2026-10-13-derived-pane-window-addressing.md` **零 diff** —— 其寻址不变量在新架构下是唯一路径；本文只取代其决策 5 中「非 tmux 阶梯 ③④⑤」一句。
- 下游三仓不改：按下一次 pin 升级自然生效；旧 pin 行为照旧（接受至 v0.19.0 发布 +30 天）。
- 逐函数删除表、`check` 判定式、用例断言差额不进本文（留评审报告与 QA 报告）。

## 相关指针

- 被取代：`docs/adr/2026-10-12-non-tmux-host-spawn.md`（状态已改「已废弃（被 2026-10-27-strict-tmux-pi 取代）」）
- 仍然有效：`docs/adr/2026-10-13-derived-pane-window-addressing.md`（决策 1–4 与本文并存）
- 发布说明：`docs/releases/v0.19.0.md`

## 参考来源

- [tmux(1) — split-window / list-panes / display-message](https://man.openbsd.org/tmux.1) · 访问 2026-10-27 · 显式 `-t` 目标寻址与 pane 句柄语义。
- [pi（coding agent）— `--name` / `--append-system-prompt`](https://github.com/badlogic/pi) · 访问 2026-10-27 · 角色卡常驻注入方式；本机 `pi --version` = `1.4.0`（版本基线来源）。
