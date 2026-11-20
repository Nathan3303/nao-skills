# T553 / Issue #139 联动仓 manifest —— QA 一轮复核（加速档）

- 状态：**CONDITIONAL**（5 点过 + 1 个 AC2 逐字偏差 + 1 个测试侧标签漂移，两处均 ≤1 行改；无功能性阻塞）
- 更新：2026-11-20 · Owner：qa · 分支 `feat/139-fleet-manifest` · HEAD `04a7627` · **只读**（未改码；变异在 /tmp 副本，已删）
- 判据：PRD `docs/prds/2026-11-19-fleet-manifest.md` AC1–AC10 · ADR `2026-11-19-fleet-repo-manifest.md` · `docs/reports/139-lite-spec.md`
- 自跑门禁：`check` rc=0 · roles=7 · files=52；`bash tests/t4/run.sh --case 39`（herdr）`RESULT: PASS` · SKIP=0/DEGRADE=0/NOTE=0。全量/双后端与 `--fast` 采用 PM 回执（加速档约定不重跑）。
- 环境：herdr 0.9.5 + `tests/t4/fixtures/herdr-double`（PATH 替身）；自建夹具：无 manifest 双树（main=v0.25.2 / HEAD，同 .agents 内容仅脚本不同）+ 多仓 manifest 场 + 桩 `pi`。

## 六点判定

1. **AC2 零回归 —— 不通过（1 处逐字偏差）**。同一无 manifest 夹具两树对照：`ensure`（默认 tier / `--fleet` / `fleet-scope` 三档）的 rc + stdout + stderr、交给后端的调用序列（除 `--append-system-prompt` 的 mktemp 随机后缀）、pane/workspace/tab 快照、`check` 输出、`close` 输出**全部逐字相同**；唯一差异 = `status` 的常驻 ✓ 行：
   `（…frontend-developer.md）·fleet=zzq` → `（…frontend-developer.md） ·fleet=zzq`（多 1 空格，3/3 行）。
   根因：新增 `_status_scope_tag` 返回带前导空格的 `" ·fleet=…"`，而旧 printf 是 `%s）·fleet=%s`（注释自称「既有行格式不动」）。既有断言只做 contains ⇒ 全量绿也咬不住。
2. **AC1 主路径 —— 过**。夹具（`slug: alpha` + `api: ../mfapi`）：`ensure rd-be@api` ⇒ 名 `rd-be@api` · pane cwd=`/…/mfapi`（phys）· `workspace_id` = 主仓 B 的 `w2`（label=alpha 计数仍 1）· tab label `api/rd-be@api`（主仓 = `main/rd-be@alpha`）。
3. **R2 `@` 四步 —— 过（含定向反放宽）**。① code 命中 ⇒ `OK linked`；② `@../mfapi` ⇒ `OK path`，ensure 层得 `qa@mfapi` / ws label=`mfapi` / tab **无**前缀 ⇒ **既有仓路径语义未被 code 抢走**；③ `main/api` 同名目录在场 ⇒ `@api` rc=1 点名两物理路径、零 pane（4→4）；把两处冲突判定改 `if false` 的副本 ⇒ 同输入变 rc=0（探针能咬住「先试 code 失败再当路径」的放宽）；④ `@nope` / `@` 空段 ⇒ rc=1 列 api/web/alpha + 「@<仓路径>」写法。
4. **AC3 非法 manifest —— 过**。缺 `slug` / `code` 撞 `slug` / `path` 不存在 ⇒ rc=1 且 `fleet.yaml:<行号>` 行号准确（1 / 3 / 4）；另测未知键(2)、`code` 重复(5)、非法字符(5)。ensure 层缺 slug ⇒ 零 pane（5→5）；case 39 的 F 11 项覆盖其余字段。
5. **禁改区 —— 过**。代码文件仅 `nao-fleet.sh`；`tests/t4/lib-backend.sh` 0 改动；cases 09/13/37/38 未动。函数体 md5 全 IDENTICAL：`fleet_of_invocation` · `fleet_name_build/parse` · `fleet_scope_problem` · `fleet_core_build` · `intercom_cwds_for` · `_close_anchor` · `_close_dedupe_cwds` · `_close_adopt_repo` · `_term_herdr_close_pane`（另 `intercom_roster` / `roster_pane_claims` / `repo_anchor_roots` 同）。`cmd_close` 唯一变更 = M5 允许的 manifest 回落块。`docs/tasks-state.md` 有改动但仅出现在 PM 提交 `05ace15`（发布事实 + T553 登记），不在实现提交里。
6. **RD 自报 3 处**：
   - ① 过：cases/28 两锚点随实现改名/改字段（`group` 参数、`t_fleets←scope_name`），变异意图不变、未削弱断言（锚点失配仍走 `t4_bad` 硬红）。另有第 4 处 `cases/06` 用例文件计数 37→38，属必要登记。
   - ② **不过（必要性问题）**：`backend-no-signal` 已进白名单 + `tests/README.md`，但全仓 **0 个调用点**；cases/39 的 tmux tab 门用的是 `backend-gate`（L43、L316），与 139-lite-spec M 行点名的 `backend-no-signal` 及 README「cases/39 … `backend-no-signal`」不符 ⇒ 新增 tag 无使用面。改法二选一：case 39 L43 改用 `backend-no-signal`（按判据单源），或撤回该 tag + README 条目。
   - ③ 过：`AGENTS.md` 一行 = M6 / AC9③ 指针，必要且不涉断言。

## 结论与建议

- **无功能性阻塞**：AC1/AC3/AC4/AC6/AC7/AC8/AC10 实测成立；未发现派错仓、漏回收、静默两义兜底。
- 需裁两项：**A**（必修或显式接受）`status` 常驻行多一个空格 ⇒ 违反 AC2「逐字一致」；1 行修（helper 不带前导空格，或恢复该行原格式）。**B**（择一）`backend-no-signal` 标签漂移。
- 建议：**CONDITIONAL** —— 修 A、B 择一后即可 squash 合并；若决定不修 A，请 PM 在 PR 验收评论写明「接受 status 常驻行 +1 空格的逐字偏差」。
- 收尾：`git status --porcelain` 仅本报告；/tmp 夹具与替身会话已拆（无残留 server / 无孤儿 pane）。
