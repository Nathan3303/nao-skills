# QA 独立复核：`status` 的 pane cwd 键口径修复（M20261101 · v0.21.1）

- 状态：待 PM 验收 · 更新：2026-11-02 · Owner：qa
- 指针：PRD `docs/prds/2026-11-01-status-pane-cwd-key.md`（AC1–AC5 · D1–D4）· RD 报告 `docs/reports/M20261101-status-pane-cwd-rd.md` · 分支 `nao/status-pane-cwd-key` @ `5fb0fe4`（Draft PR #63）

## TL;DR

- **结论 GO**：AC1–AC5 全通过、未过项 0、缺陷 0，不阻塞 v0.21.1（PATCH）。
- **独立证据（不复用 RD 用例作唯一依据）**：自建夹具 **40/40 PASS**（含 BR5 分屏双向排布）· 真机 pi-intercom 探针 **2 轮 4 份输出 md5 全同** · 键口径变异自做**点名 FAIL** 且零污染真仓库。
- **门禁（自跑）**：`check` rc=0（roles=6 · files=50）· `npm test` rc=0 · `test:t4:full` ×2 rc=0（20 用例 · PASS=20 · FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=2 全白名单）· `--case 19` ×2（各 62 断言 · FAIL=0）· `roles.yaml` diff 0 字节。
- **RD 两条遗留本批关闭**：真机探针（md5 自算，不采信 RD 值）· BR5 多 pane 同会话名（已单建分屏夹具证明未退化）。

## 一、范围 / 不测

- 范围：AC1–AC5 全量 + 真机名册路径零回归 + BR5 拼接语义 + 禁改区逐文件核。
- 不测：真实 broker 抖动时序（不可确定性，另批观察）· 下游三仓接入（另批）· 发布流水线/npm 实测（PM 职责）。
- 纪律：夹具根 `/tmp/qa-m20261101`（硬断言不在任何 git 仓内）· tmux **隔离 socket** + `env -u TMUX`（禁裸 kill-server）· 未改实现、未改 RD 用例、变异只做在副本。

## 二、环境与命令

- 环境：tmux 3.8 · 真 `intercom-probe.mts`（`~/.pi/agent`）· 自建夹具三件：`lablocal`（本仓锚）/ `otherrepo-qa19`（他仓）/ `noagent`（无 tsx ⇒ 名册不可用）。
- 命令：`bash .agents/scripts/nao-fleet.sh check` · `npm test` · `npm run test:t4:full` ×2 · `bash tests/t4/run.sh --case 19` ×2 · 自建 `bash /tmp/qa-m20261101/qa-lab.sh`（40 断言）。

## 三、结果

### 真机（AC5① · RD 遗留 2）

- 新版与 `git show main:.agents/scripts/nao-fleet.sh` 旧版各跑 2 轮，`diff -u` 全空；4 份输出 md5 均 **`acfb0574bcabc3f994a8e3e3d1524ce1`**（自算，未采信 RD 的 `2ff03906…`；后者为其当次环境快照，与本轮派发会话集合不同，不影响等价性结论）。
- 名册可用性自证：旧版 `pane_cwds` 恒空，其两行派生会话仍判本仓（`? … 仅散文提及 … close --task`）⇒ 该结论只能来自名册 cwd；探针实列 4 条，含 `rd-infra-M20261101`、`qa-M20261101`（cwd=本仓）。

### 自建夹具 40/40 PASS

- **G1 pane-only（名册不可用）**：① 本仓 pane ⇒ 行首 `·`、`! 残留`、含可执行 `close --task T9001 rd-infra`，非 `?`；② 他仓 pane ⇒ `~ （他仓 @ otherrepo-qa19）` 且整行无 `close --task`；④ 标题契约不命中且名册无 cwd ⇒ 仍 `?（归属不可判定）`、无命令（BR2 未退化）；`status` 连跑两次逐字一致。
- **G2 冲突（名册登记本仓 / pane 在他仓）**：判 `~`（pane 优先，AC3）；同轮仅名册可见的 `qa-T9005` 也判 `~` ⇒ 证明名册路径确在生效，非“名册整体失效”造成的假象。
- **G3 夹具级零回归**：同一名册夹具下新旧输出 md5 相同（脚本 md5 确不同，对照有效）。
- **G4 BR5 分屏**：同会话名 2 pane「他仓在前 + 本仓在后」判 `·`（排除只取首 pane）；「本仓在前 + 他仓在后」亦判 `·`（排除只取末 pane）；2 pane 皆他仓判 `~`（排除恒本仓）；两条 pane 顺序均以 `pane_current_path` 自证。
- **变异负控（AC5②）**：副本把读序改回 `read -r pn pname pcwd`（pane_id 建键）⇒ 我方 AC1 断言点名 FAIL、该行回落 `? … 归属不可判定` 且无命令；真仓库脚本 md5 与 `git status` 前后一致，还原后无残留副本。

### 门禁数字

- `check`：rc=0 · roles=6 · files=50 · layout=main-row2。
- `npm test`：rc=0（scripts 含 `check` + `tsc` + t4）。
- `test:t4:full` ×2：20 用例 · PASS=20 · FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=2（`06:static-contract` ×2，非白名单 NOTE=0）· rc=0。
- `--case 19` ×2：各 **62** 断言 · FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=0 · rc=0（修前 38 ⇒ +24）。
- `git diff --stat .agents/roles.yaml` = 空（diff 0 字节）；未推送 0（复核基线 `5fb0fe4` 与远端一致；本报告随分支追加提交）。

## 四、禁改区（`git diff main...HEAD` 逐文件核）

- 改动面共 5 文件：`nao-fleet.sh`（+4/−4，单处 hunk，:1657–1660 读序 + 注释）· `tests/t4/cases/19`（+98/−4，删除 4 行仅为 `run_status` 增参）· PRD · RD 报告 · `tasks-state.md`（M 编号订正 + 立项行）。
- `session_repo_verdict` / `repo_contains_path` / `repo_anchor_roots` / `card_role_set` / `task_state_class` / `cmd_ensure` / `cmd_close` / `cmd_check` 在 diff 中出现 **0** 次；fail-closed 文案未动；`roles.yaml` 未动。

## 五、缺陷

- 无（致命 0 / 严重 0 / 一般 0 / 轻微 0）。

## 六、未覆盖与风险

- 未覆盖：真实 broker 抖动（名册时有时无）的时序场景 —— 本修不依赖抖动时序，行为由“名册可用/不可用”两态覆盖。
- 风险（低）：pane 优先生效后，若某 pane 标题被外部改写成同会话名且其 cwd 在他仓，将按 pane 判 `~`（BR4 既定语义，且仍 fail-closed 不给命令）；标题契约本身由 pi OSC 维护，非本批引入。
- 观察（非本批）：真机两行派生会话的「仅散文提及」属 tasks-state 归处口径，与本修无关。

## 七、发布建议

- **GO**：按 D4 发 **v0.21.1（PATCH）**；`nao-fleet.sh` 属包内容 ⇒ `npm` 需重发，成功判据用 registry 直连（`latest` + `dist.integrity` 与本地 tarball 逐字节一致）；回滚 = revert 单条 squash。

## 八、遗留（三出口）

- RD 遗留 1（BR5 多 pane 未单建夹具）→ **本批关闭**：已分屏验证双向排布。
- RD 遗留 2（真机探针未跑）→ **本批关闭**：2 轮 md5 自算等价。
- `T537-O3`/`O4` → **接受**（到期 2026-12-31），本批不夹带；无新增遗留。

- 修订：2026-11-02 首版（独立复核 GO · 自建夹具 40/40 · 门禁全绿）
