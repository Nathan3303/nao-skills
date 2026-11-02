# T538 门禁数字可复现口径 —— QA 点检报告

- 状态：复核后 **AC1 改判 = 过**（待 PM 验收；仅余 1 项文档订正 P1-b）· 更新：2026-11-02 · Owner：qa
- 指针：PRD `docs/prds/2026-11-02-gate-number-provenance.md`（AC1–AC5）· RD 报告 `docs/reports/T538-gate-number-provenance-rd.md` · 分支 `nao/gate-number-provenance`

## TL;DR

- **结论 = 复核后通过（首轮 CONDITIONAL）**：AC2–AC5 过；**AC1 首轮部分未过 → 补丁 `0f24293` 后改判 = 过**（模板与协议条已同步三件套，照模板填即合格，依据见 §六）。仅余 P1-b：RD 报告「变更清单（8 文件）」实为 **7**（文档订正，不阻塞）。
- **AC3 vs AC4 取舍成立**：三侧指针分别落在各自「门禁回执数字」条（`pm.md:110` / `qa.md:23` / `rd-infra.md:19`），无「某侧未覆盖」空洞；条数 94/32/22 零漂移（与 `main` 逐一相同）。
- **门禁**：三重 rc=0（`check` OK roles=6 files=50 · `npm test` PASS · `test:t4:full` PASS，非白名单 NOTE=0）；20 例 / 694 断言 / 未推送 0。
- **待办**：P1-b 由 RD 订正（8 → 7）；P2-a/P2-b 已由 PM 判「接受不做」；P3-b 接受；P3-d 观察项见 §六。

## 一、环境与命令（三件套自证）

- 门禁在 `2ab2e9c`（机制最终态）与本报告所在 HEAD 各跑一轮，数字完全相同；两轮 `git status --porcelain` 均为**空**；同 worktree 无其他会话跑门禁（本会话独占）。
- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=6 · files=50 · layout=main-row2`，rc=0。
- `npm test` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）`，rc=0（日志内 20 条 `RESULT: PASS`）。
- `bash tests/t4/run.sh --list | tail -n +2 | wc -l` → `20`。
- `bash tests/t4/run.sh 2>&1 | grep -c '\[PASS\]'` → `694`（与例数不同轴）。
- `npm run test:t4:full` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）`，rc=0 ⇒ 非白名单 NOTE=0（2 条均 `06:static-contract`）。
- `find "$NAO_SKILLS/.agents" -type f | wc -l` → `50`（与 `check` 的 `files=` 一致；需先 `export NAO_SKILLS=<包根>`，见 §三.5）。
- `git show --shortstat --oneline 2df07f9` → `5 files changed, 15 insertions(+), 5 deletions(-)`；`2ab2e9c` → `1 file changed, 46 insertions(+)`；分支累计 `git diff main...HEAD --shortstat` → `9 files changed, 155 insertions(+), 7 deletions(-)`。
- `timeout 60 git fetch origin --prune`（HTTPS）rc=0 ⇒ `git rev-list --count origin/nao/gate-number-provenance..HEAD` = **0**（未推送 0），`HEAD..origin/main` = 0（不落后）。

## 二、点检七项（逐条判定）

1. **AC2 单源 = 过**。四条命令串（用例数 / `grep -c '\[PASS\]'` / `find "$NAO_SKILLS/.agents"` / `git show --shortstat --oneline`）在 `.agents/**` + `tests/README.md` 合计各 **1** 次，全部落在 `tests/README.md:35-38`；三份清单内命中 **0**。改前复算一致：`run.sh --list` 正文改前 3 次（`tests/README.md` 同一行 2 次 + `pm.md` 1 次）→ 1 次，与 RD 自述相符。
2. **AC1 三件套可执行性 = 部分未过**。三条本身可按做：静默工作区有机械判定（`git status --porcelain` 空）、HEAD 可 `git rev-parse HEAD` 记短 sha、计数数字被指向单源四条命令并明令禁「我数了 N」——照 `output-format.md:33-36` 写能产出合格回执。**但**该文件开头即要求「派发/回执前读取」`comm-templates.md`，而后者给的两份「可直接复制」模板**均只含 `命令 + exit code + 文件数/例数/红数`**：缺 HEAD、缺静默工作区、缺「输出」；其 `commit=` 易被误当 HEAD（那是交付提交，不是跑门禁时的 HEAD）。⇒ 照模板填 ⇒ 产出即不合格，AC1 的生效路径被自身模板截断（P1-a）。
3. **AC1 反例有效性 = 过**。反例 `测试：npm test 通过，t4 21 个用例全绿` 点名四项缺失（无 HEAD / 无命令 / 无工作区状态 / 21 = 最大编号而实测 20），并给出**判定动作**「⇒ 打回，补齐 HEAD + 静默工作区状态 + 命令与输出后重报」，不停留在措辞。
4. **AC3 vs AC4 取舍 = 成立，无空洞**。三侧指针都改在**各自唯一出现「门禁回执数字」的那一条**（PM 计数条 / QA 全范围门禁红线 / RD 全范围门禁红线），措辞贴合各自风格（QA 仍为问句、RD 仍为断言式 `- [ ]`），且 `output-format.md` 作为全体角色常驻条款构成第四道同源约束。代价是 `qa.md:23` 单句增至约 190 字（可读性下降，P3-b），不构成未过。
5. **风险 3 复现 = 成立（表述需精度订正）**。`env -u NAO_SKILLS bash -c 'find "$NAO_SKILLS/.agents" -type f | wc -l'` → 输出 `0`、**管道 rc=0**；同时 `find` 向 stderr 报 `find: “/.agents”: 没有那个文件或目录`。即「计数层面静默得 0」成立，但**并非完全无声** —— 只看计数/退出码的人会被骗。`tests/README.md:37` 已写该易错点（「`NAO_SKILLS` 未设置时 `find` 会**静默得 0**」），建议补半句「（stderr 有 find 报错）」（P3-c）。本次实测亦踩到：会话内 `NAO_SKILLS` 默认未设。
6. **零改名 = 过**。`git diff main...HEAD --name-status` 共 9 项（4 改机制文本 + 5 项 docs），**无 R/A 以外的结构变更**；`nao-fleet.sh`、`tests/t4/**`、`roles.yaml` 的 diff 行数均为 **0**（`roles.yaml` blob 两侧同为 `270b758`）。
7. **门禁 = 过**。见 §一：`check` rc=0（roles=6 · files=50，与 `find` 交叉一致）· `npm test` rc=0 · `tests/t4` **20 例** `RESULT: PASS` ×20 · `test:t4:full` rc=0 且非白名单 NOTE=0 · 未推送 0（fetch 后实测）。

## 三、缺陷 / 未过项

- **P1-a（一般 · 已由 `0f24293` 修复 ⇒ AC1 改判过，见 §六）**：`checklists/comm-templates.md:25` 与 `:38` 的两份模板、`common/intercom-protocol.md:90` 的「终态回执」硬性条，仍只要求 `命令 + exit code + 文件数/例数/红数`，与 `output-format.md:33-36` 的三件套冲突。后者是本批唯一新口径，前者是**执行时真正被复制的形态**与**所有角色常驻的硬性闸门** ⇒ 不补则「同一套回执口径两处表述」原样回潮（正是本批要消灭的病）。修法成本低：模板补 `<HEAD> · 静默（porcelain 空）` 与「命令 + 输出」，协议条加「三件套见 output-format 第 3 条」指针；**不新增 `- [ ]` 条目、不动三份清单 ⇒ AC4 不受影响**。
- **P2-a（建议）**「同一 worktree 无其他会话正在跑门禁」无判定手段（无命令、无自检项），回执只能凭自述；建议给一条可判定的写法（如「本会话独占」+ 可选 `nao-fleet.sh status` 佐证）。
- **P2-b（建议）** 只有不合格反例、无**合格回照样例**；补一条 3–4 行的合格样例可让「照它写」从"能推"变成"能抄"。
- **P3-a（口径说明 · 已由 `0f24293` 补入 `tests/README.md:34`）** AC2 的「唯一」只对 `.agents/**` + `tests/README.md` 成立；`docs/**` 仍有 17 个文件、32 行历史引用（不含本报告；PRD §BR1 已许作证据）。若日后有人用 `grep -r` 全仓复核会误判违规，建议在 `tests/README.md` 该节补一句「历史文档（`docs/**`）引用不计正文」。
- **P3-b（可读性 · 接受）** `qa.md:23` 单句约 190 字，建议后续拆分（拆分亦不增条目）。
- **P3-c（表述精度 · 已由 `0f24293` 补入 README `files=` 易错点）** 「静默得 0」已补「stderr 报错、管道 rc 仍 0」⇒ 计数静默 ≠ 无声，与实测一致（§六）。

## 四、未覆盖与风险

- 不测：`test:t4:full:dual`（非发布批，PM 点检未要求）；无 UI/视觉面（纯文本）。
- 生效性只能观察：PRD §八 监控项（下 2 批回执是否仍缺 HEAD/命令）为唯一真实检验；本报告 §一 即按新口径示范。
- 若 P1-a 不补，本批「单源」只覆盖"数字怎么算"，未覆盖"回执长什么样"——北极星（不可复现的计数数字 = 0）仍会被模板绕过。

## 五、发布建议

- **建议有条件通过**：补 P1-a 三处文本（`comm-templates.md` ×2 + `intercom-protocol.md` ×1，均为 `.agents/**` ⇒ 需重跑 `check` + `npm test`）后 QA 只读复核一次即可 GO；若 PM 判「模板顺延下一批」，则登记 `T538-O1` 并写明到期（否则口径双写回潮，AC1 半达）。
- 本批「只合并不发版」不变；合并后 main 机制文本领先 npm 0.21.2 的状态须在台账保留。
- 我未修改任何功能/机制代码，仅新增本报告（`docs/` 单文件）。

- 修订：2026-11-02 首版（七项判定 + P1–P3 五条）；同日补丁 `0f24293` 复核 ⇒ **AC1 改判过**，新增 P1-b / P3-d。

## 六、复核（2026-11-02 · 补丁 `0f24293`）—— AC1 改判

- **AC1 改判 = 过**。把 `comm-templates.md` 两份模板当表填一遍（真实数字：HEAD `0f24293` / 20 例 / 694 断言 / `files=50`）：lite 填充 = 1 行 511 字符、full = 9 行；填出的 `测试：` 段同时含 `HEAD=0f24293`、`工作区=静默（porcelain 空 + 本会话独占）`、每个计数数字后的「命令 → 输出」，且 `commit=` 明标「交付提交 ≠ 门禁 HEAD」⇒ **通得过 §二.2 自定判据**，生效路径不再被模板截断。
- **项 2 协议一致 = 过**：`intercom-protocol.md:90` = 「旧枚举 + 三件套三项命名 + 双指针」，全文复写 **0**（`porcelain` 0 处、命令串 0 处），与 `output-format.md:33-36` 无冲突。
- **项 3 P3-a = 到位**：`tests/README.md:34` 写明复核范围 = `.agents/**` + 本文件、`docs/**` 历史引用不计违规；抽样 `docs/releases/v0.20.4.md:28` 的旧命令串 ⇒ 按新句**不算违规**（全仓 `grep -r` 已明确不作判据）。
- **项 3 P3-c = 与实测一致**：`env -u NAO_SKILLS … find … | wc -l` → `0`、`pipe_rc=0`、stderr `find: “/.agents”: 没有那个文件或目录`；README 新句「计数静默得 0、报错不静默」相符（引号字形随 locale，无实质差异）。
- **项 4 回归 = 过**（记录 1 次 flake）：`npm test` 第 1 跑 `RESULT: PASS（SKIP=1 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）`，SKIP 命中**用例 02**（`pi 未成功启动或无输出（rc=124，stdout=60690B）`）；第 2 跑同 HEAD 同工作区 `SKIP=0` ⇒ 复现既有抖动 `M20261102-F2`（此前 QA 7 跑 0 次，本次为首次命中），**非本批引入**（本批机制文件仅文本改动）。四条命令串 `.agents/**` + `tests/README.md` 各 **1** 次、三份清单命中 **0**；条数 pm 94 / qa 32 / rd-infra 22（= `main`）；`check` rc=0 roles=6 files=50；20 例 / 694 断言；`test:t4:full` 非白名单 NOTE=0；未推送 0（数字见回执，门禁 HEAD 与之同）。

### 新发现（不改变 AC1 改判）

- **P1-b（轻微 · 转办 rd-infra）** RD 报告「变更清单（**8 文件**）」实测 **7**（`git diff main...HEAD --name-only -- .agents tests/README.md | wc -l` → `7`）。根因 = 两轮都改过的 `tests/README.md` 被重复计入（5 + `comm-templates` + `intercom-protocol` + `tests/README` = 8）⇒ **第 4 次同型计数标签错**（正是本批主题）。改 1 行即可（`docs/**`，不触发门禁重跑）。
- **P3-d（观察 · 非阻塞）** lite 单行在「四数字 + 每组命令 → 输出」下实测 **511 字符**，与「单行/短」初衷及「>300 字落盘」阈值有张力；建议后续 lite 只留 HEAD + 工作区 + 汇总 `exit/文件数/例数/红数` + 关键命令，输出明细下沉报告。
