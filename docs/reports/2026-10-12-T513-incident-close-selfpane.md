# T513-S1 事故定性：`close` 自伤 —— kill 调用者自己的 tmux pane（窗口消失）

- 批次：T513（合并冻结中，等本定性）
- 提交人：rd-infra
- 日期：2026-10-12
- 复现脚本：`docs/reports/2026-10-12-T513-close-selfpane-repro.sh`（自包含，全程 `/tmp` 沙箱）
- 对照 revision：`main`(0.13.0) · `a28b11d` · `04baea2`

---

## 1. 结论（先给答案）

| 问题 | 结论 |
| :-- | :-- |
| H1 是否成立 | **成立**。`close` 经 `find_pane_for_any_repo()` 层②（名册 `tmuxPane`）命中「调用者自己的 pane」时，会 `tmux kill-pane -t <自己的 pane>` ⇒ 自杀；若该 pane 为同窗口最后一个，整个 tmux 窗口消失（`exit-empty on`）。 |
| 是否本批引入 | **否，属既有缺陷**。`find_pane_for_any_repo` / `intercom_pane_for` / `cmd_close` 的 kill-pane 主体在 `main`(0.13.0) 与 `04baea2` **逐字节相同**；同一夹具三版**均复现**。 |
| 本批的影响 | **放大触发面，非引入**。T513 新增「从 pane 内派生可见窗口」入口（④ xdg-window、`nao:foot/ghostty/ptyxis`、③ attach 窗口、⑤ background）——这些路径把调用者的 `TMUX`/`TMUX_PANE` 一并传给子进程（三版均有同类路径：main 为 ghostty/ptyxis）。 |
| PM 前提校正 | 代码**任一版本都没有 `env -u TMUX`**（全仓 grep + `git log --all -S 'env -u TMUX'` 均无；`env -u TMUX` 仅出现在测试脚本 `docs/reports/2026-10-12-T513-verify.sh` 的 `set_env`）。因此「当时只 unset TMUX、漏了 TMUX_PANE」不成立于代码事实：**TMUX/TMUX_PANE 从未被清除**。H1 的核心链路仍成立。 |
| 是否可放行 0.14.0 | **F1+F2 已折入本批并落地（见 §7）**：带上自伤不变量与句柄源头清理后可放行；不带 F1 不放行。 |

---

## 2. H1 链路（已验证）

```
[pane 内] NAO_TERMINAL=foot（或 ④ xdg-window / ghostty / ptyxis）nao-fleet ensure rd-be
   └─ 子进程继承调用者 env：TMUX=<sock>, TMUX_PANE=%99   ← 实测见 §3.B
   └─ 新 pi 启动，pi-intercom 注册时读 process.env.TMUX_PANE（不可变）
        => 名册 rd-be.tmuxPane = %99（= 调用者自己的 pane，而非新窗口的 pane）
[之后] nao-fleet close rd-be [--force]
   └─ find_pane_for_any_repo("rd-be")
        ① 标题契约：未命中
        ② intercom_pane_for：返回名册 tmuxPane = %99
           tmux_pane_live(%99) == true ⇒ 直接返回 %99        ← close 路径**无层③**
   └─ 闸门② 仅拦「在跑 turn」；名册 status=idle 时**无需 --force**即通过
   └─ tmux kill-pane -t %99   ⇒ 杀掉调用者自己的 pane
```

依据（外部）：`pi-intercom` 会话注册读取 `process.env.TMUX_PANE`，注释明言「inherited at process start and immutable」
（`~/.pi/agent/npm/node_modules/pi-intercom/index.ts:567`、`types.ts:56`）。

---

## 3. 沙箱复现（不碰真实 tmux server / 真实名册）

方法：`PATH` 前置桩 `tmux`（**只记录 argv、不执行真实 kill**；「调用者自己的 pane」= 桩自身 env 的 `TMUX_PANE`）；
BASH_ENV 注入 `kill()` 日志桩；名册用假 `tsx cli.mjs`（`tmuxPane` 取自继承的 `TMUX_PANE`）；
`kill-pane` 目标是可自证的：**桩报告的 live pane 恒等于调用者自己的 `TMUX_PANE=%99`**。

### A. `close` 自伤（同一夹具 × 三版）

| revision | 结果 | 证据（桩 tmux argv） |
| :-- | :-- | :-- |
| `main` (0.13.0) | **自伤复现** | `kill-pane -t %99`（%99 = 调用者自己的 pane） |
| `a28b11d` | **自伤复现** | `kill-pane -t %99` |
| `04baea2` | **自伤复现** | `kill-pane -t %99` |

补充：同一夹具下**去掉 `--force` 也复现**（名册 `status=idle`、pane 不 busy 时闸门②不拦）。

### B. 派生子进程继承 `TMUX_PANE`（触发面）

| revision | 宿主路径 | 子进程 env |
| :-- | :-- | :-- |
| `main` | `ghostty` | `TMUX=…` `TMUX_PANE=%99` ✓ 继承 |
| `a28b11d` | `ghostty` / `foot` | 均 ✓ 继承 |
| `04baea2` | `ghostty` / `foot` / **`xdg-window`(④)** | 均 ✓ 继承 |

⇒ main 已有 ghostty/ptyxis 入口；本批新增 foot/ghostty/ptyxis（`nao:*`）与 ④ xdg-window，触发面扩大。

### C. `kill 0` 类自伤核对（PM 第 4 项）

| 情形 | 断言 | 结果 |
| :-- | :-- | :-- |
| `kill-pane` 失败、`pi_pids_for` 返回空 | `pids` 为空时不得调用 `kill`（防无参/`kill 0`） | **PASS**：`KILL-ARGV` 计数 0（`[[ -n "$pids" ]]` 拦住） |
| `kill-pane` 失败、存在 comm=pi 子进程 | `kill` argv 为真实 pid | **PASS**：`KILL-ARGV: 1298928`（非 `0`、非空） |

静态复核：全部 `kill` 调用点均有非空前置（`nao-fleet.sh` 行 `979/982`、`1075/1076`、`1534`、`1584`）；
`kill $pids` 前的 `[[ -n "$pids" ]]` 有效阻断空值；`pi_pids_for` 只输出 tmux/pgrep 的真实 pid，产不出 `0`。
**⇒ 无 `kill 0` 自伤路径。**

---

## 4. 最小复现命令

```bash
cd /home/nathan/Projects/nao-skills
bash docs/reports/2026-10-12-T513-close-selfpane-repro.sh        # 期望 A 三版均「自伤复现 ✓」
# 夹具落在 /tmp/nao-t513-repro（可用 T513_SBX=… 覆盖）
```

单点最小链路（可只跑一版）：脚本内 `run_close` 即 `nao-fleet.sh close rd-be --force`，
env 仅需 `NAO_SKILLS=<夹具>`、`PI_CODING_AGENT_DIR=<假名册 agent>`、`TMUX=/tmp/nao-sbx-fake-sock,4242,0`、`TMUX_PANE=%99`，
其中假名册的目标会话 `tmuxPane` 即 `%99`。

---

## 5. 修复方案（**F1/F2 已落地见 §7**，F3/F4 未纳入）

### F1（必须 · 不变量）：`close` 任何路径不得回收调用者自己的 pane/窗口

- `cmd_close` 解析出 `pane` 后立刻加闸门：`pane == $TMUX_PANE` ⇒ **拒绝 + 诊断 + return 1**（不 kill-pane、不进入 `pi_pids_for` 兜底）。
- 覆盖点：① 层②名册命中；② 末尾 `pids="$(pi_pids_for …)"` 兜底（其内部 `find_pane_for` 会再次命中层②）——两处都要挡住。
- 影响面：仅当 `close` 运行于 tmux 内且目标会话错注册为当前 pane 时触发；唯一「合法」自指场景（close 自己所在会话）本就不应发生 ⇒ 无误伤。

### F2（必须 · 源头）：派生窗口/分离宿主时清 `TMUX` + `TMUX_PANE`

- 对 pi 直接落地的宿主，派生前缀 `env -u TMUX -u TMUX_PANE`：
  - `xdg-window`（④）、`nao:foot|ghostty|ptyxis`、`screen-bg`、`tmux-bg`。
  - 例：`spawn_fork_window "$name" env -u TMUX -u TMUX_PANE foot …`；
        `spawn_xdg_window "$name" "$repo" env -u TMUX -u TMUX_PANE bash -lc "$inner"`。
- **不动** `spawn_tmux_attach` 的 `tmux attach` argv（tmux 自身需要 socket 上下文）；`tmux-in`/`tmux-bg`（`new-session`/`split-window`）由 tmux server 为新 pane 注入正确 `TMUX_PANE`，天然无污染。
- 验证：以「桩窗口宿主落盘 env」断言子进程不再出现 `TMUX`/`TMUX_PANE`（复用 §3.B 夹具）。

### F3（建议 · 纵深）：名册 `tmuxPane == $TMUX_PANE` 的信任剔除

- 在 `close` 专用路径（`find_pane_for_any_repo` 层②或 `cmd_close`）对「等于本进程 pane」的名册句柄**不再采信**（视为无记录 + warn）。
- 评估：**值得做**。错注册的签名精确（继承 ⇒ 恒等于调用者 pane），误伤面极小；且能同时缓解「名册滞后/串名」类风险。
- 注意：不要下沉到 `find_pane_for`（`running`/`ensure` 判重共用）——否则会造成 ensure 误判「未运行」而拉重，属另一课题。

### F4（可选 · 可审计）：`close` 成功回执附「被回收 pane vs 调用者 pane」对照，便于事后定位同类自伤。

**放行建议**：F1 是纯防御性、低风险、小改动，建议**并入本批或紧随热修**后放行 0.14.0；F2 同批落地最佳（治本）。F3 可作同批或下一小批次。

---

## 6. 证据索引

- 复现脚本：`docs/reports/2026-10-12-T513-close-selfpane-repro.sh`
- 关键代码：`nao-fleet.sh` `find_pane_for_any_repo()`（层②无自 pane 剔除）、`cmd_close()`（kill-pane 主体三版相同）
- 三版逐字节对照：`find_pane_for_any_repo` / `intercom_pane_for` 在 `main`、`a28b11d`、`04baea2` **完全一致**
- pi-intercom 注册依据：`~/.pi/agent/npm/node_modules/pi-intercom/index.ts:567`（`currentTmuxPane()` 读 `$TMUX_PANE`）

## 7. 修复落地（T513-S2 · PM 拍板 F1+F2 折入本批）

- **F1（不变量 · 本批）**：`cmd_close` 解析出 pane 后加闸门 `pane == $TMUX_PANE` ⇒ **拒绝 + 一行诊断 + return 1**（不 kill-pane、不进入兜底）；`pi_pids_for` 内同判，覆盖末尾兜底路径。见 ADR「不变量」节。
- **F2（源头治理 · 本批）**：`TMUX_ENV_SCRUB="env -u TMUX -u TMUX_PANE"` 前缀用于 ④ `xdg-window`、`nao:foot|ghostty|ptyxis`、`screen-bg`。
- **F3/F4 未纳入**（PM 登记为后续候选；F3 与 T512-① 一并议）。

### 7.1 对 PM 指令的一处数据修正：`tmux-bg` 不适用 F2

PM 要求 `tmux-bg` 也前缀 `env -u TMUX -u TMUX_PANE`。实测（隔离 `tmux -L nao-t513sbx`，不碰真实 server）：
tmux 会为新 pane **注入并覆盖**正确句柄——外层 `TMUX_PANE=%FAKE` ⇒ pane 内实为 `%0`/`%1`。
故 `tmux-bg`/`tmux-in`/`attach` 本就无继承问题；对其前缀剥离反而会**抹掉正确 `TMUX_PANE`**
（pi 将注册 null 句柄，回退到不可靠的标题/兜底）。**∴ F2 未施加于 tmux 自身路径**，仅施加于非 tmux 窗口/screen 宿主。

### 7.2 修复后复跑（同产物：脚本默认 rev `main a28b11d 04baea2 HEAD`）

| 段 | 修复前（三版） | 修复后（HEAD） |
| :-- | :-- | :-- |
| A. close 自伤 | `kill-pane -t %99`（调用者自己的 pane） | **不再自伤**：打印拒绝诊断、无 `kill-pane` |
| B. pi 进程继承 `TMUX_PANE` | ghostty / foot / screen / xdg 均继承 | **已清除**（ghostty / foot / screen / xdg 四宿主均无 `TMUX_PANE`） |
| C. kill 兜底 | pids 空=0 次 kill；pids 非空=`kill <真实pid>` | 同（未回退） |

总判定 **PASS**（脚本 exit 0）。tmux 注入覆盖证据：`TMUX_PANE=%FAKE` ⇒ 新 pane 内 `%0`/`%1`。

### 7.3 与 QA AC12 的独立交叉验证（QA `verify.sh` 预跑，同一树）

QA 的 AC12 用独立桩重跑同一批不变量，修复前/后逐项对照（在 pristine 隔离 worktree、`--only AC12`）：

| AC12 断言 | 修复前（`04baea2`） | 修复后（F1+F2） |
| :-- | :-- | :-- |
| F1+ close 自身 pane（rc≠0 + 诊断 + 0 次 kill-pane） | 3/3 **FAIL**（实测自杀 rc=0 + `kill-pane -t %99`） | 3/3 **PASS** |
| F2 foot/ghostty/ptyxis/xdg-window 不继承 | 4/4 **FAIL** | 4/4 **PASS** |
| 合计 | PASS=6 **FAIL=10** | PASS=13 **FAIL=3** |

剩余 3 项**修复前也 FAIL**（非 F1/F2 回归，已定位）：

1. **screen-bg**：QA 的 `screen -ls` 桩**无条件回放** `nao-qa` 会话 ⇒ `running` 短路、ensure 跳过、env 文件为空（夹具 bug）。本报告 §7.2 的 B 段改用 stateful screen 桩（`-dmS` 建态后才回放 `-ls`）⇒ HEAD 的 screen-bg **已清除 `TMUX_PANE` ✓**。
2. **tmux-bg**：QA 的 `tmux new-session` 桩**未模拟 server 注入**（实机 tmux 会覆盖外层 `TMUX_PANE`，见 §7.1）⇒ 断言按「被剥离」判红。属 PM 指令与实测的偏差，待 QA 桩修正或 PM 改口径。
3. **F2 边界② rc=1（D7 · 已修）**：`apply_tmux_layout` 的 `read -r win_w win_h < <(tmux display-message …)` 在**空输出**下 `read` 返回 1，`set -e` 使 ensure 中断（修复前同现，与 F1/F2 无关；QA 桩 display-message 回空暴露之）。**T513-S3 已修**：`read … || true`，读不到窗口尺寸即跳过布局、不硬崩；QA AC13 覆盖（`--only AC13` GREEN 1/1）。
