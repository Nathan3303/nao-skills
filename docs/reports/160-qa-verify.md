# #160 P0 独立复核（QA）：ensure 不再把「只有用户自己 pane 的 workspace」判空并关掉

- 状态：已复核（`done(full)`）· 更新：2026-11-23 · Owner：qa · 任务 T558
- 指针：Issue #160 · PR #162 · 复核对象 HEAD `2ee97fa`（base `main` @ `d8e4d09`）· 机制包 v0.29.0 候选（本批未 bump 版本）
- 性质：**只读复核**。不复用 RD 的用例 43；独立造场景、独立造变异、独立跑门禁。

## 结论

**done(full) · 0 P1 / 0 P2 / 3×P3（不阻塞）。**

- P0 修复成立：基线真发出 `workspace.close` 并杀掉用户 pane；本分支同场景零 close、pane 存活、角色 tab 落**同一** ws。
- 关前护栏三向成立：根因回退 + 护栏 ⇒ 不关 + fail loud；复核恒 0 ⇒ 关 + pane 被杀（负控生效）；复核不可用 ⇒ 不关 + fail loud。
- 全范围门禁绿：`check` rc=0、`npm test` 40 例 2513 PASS / 0 FAIL、`--case 43` 60 PASS / 0 FAIL。

## 复核方法（与 RD 用例无关）

用 `git archive` 出两棵独立树：基线 `d8e4d09` 与本分支 `2ee97fa`（目录同名 `repo` ⇒ 放置键 `repo` 相同）。各自在**独立 XDG 根 + 独立 herdr session**（`qa558-base` / `qa558-fix` 及变异 session）里造「label=`repo`、只有**无 label 的用户 pane**」的 workspace，跑 `ensure rd-fe`。`pi` 用记录 argv 的桩（`exec sleep`）代替真会话 ⇒ 可观测、不产生真 pi 会话；就绪门因此计 SPAWN_FAIL，与 P0 判据无关。

4 个消费点的修前/修后对照另用仓库既有 herdr 替身夹具（`tests/t4/fixtures/herdr-double`）+ 自写断言脚本完成（46 项全过）。

## 1. 修前红（基线 `d8e4d09` · 真 herdr · 隔离 session `qa558-base`）

场景：workspace `w1`（label=`repo`）唯一 pane `w1:p1` **无 label**，cwd=基线树；pane 内起 `pi --name user-self`（桩）；跑基线脚本 `ensure rd-fe`。

`herdr-server.log` 原文（时间戳与转义保留）：

```text
2026-11-23T10:55:33.661121Z  INFO herdr::logging: api request received event="api.request.start" subsystem="api" outcome="started" request_id="cli:workspace:close" method="workspace.close" changes_ui=true
2026-11-23T10:55:33.661196Z  INFO herdr::logging: workspace closed event="workspace.close" subsystem="workspace" outcome="ok" workspace_id="w1"
2026-11-23T10:55:33.661620Z  INFO herdr::logging: pane child exited event="pane.exit" subsystem="pane" outcome="completed" pane_id=1 status="ExitStatus { code: 1, signal: Some(\"Hangup\") }"
2026-11-23T10:55:33.670279Z  INFO herdr::pane: pane session terminated pane=1 pid=2135089 signal=Hangup
```

随后 `workspace.create` 建 `w2` / 新 pane `w2:p1`（label `rd-fe`）。核对：`workspace list` 只剩 `w2`；`pane process-info w1:p1` ⇒ `pane_not_found`。**用户 pane 被杀，缺陷复现。**

## 2. 修后绿（HEAD `2ee97fa` · 隔离 session `qa558-fix`）

同场景（`w1` / `repo` / 唯一无 label pane `w1:p1`，先起 user-self 桩，再跑 `ensure rd-fe`）：

- `herdr-server.log` 中 `workspace.close` / `workspace closed` 计数 **= 0**；
- `workspace list` ⇒ `w1`（label=`repo`，pane_count=2 / tab_count=2）；
- `w1:p1` 存活（`pane process-info` 仍返回 user-self 桩进程）；
- `w1:p2` label=`rd-fe`、tab=`w1:t2`（角色 tab 落**同一 ws**）；
- ensure 摘要「成功 0 / 跳过 0 / 失败 1」只因桩 pi 不满足就绪门，与 P0 判据无关。

## 3. 关前护栏三向（自造变异）

- **3a 根因回退 + 护栏保留**（仅 `_TERM_PLACE_FS` 改回 `$'\t'`）：零 close；stderr 原文
  `空 workspace 判据与实测冲突：workspace=w1 快照判 0 pane，实测 1 pane ⇒ **不关**（关掉会连带杀掉在场会话）`；用户 pane 存活。
- **3b 3a + 复核函数恒返回 0**：`workspace closed workspace_id="w1"` + `pane child exited … Hangup` 真发出；`w1:p1` ⇒ `pane_not_found`；新 ws `w2`。**证明护栏是最后一道防线（负控生效）。**
- **3c 3a + 复核函数恒 `return 1`（后端不可用）**：零 close；stderr 原文
  `workspace 关闭前复核失败（workspace=w1：pane list --workspace 不可用）⇒ **不关**（无法证明它是空的）`；用户 pane 存活。

## 4. 同族字段（纯函数，逐位）

直接 eval 本分支的 `_TERM_PLACE_FS` / `_term_place_pane_row` / `_term_place_pane_fields`：

- 分隔符字节 = `1f`（US，非 IFS 空白类）；
- 5 组行（空 label、空 cwd、空 fgcwd、空 wsid、连续两空字段）共 **20 项逐位断言全过**；
- 独立复验根因：同一行用 TAB 拼 + `IFS=$'\t' read -r a b c d e f` ⇒ `a=w1:p1`、`b=w1`、`c=w1:t1`、`d=/repo`、`e=/repo`、`f=''`（整体左移一格，与 #160 描述一致）。

## 5. 消费点抽查（≥4，修前/修后实测；46 项全过）

- **spawn 空 ws 判据（`first`，P0）**：见第 1/2 节。**真实差异**。
- **`_ensure_ws_panes_in_repo` 仓归属**：他仓 cwd 的 `repo` ws（唯一 pane 无 label）。
  修前：判「全在仓内」复用该 ws（随后 P0 分支关掉它）⇒ 1 个 ws、用户 pane 被杀；
  修后：判他仓 ⇒ 让号 `repo2`，他仓 ws `w1` 保留、fleet pane 落新 ws `w2` ⇒ 2 个 ws、零 close。**真实差异**。
- **`_term_herdr_pane_tab` 归属**：同一快照行——修前对无 label pane 返回空；修后返回 `w1:t1` / `w1`。**真实差异（归属面）**。
- **判重「已在运行」+ 槽位取名**：ws 内已有 `rd-fe2(T1)`（label 正确）+ 无 label 用户 pane。
  修前/修后**都**命中「已在运行」（摘要 成功 0 / 跳过 1 / 失败 0、零新建、零 close）；随后 `ensure --task T2 rd-fe` 两版都取 `rd-fe2(T2)` 并落同一 ws。**无修前/修后差异**。
- 对照：`_ensure_slot_taken` 在本分支**无调用点**（全仓仅定义），把它写成「消费点行为变化」不成立。

## 6. 旧行为不退化

- 替身夹具造「label=`repo`、0 pane」的旧 ws：修后仍发出 `workspace close` 并重建（新 ws id、label 仍 `repo`、fleet pane 就位、摘要 成功 1）。
- 真 herdr 补充实测：关掉 workspace 最后一个 pane 时 herdr 会自动删除该 ws（`workspace list` 变空）⇒「真·0 pane ws」只能来自状态残留/并发，替身造态是合理覆盖。

## 7. 静态闸

- 真件：`t4_scan_place_pane_rows` 命中 **0**；`_TERM_PLACE_PANE_ROWS+=(` 全仓**恰 1 处**且走 `_term_place_pane_row`。
- 正向控制：塞一条 `IFS=$'\t' read -r a b c <<< "$line"` ⇒ 命中 2 行（裸 read + TAB 运算）；删掉访问器调用 ⇒ 命中「缺访问器」。**两向都红。**

## 8. 全范围门禁（精确数字）

- `bash .agents/scripts/nao-fleet.sh check` ⇒ **rc=0**（`check: OK · roles=7 · files=53`）。
- `npm test`（`tests/` 全目录，非子目录）⇒ **rc=0** · **40 例** · **2513 PASS / 0 FAIL** · `SKIP=0 · DEGRADE=0 · NOTE=17（全白名单）` · `RESULT: PASS`。
- `bash tests/t4/run.sh --case 43 -t` ⇒ **rc=0** · **60 PASS / 0 FAIL** · `[TIMING] 合计 11.030s` · `RESULT: PASS`。
- `status` 回归对照：同一 session/cwd 下基线与本分支 `status` 输出 `diff` **无差异**。

## P3（不阻塞合并）

1. RD 实现报告「10 消费点 修前→修后」表把 `_ensure_slot_taken` / `_ensure_task_name_in_ws` / `_ensure_pick_num` / spawn 同名判重 / `set_pane`/`drop_pane` 都写成有行为差异；独立实测这些点在**有 label 的行**上修前/修后一致（空 label 行两版都不会匹配合法名）。真实差异只有 spawn `first`、`_ensure_ws_panes_in_repo`、`_term_herdr_pane_tab`。建议报告口径收窄（勿把「同族改写」当「行为差异」引用）。另：`_ensure_slot_taken` 全仓无调用点（既有死函数，非本批引入），可在后续清理。
2. `tests/t4/lib.sh::t4_scan_place_pane_rows` 注释写「当前 6 处消费点」，实际扫描 **10** 个循环（`nao-fleet.sh` 行号 995/1010/1090/1113/1241/1333/4070/4133/4160/4188）；注释与实现漂移。
3. 静态闸只匹配 `for … in "${_TERM_PLACE_PANE_ROWS[@]:-}"` 这一写法；未来若新增不带 `:-` 的 `[@]` 循环将不被扫描（当前全部带 `:-`，无实际绕过）。建议放宽正则或改为按变量名扫描。

## 环境与收尾

- 隔离根 `/tmp/t558qa/config`（`XDG_CONFIG_HOME`）；全部自造 session（`qa558`、`qa558-base`、`qa558-fix`、`qa558-mutA`、`qa558-mutB`、`qa558-mutC`、`qa558-empty`）已 `cleanup --session` 收掉，`herdr session list` 仅剩 stopped `default`，无残留 server 进程；未触碰生产 session。
- 未改功能/测试代码；本文件是本批唯一新增。
