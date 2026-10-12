# ADR：非 tmux 宿主的舰队派生（宿主阶梯 + 派生方式 + 句柄模型）

- 状态：**已接受** · 日期：2026-10-12 · 出具：arch-designer（T513-A 终签）· 落地：rd-infra
- 指针：PRD `docs/prds/2026-10-12-non-tmux-host-spawn.md`（§5/§7/§9）· Issue #26 · 分支 `feat/26-non-tmux-host-spawn`
## 背景

- `detect_host()` 枚举模拟器（ghostty|ptyxis|tmux→screen），本机 foot 0 命中 ⇒ 非 tmux 落 detached：不可见却报在线（P1/P2）；宿主缺失时 `setsid -f` 假成功（rc=0 无窗口）与 `screen` 裸 127（P3/P4）；句柄绑死 tmux（`find_pane_for*`/`pane_busy`/`offline_verifiable`）。
- 用户 D1–D5：默认可见窗口；非 tmux 句柄支持 + status 降级（D2）；tmux 内不回退（D3）；后台须显式（D4）；tmux 可用则前台可见（D5）。
## 决策

1. `detect_host()` 改**环境查询阶梯**（非枚举）：①`NAO_TERMINAL` 显式 → ②`$TMUX` 当前窗口分屏 → ③非 tmux+tmux+图形 ⇒ `new-session -d` + `xdg-terminal-exec` 开窗 attach → ④无 tmux+图形 ⇒ `xdg-terminal-exec --app-id=org.nao.<角色> --dir=<repo>` 直开 → ⑤无图形 ⇒ 仅 `--background` detached → ⑥`exit 2`。
2. **禁假成功**：任何「已拉起」前须校验宿主句柄；③取「**每角色一个 tmux 会话 + 每角色一个可见窗口 attach**」+ **默认 socket**（不加 `-L`）⇒ pane 标题契约 / `$TMUX_PANE` / `pane_busy` 完整保留、句柄零改动；④由 app-id 层兜底。
3. `offline_verifiable()` 新语义：**本批仅落地「名册可用」limb**（名册可读 ⇒ 可断言离线）；「宿主枚举器可用且枚举成功」limb **未实现，属已知边界**（函数仍保留 `$TMUX` 存在 / `NAO_TERMINAL=tmux|screen` 两条旧启发式，不构成可靠枚举）。枚举失败/歧义 ⇒ 不得断言，`close` 非 0。
## 理由（四步法）

- 业务匹配「可见 + 不骗人」，foot 默认路径覆盖本机 100%；技术成熟：`xdg-terminal-exec` 是 freedesktop Default Terminal 规范的现成实现（实测见来源）；团队/成本：③复用既有 detached 分支 + 一条 attach 命令，D2 降级面收敛到④。
## 对照过的备选模式（含不采纳理由）

| 方式 | 条件 | 代价 | 结论 |
| :-- | :-- | :-- | :-- |
| 维持现状（枚举模拟器 + detached） | — | 无穷集合、不可见、假成功 | **不采纳**（P1–P4 根因） |
| tmux 会话 + 可见窗口 attach（D5 · ③） | 有 tmux + 图形 | 每角色一窗口；attach 须校验 | **采纳**（tmux 句柄完整保留） |
| `xdg-terminal-exec`（④） | freedesktop 图形 | 依赖桌面条目；无 tmux 句柄 | **采纳**（无 tmux 主路径） |
| 合成器 launcher（hyprctl/swaymsg） | 特定合成器 | 不可移植、矩阵维护 | **仅后备**（存在性探测） |
| detached opt-in（`--background` · ⑤） | 无图形 / SSH | 不可见 | **采纳为显式开关**（非默认） |
## 阶梯失败语义

- ① 档值非法/命令缺失 ⇒ `exit 2`（不静默降级，P3/P4 回归）；② pane 创建失败 ⇒ warn + 跳过该角色、其余继续（现状）；③ `new-session` 成功但限时内 `list-clients` 无客户端 ⇒ kill-session 并降级④（守住「可见」），④ 亦失败 ⇒ `exit 1`。
- ④ 开窗后：**无 class 探针**（`hyprctl`/`swaymsg`/`xdotool`/`wmctrl` 全缺）⇒ **接受启动 + 一行 warn**「未能校验可见性」（D6：无法校验 ≠ 校验失败）；**有探针但限时未出现 class** ⇒ 尽力回收已开的 pi 进程（pidfile 记 inner pid 后 kill）+ `exit 1`，回收结果**如实报告**（未捕获 pid 时明说窗口可能仍在、需手动关闭）。
- ⑤ tmux 与 screen 皆缺失 ⇒ `exit 2`；成功建 detached 会话即视为句柄建立（`new-session` 的 rc 由 `set -e` 兜底，**无独立存活校验**）。⑥ `exit 2` + 单行诊断 + 可复制恢复命令（禁裸 127）。
## 非 tmux 句柄模型（D2 边界）

- 优先级：tmux pane（①②③ 现状不变）> app-id/class（④：`hyprctl clients -j` 按 `class=org.nao.<角色>` 取 pid，校验 pid `comm=pi`；X11 用 xdotool/wmctrl 后备）> 名册（turn 判定）。
- `status`（④ = **无 tmux pane 句柄**；含 `NAO_TERMINAL` 显式窗口宿主）：在线取名册，turn 判定仅名册 status 并输出一行「turn 判定来源 = 名册」；未知状态不阻塞 `close` 但告警（BR6）。`close`（④）：class→pid→kill 优先；名册在线却无句柄 ⇒ `exit` 非 0 + 诊断（不静默 no-op）；tasks-state 与在跑 turn 闸门不变。
## D5 的坑（已核）

- 独立 socket **不要**：现有 tmux 查询全用默认 socket，`-L` 会让 `find_pane_by_title`/`pane_busy` 失据；隐形会话：`destroy-unattached`/attach 竞态可能「会话在、窗口无」⇒ 必须限时校验 `list-clients`。
- 单窗口装 6 pane **不采纳（本批）**：布局函数基于当前窗口，跨窗口需改目标寻址，多仓/回收耦合大；每角色会话更贴合既有句柄与判重模型，三布局仍只服务②。
## 后果与风险

- 正面：非 tmux 可见、失败不骗人，③句柄零改动。风险：attach 竞态（校验+清理）· `setsid -f` 假成功面（句柄前置校验）· hyprctl 仅 Hyprland（存在性探测 + X11 后备，覆盖限制见 NFR5）· class 冲突（app-id 唯一 + `comm=pi`）· 用户 detach 后不可见（用户意图，`status` 标注 detached）。
- 边界（同源情报）：`fallback_pane_for` 层③「本仓未认领 pi pane 唯一兜底」会在新 pane 未被名册认领时误配（实测 `ensure qa rd-infra` 把新 qa pane 命中给 rd-infra ⇒ 误判已在运行而跳过）；层③要求名册 cwd 匹配 + 跨**全部角色**唯一，否则不返回。
- **D6（④ 无 class 探针）**：接受启动并打印一行 warn「未能校验可见性」；`status` 同时给降级标注。理由：「无法校验 ≠ 校验失败」——`exit 1` 会让 X11/无探针环境完全不可用；诚实性由 warn + 文档守住。`status` 降级标注条件为「④ 路径（无 tmux pane 句柄）」，非「tmux 命令缺失」（含 `NAO_TERMINAL=foot` 等显式窗口宿主）。
- **L1（`$TMUX` 已设但 tmux 命令缺失）**：**warn + 继续**按环境选择宿主，不因升级中途残留变量直接 `exit 2`；该情形不构成 tmux 句柄。
- **已知边界（本批不修）**：L2/L3/L4 以及「宿主枚举器 limb 的 `offline_verifiable()`」均接受为已知边界，仅记录。
## 实施闸门（给 RD 的判定式）

```text
NAO_TERMINAL → 校验档值 ∈ {tmux,foot,ghostty,ptyxis,screen}，命令缺失 exit 2
elif $TMUX   → split-window rc=0（失败 warn+跳过该角色）
elif tmux ∧ 图形 ∧ `xdg-terminal-exec --print-id` ok → new-session -d && 开窗 attach && 限时 list-clients 有客户端（否则 kill-session→降级④）
elif 图形 ∧ `xdg-terminal-exec --print-id` ok → 开窗 --app-id=org.nao.<角色> --dir=<repo> && 限时 class 出现（有探针未现 ⇒ 尽力回收 pi + exit 1；无探针 ⇒ 接受 + warn）
elif --background ∧ tmux → new-session -d ｜ else exit 2 + 一行诊断 + 恢复命令
```
- 门禁：`tests/t4` case 11 断言 P3=`exit 2` / P4=`rc≠0` 且 0 处「已拉起」+ AC1/AC2/AC5/AC6/AC8；文档四处同步（AC9）。
## 参考来源

- xdg-terminal-exec（freedesktop Default Terminal 规范）· https://gitlab.freedesktop.org/xdg/xdg-terminal-exec · 访问 2026-10-12
- foot 1.28.0 man page（`--app-id`/`--working-directory`）· https://codeberg.org/dnkl/foot · 访问 2026-10-12
- Hyprland `hyprctl clients -j`（`class`/`pid`/`title`）· https://wiki.hyprland.org/Configuring/Using-hyprctl/ · 访问 2026-10-12
- tmux(1)（`new-session -d`/`attach`/`list-clients`/`destroy-unattached`）· https://man.openbsd.org/tmux.1 · 访问 2026-10-12
- 本机实测 2026-10-12：`--print-cmd` = `foot --app-id=org.nao.qa --working-directory=/tmp -e …`；`~/.local/share/applications/foot.desktop` 声明 `X-TerminalArgAppId/Dir`

- 修订：2026-10-12 首版（T513-A 终签）
