# T572 验证期缺陷台账

- 日期：2026-11-26 · Owner：qa · 关联报告：`docs/reports/572-qa-verify.md`
- 状态口径：New → Open → Fixed → Verify → Closed / Reopen（**不 Verify 不关闭**）

## D1 · `cases/44` 每跑一次泄漏 2 个真 `herdr-core` 进程（收尾用了不存在的子命令）

- **状态**：New（未修）
- **严重度**：一般（P2 —— 不阻断发布，但每次跑测试都累积进程/资源）
- **发现于**：T571+T572 合并后全量验证（HEAD `a59d1c3`），`npm run test:t4:full` 收尾孤儿扫描
- **环境**：`hc 0.1.22` · `herdr 0.9.5` · `node v24.22.3` · Linux（test cache 根 `/tmp/nao-t4.*`）
- **关联用例**：`tests/t4/cases/44-app-backend.sh` ⑪「真 hc（私有 core）」段（收尾在 `:379`）

### 复现步骤

```bash
cd /home/nathan/Projects/nao-skills
ss -xlpH | grep -c 'nao-t4'                      # 基线：0
bash tests/t4/run.sh --case 44                   # RESULT: PASS（99 PASS）
ss -xlpH | grep 'nao-t4'                         # 实际：2 条 LISTEN（serve + holder）
```

最小复现（不跑用例，只跑同形命令；私有运行时根，不碰用户环境）：

```bash
RRT=/tmp/qa572/hcprobe; mkdir -p "$RRT"
env XDG_RUNTIME_DIR="$RRT" XDG_STATE_HOME="$RRT/state" HC_SESSION=qa-probe \
  hc run --bg --no-parent --keep --name probe -- sleep 30
env XDG_RUNTIME_DIR="$RRT" XDG_STATE_HOME="$RRT/state" HC_SESSION=qa-probe hc server kill
# → {"error":{"hint":"see `hc --help`","kind":"usage","message":"unrecognized subcommand 'kill'"}}  rc=2
env XDG_RUNTIME_DIR="$RRT" XDG_STATE_HOME="$RRT/state" HC_SESSION=qa-probe hc server stop
# → {"stopped":true}  rc=0
```

### 预期 vs 实际

- **预期**：用例收尾后，该私有 `XDG_RUNTIME_DIR` 下不再有 `herdr-core` 监听 socket（用例注释自述「effect 判据 = 进程/socket 消失」）。
- **实际**：每次 `--case 44` 结束后仍有 **2 个** `herdr-core` 进程（`serve` + `hold --socket …holder.*.sock`）监听在 `$T4_CACHE_DIR/apprt-real-<pid>/herdr-core/`；cache 目录被正常删除后，socket 成为「已删除目录上的监听」。

### 证据

- **2/2 复现**：`npm run test:t4:full`（rc=0）后 2 条；单跑 `--case 44`（rc=0，99 PASS）后 2 条。路径均含 `apprt-real-<pid>`，时间戳与跑次一致。
- **子命令实测**（见上最小复现）：`hc server --help` 的子命令 = `start` / `stop` / `status` / `restart`（**无 `kill`**）；`server kill` rc=2、`server stop` rc=0 且监听归 0。
- **累积量**：本次验证前，本机已累积 **93** 个监听 `/tmp/nao-t4.*` 的 `herdr-core` 进程 + **13** 个 cache 目录（最大单目录 84M），部分来自更早的被中断跑次；已全部清理（见下「已执行清理」）。
- **逃逸原因**：`:379` 的 `… || true` 把 rc=2 吞掉，且该段**没有 effect 断言**（只有 kill/rm 面板级断言），故用例仍绿。

### 影响

- 每次跑 `cases/44`（含 `npm test` / `test:t4:full`）在宿主上净增 2 个常驻进程与少量内存/句柄；反复跑或 CI 上累积会造成进程表膨胀（实测历史已到 93）。
- 不影响产品行为与用例判据；`run.sh` 起跑前的 sweep 只覆盖 herdr 实验根形态（`XDG_CONFIG_HOME`），**不覆盖** app 后端的 `XDG_RUNTIME_DIR` 根 ⇒ 不会被自动收走。

### 根因

`hc` CLI 的服务端子命令是 `server stop`，用例写成了 `server kill`（rc=2 usage 错误），又被 `|| true` 静默吞掉 ⇒ 私有 core 未被停。

### 建议修法（测试侧，1 行 + 1 条断言）

```diff
-  XDG_RUNTIME_DIR="$RRT" XDG_STATE_HOME="$RRT/state" HC_SESSION="$SESS" "$REAL_HC" server kill >/dev/null 2>&1 || true
+  XDG_RUNTIME_DIR="$RRT" XDG_STATE_HOME="$RRT/state" HC_SESSION="$SESS" "$REAL_HC" server stop >/dev/null 2>&1 || true
+  # effect 判据（不信 rc）：该运行时根下不得再残留 herdr-core 监听 socket
+  t4_assert_eq "0" "$(ss -xlpH 2>/dev/null | grep -c "$RRT" || true)" "⑪ 真 hc 收尾：私有运行时根下 0 个监听 socket"
```

注意：`ss` 属可选能力，若要保持本用例零额外依赖，可改为「按 `/proc/<pid>/fd` 或 `pgrep -f` 反查 `$RRT`」的等价判据；无论哪种，**判据必须是 effect，不能是 rc**。

### 已执行清理（本验证轮的收尾，已复核）

- 先按监听 socket 反查 PID，**只杀** `comm=herdr-core` 且 socket 在 `/tmp/nao-t4.*` 的进程（用户 `~/.config/herdr` 的 `herdr` 会话未触碰：前后均在线）。
- 清理前后：监听 `nao-t4` 93 → **0**；`/tmp/nao-t4.*` 目录 13 → **0**；`git status --porcelain` 仅 `?? .pi/`（与本批无关）。

### 修复排期建议

- 不阻断 v0.33.0（产品面全绿）。
- 建议随下一批（或本批 PM 允许时）修：改 1 词 + 补 1 条 effect 断言，修复后重跑 `--case 44` 并复核「跑后监听数 0」，再进 PR 评论。
