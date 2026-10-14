# PRD：`close` 末段「无法确认在线状态」缺口补回归护栏

- 状态：**已交付并发布（v0.18.1）** · Owner：PM · 更新：2026-10-14
- **验收记录** = 2026-10-14 PM 验收**通过（AC1–AC8 全过）**：PR [#41](https://github.com/Nathan3303/nao-skills/pull/41) squash **`ef391af`**（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 独立复跑 **GO**（`check` rc=0 roles=6 files=46 · `npm test` rc=0 · 91.8s · **13/13 PASS** · SKIP=0/DEGRADE=0/NOTE=3 · **断言 267→282**）+ 三变异 MUT-C/D/E 全拦 + BR2 注册负控 + BR6 裸名实证 · 验收评论见 PR #41
- **发布记录** = 2026-10-14 **v0.18.1（PATCH）已发布**：发布提交 `292b3f4`（pin 升 0.18.1）· **tag `v0.18.1` + Release 已发**（**AC9 自证：`gh release view` name = `v0.18.1`** · `gh release list` 首行 Latest）· 发布前置 `test:t4:full` **rc=0**（空载 1m59s · SKIP=0 / DEGRADE=0 / NOTE=3）· **npm 不重发**（`package.json` 运行面不变）。
- 开工确认卡（2026-10-14 · ask-me 用户拍板 5 项）：D1 范围 = **按 QA 定稿**（C2 + `run.sh` 注册三行 + 6 条双侧断言 + MUT-C/D/E）· D2 `:1676` 文案 = **记台账新项 ⑯ 另批**（本批不碰机制脚本）· D3 版本 = **v0.18.1（PATCH）**· D4 立项 = **降级批次 `nao/close-guard`**（无 Issue）· D5 arch 评审 = **跳过**（QA 判定无结构决策；理由已记 §九）
- 指针：上游 = 用户 2026-10-14 选定台账待裁量项 **⑭**（T522 QA 报告 R2 实测缺口 · 「小批 · 小改测试代码」）· 成熟度判定 = 命中 `pm-to-spec.md` §一.4（用户明示范围 + R2 已给实测复现）· **QA 接缝复核** = 2026-10-14 `done(full)`（采 C2 但**补 `run.sh` 三行**；断言 6 条双侧；变异 **MUT-C/D/E** 实测）
- 优先级：中低（护栏补缺 · 低成本）· 战略筛子：命中「机制护栏 / 单一门禁可信度」→ 做 · MoSCoW：**Should** · Kano：基本型（缺护栏 = 静默假绿通道）· RICE ≈7.2（附录）

## TL;DR（≤5 行）

- **做什么**：新增 `tests/t4/cases/13-close-guards.sh`（6 条双侧断言）+ 在 `run.sh` 注册该用例，把 `close` 末段「无法确认在线状态 ⇒ 非静默失败」这一路径纳入默认门禁。
- **给谁**：本仓维护者（改 `close` 的人）、QA（复跑与变异控）、下游三仓维护者（照抄护栏口径）。
- **成功标准**：单点注入 `nao-fleet.sh:1671` 的 `if offline_verifiable` → `if true` ⇒ `npm test` **rc≠0 且恰新用例 FAIL**；基线 13/13 PASS；还原后全绿且 `md5` 一致。
- **不做什么**：不改 `.agents/scripts/nao-fleet.sh` 功能代码（含 `:1676` 文案，见 §三）· 不并入 `cases/09` · 不落一次性探针 · 不做 `/tmp` 夹具治理（⑮）· 不拆脚本（⑫后半）。

## 一、问题证据

- **实测缺口（T522 QA R2 · 2026-10-14）**：把 `.agents/scripts/nao-fleet.sh:1671` 的 `if offline_verifiable; then` 单点改为 `if true; then`（即把「未运行（无需回收）」静默 no-op **永久化**）⇒ **`npm test` rc=0 · 12/12 全绿**，无任何用例拦截。复现成本：单点 sed + 全量跑批 104s。
- **缺口本质**：`close` 末段有三条出口 —— ①名册报在线但无句柄 ⇒ warn + rc≠0；②常驻缺席而派生在场 ⇒ 拒绝 + rc≠0；③`offline_verifiable` 为真 ⇒ 静默「未运行（无需回收）」rc=0；④**兜底**：宿主无 tmux/screen 句柄且名册不可用 ⇒ warn 三条 + rc≠0（`:1674-1678`）。既有 `cases/09` 覆盖了 ①②③ 的多数形态，**但从未构造 `offline_verifiable` 为假的环境**，故 ④ 与其守卫（`:1671` 的判据）无护栏。
- **5 Whys**：删掉判据不会被发现 ← 无断言覆盖兜底分支 ← 既有用例只造出「名册可用」与「真离线」两种环境 ← 夹具设计时把 `offline_verifiable` 当作环境事实而非被测对象 ← 无人把「判据本身」列为可测契约（T522 才引入「接线/判据须有负控」的口径）。
- **可观察代价**：③ 被永久化后，`close` 会在**无法确认在线状态**时宣称「未运行（无需回收）」并 rc=0 —— 使用者据此认定会话已收拾干净，实际可能残留 pane/进程（与 T515/T516 血训同类：静默状态谎言）。
- 证据留痕：`docs/reports/2026-10-14-T522-qa-verify.md:54`（R2）· `docs/tasks-state.md` 待裁量项 ⑭ · 本轮 QA 只读实测（MUT-C 实测 ①②③ 同时 FAIL）。

## 二、目标指标

- **北极星**：`close` 的**在线状态判据**被默认门禁机械守护 —— 判据被删/被短路（`if true`）/被收窄（删 `NAO_TERMINAL` 子句）**都**会被拦。
- **预期**：基线 **13/13 PASS · rc=0 · SKIP=0 · DEGRADE=0**（能力齐备机）；MUT-C ⇒ **恰用例 13 FAIL**、其余 12 PASS、`npm test` rc≠0；MUT-D / MUT-E ⇒ 对应断言 FAIL；还原后全绿 + `md5` 前后一致。
- **观测**：`npm test` rc + 13 用例逐条状态 + 断言数（只增不减：**12/267→13/282**；口径订正：派发期写的 263/≥270 为旧快照，以 QA 实测 267 为基线）+ 三变异各自的 FAIL 断言编号。

## 三、范围 / 非范围

- **范围**
  1. 新增 `tests/t4/cases/13-close-guards.sh`：**6 条双侧断言**（①不可验证环境 ⇒ rc≠0；②同场景 stdout 不含「未运行（无需回收）」；③同场景 **stderr** 含「无法确认」+「不做静默 no-op」；④反向：名册可用且为空 + 无句柄 ⇒ rc=0 + stdout 含「未运行（无需回收）」；⑤`offline_verifiable` 三子句各一条（`NAO_TERMINAL=tmux` / `NAO_TERMINAL=foot` / `$TMUX` 在场）—— **极性口径：`tmux`/`screen`/`$TMUX` = 正向（可验证 ⇒ rc=0 + MARK）；`foot`（及 `ghostty`/`ptyxis`）= 负向（∉ {tmux,screen}，不构成可验证 ⇒ rc≠0、不含 MARK）**；⑥`--force` 现状锁定）。
  2. `tests/t4/run.sh`：`CASE_IDS`/`CASE_TITLES` 增 `"13"` + usage 文案 `<01-12>` → `<01-13>`（**必需**：该数组是显式枚举，不注册则用例永不执行 —— QA 指出的 PM 候选盲点）。
  3. 变异控编排与留痕：**MUT-C**（`if true`）· **MUT-D**（`if false`，过度矫正）· **MUT-E**（删 `NAO_TERMINAL` 子句，定义收窄）+ **单调性交叉**（MUT-C 下 ④ 仍绿）+ 还原 `md5` 证据。
  4. 文档同步：`tests/README.md` 用例表 +1 行（含能力依赖说明）· `docs/releases/v0.18.1.md`（PATCH）· `docs/tasks-state.md` ⑭ 收口。
- **非范围**（各带理由）
  - **不改 `.agents/scripts/nao-fleet.sh` 功能代码**：理由 本批定位「只补护栏」，改被测对象会混淆证据来源；其中 `:1676` 的 warn 文案「或用 `--force` 跳过闸门」与实现不符（`--force` 在末段不生效，QA 实测）⇒ 记台账新项 **⑯**，另批处理（是否顺带修见开工确认卡 Q2）。
  - **不并入 `cases/09`**：理由 09 是「别名解析 / 跨仓回收」契约（190+ 行），并入会让一个用例双契约、失败定位模糊；先例 = T510 新增 case 10 而非扩 05/08。
  - **不落一次性只读探针**：理由 无持续守护，正是 R2 的复发通道。
  - **不做 `/tmp/nao-t4.*` 夹具治理（⑮）**：理由 与本批目标无关，另批（本批会让该计数再 +1，已知）。
  - **不做 `nao-fleet.sh` 拆分（⑫后半）**：理由 未立项，待 arch 评审后另议。

## 四、用户场景

- 画像 A（本仓维护者）：改 `close` 的在线判定后只跑 `npm test`，13 号用例当即把「静默 no-op 被永久化」拦下。
- 画像 B（交付批次 QA）：可用 3 个单点变异自证「断言钉在判据与双侧极性上」，而非钉在实现巧合上。
- 画像 C（下游三仓维护者）：照抄「同名退出码 + 双侧极性 + 判据三子句」的护栏写法。
- 状态清单（护栏语义）：**成功** = 13/13 PASS · rc=0；**被测判据被短路** = 用例 13 FAIL 且 `npm test` rc≠0；**过度矫正**（恒失败）= ④ FAIL；**判据被收窄** = ⑤ FAIL；**缺 `tsx` 能力** = ④⑤ 记 `t4_degrade`（默认门禁仍绿、`test:t4:full` 可见地红）；**环境意外命中占用名** = 前置探测命中 ⇒ `t4_degrade` 跳过该组（不得假 FAIL）。

## 五、业务规则

- **BR1 接缝复用**：门禁接缝 = `npm test` rc=0（不新增接缝）。
- **BR2 用例必须登记**：新用例须写入 `run.sh` 的 `CASE_IDS`/`CASE_TITLES`（禁依赖 glob 的隐式发现）；未登记即视为未交付。
- **BR3 双侧极性**：**不可验证 ⇒ 非静默失败**；**真离线 ⇒ 静默 rc=0**；两侧必须同时断言，既不放宽也不过度矫正。
- **BR4 通道正确性**：`warn` 输出走 **stderr** ⇒ 断言 ③ 必须查 `T4_ERR`（照抄只查 `T4_OUT` 会得到恒假断言 —— 与 T522「空心断言」同类教训）；对应地 ② 只查 stdout。
- **BR5 判据钉死**：`offline_verifiable` 的三个子句（名册可用 / `$TMUX` / `NAO_TERMINAL=tmux|screen`）各至少一条断言，防「定义被悄悄收窄」。
- **BR6 hermetic 夹具**：目标一律用**派生名**（`close --task <唯一任务号> qa`），**禁 `close qa`** —— 本机测试进程自身标题即 `π - qa - <repo>`，裸名会命中调用者自己而落到 F1 拒绝分支（rc=1 但原因不同 ⇒ 断言 ③ 因错误原因失败）；保留 `TMUX_PANE`，靠唯一任务号保持隔离。夹具不留副本、跑后工作区干净。
- **BR7 能力缺失须诚实**：④⑤ 依赖 `tsx`（名册探针）⇒ 前置探测缺失时用 `t4_degrade`（默认门禁豁免、`test:t4:full` 计分），**不得**静默 PASS 或静默 SKIP。
- **BR8 变异必做且可还原**：MUT-C/D/E 均在临时副本或注入后立即 `git checkout --` 还原，附 `md5` 前后一致证据；断言单调性（MUT-C 下 ④ 仍绿）须给出。

## 六、NFRs

- **时长**：全量门禁仍为 ≈2min 量级（新用例为纯本地进程断言，不引入网络与真 tmux 操作，量级可忽略）。
- **可移植性**：①②③⑥ **环境无关**（空 `PI_CODING_AGENT_DIR` + `-u TMUX -u NAO_TERMINAL`）；④⑤ 需 `tsx`，缺失时按 BR7 降级。
- **网络**：不适用（纯本地断言，零网络调用）。
- **可诊断**：失败输出须指名断言编号与用例号；warn 原文保留（含「无法确认」「不做静默 no-op」）。
- **安全**：变异注入只碰 `.agents/scripts/nao-fleet.sh` 单点且立即还原（禁留副本、禁 push 变异态）；夹具仅临时目录。

## 七、AC

- **验证接缝（QA 已确认 2026-10-14）**：`npm test` rc=0（复用唯一机械门禁，接缝数不增）。QA 复核改定 = 采 C2 + **补 `run.sh` 注册三行**（PM 原候选遗漏）+ 断言改 6 条（原 5 条）+ `--force` 断言按实测订正。
- **AC1（主路径 · 接缝复核）**：Given 本批需求，When QA 复核接缝候选，Then 确认/改定并记录日期 —— **已完成 2026-10-14**（QA `done(full)`）。
- **AC2（主路径 · 用例真被执行）**：Given 新用例已交付，When 跑 `npm test`，Then 汇总出现 13 号用例且基线 **13/13 PASS · rc=0 · SKIP=0 · DEGRADE=0**（能力齐备机）；**负向**：把 `"13"` 从 `run.sh` 注册摘掉 ⇒ 用例消失/计数回 12（证明 BR2 是硬约束）。
- **AC3（业务规则 · 双侧极性）**：Given ①不可验证环境，When 跑 `close --task <唯一号> qa`，Then **rc≠0** 且 stdout 不含「未运行（无需回收）」且 **stderr** 含「无法确认」+「不做静默 no-op」；Given ②名册可用且为空 + 无句柄，When 同命令，Then **rc=0** 且 stdout 含「未运行（无需回收）」（BR3/BR4）。
- **AC4（设计一致性 · 判据三子句）**：Given `offline_verifiable` 的三子句，When 分别构造（`NAO_TERMINAL=tmux` / `NAO_TERMINAL=foot` / `$TMUX` 在场），Then 各自断言成立（BR5）。
- **AC5（异常 · 失败传播，本批核心）**：Given 基线绿，When 单点注入 `if true; then`（**MUT-C** = R2 原样），Then `npm test` **rc≠0** 且**恰用例 13 FAIL**、其余 12 PASS、失败断言含 ①②③；还原后 `git status --porcelain` 空、`md5` 一致、复跑全绿（BR8）。
- **AC6（边界 · 反向与收窄）**：Given **MUT-D**（`if false`，过度矫正），Then ④ FAIL（真离线场景不得被判失败）；Given **MUT-E**（删 `NAO_TERMINAL` 子句），Then ⑤ FAIL（定义不得被收窄）；Given MUT-C，Then ④ 仍绿（**单调性交叉**，两向极性互不掩盖）。
- **AC7（诚实性 · 能力与现状锁定）**：Given 缺 `tsx`，Then ④⑤ 走 `t4_degrade`（默认门禁绿、`test:t4:full` 红）不静默通过（BR7）；Given `--force`，Then 锁定现状 = **不改变本分支 rc 且仍不含「未运行（无需回收）」**（QA 实测 `--force` 只作用于闸门①/②，PRD 原预期已按实测订正）（BR4 同源原则）。
- **AC8（一致性闸门 · 文档同步）**：Given PRD 接缝/AC 与 QA 用例范围，When 比对，Then 一致（不一致即验收打回）；且 `tests/README.md` 用例表含 13 行（含 `tsx` 能力说明）、`docs/releases/v0.18.1.md` 已落盘、`docs/tasks-state.md` ⑭ 已收口。

## 八、上线闭环

- **版本**：**v0.18.1（PATCH）** —— 纯测试/护栏变更，包运行面与 0.18.0 无差异。
- **灰度**：不适用（本仓内部门禁）。
- **回滚**：revert 用例与注册三行并发下一 PATCH；已 push tag 不删。
- **npm 重发**：**不重发**（`package.json` 不变、`tests/` 不入包；版本漂移已在 release notes 记录）。
- **发布前置**：`npm run test:t4:full` **rc=0** —— ✅ 发布期实测（空载 · 合并后 main）：**rc=0 · 1m59s · SKIP=0 / DEGRADE=0 / NOTE=3**（O-1 提醒：连续跑批可能出现负载性 SKIP，发布判据须**空载**跑）。
- **监控**：不适用；唯一指标 = `npm test` rc + 13 用例逐条状态 + 断言数（只增不减）。

## 九、变更治理

- **流程**：降级批次分支 `nao/close-guard`（无 Issue，与 T518–T522 一致）→ PR → QA 独立只读复跑 + MUT-C/D/E → PM 验收 → RD `--squash` 合并（显式 `--subject`）→ PM 发 tag/Release → PRD 归档。
- **实现分工（同分支顺序写，禁并发）**：① **rd-infra** 落 `tests/t4/cases/13-close-guards.sh` + `run.sh` 注册三行 + `tests/README.md` + release notes → 回执；② **qa** 独立复跑 + 三变异 + 报告（`docs/reports/2026-10-14-T523-qa-verify.md`）→ `done(full)`。
- **架构评审闸门**：**跳过**（QA 判定无需 arch 介入：`offline_verifiable` 位置与语义清晰，本批是纯外部行为断言，无结构决策）—— 理由记入本 PRD，供回执核对。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-close-guard-coverage.md`（本文件；归档时登记 `docs/prds/README.md`）；运行时状态记 `docs/tasks-state.md`（⑭ 收口 + 新增 **⑯** `nao-fleet.sh:1676` 文案与实现不一致）。
- **待裁量项**：⑯ 新增（本批不修，见 §三）· ⑮⑫后半 维持不变。

## 附：RICE 与依据

- Reach 2（本仓维护者 + 交付批次 QA）· Impact 2（堵一条静默状态谎言通道）· Confidence 0.9（QA 已实测三种变异与双侧基线）· Effort 0.5（1 用例 + 3 行注册 + 文档 + 变异编排）⇒ **RICE ≈7.2**。
- 战略筛子：命中「机制护栏 + 单点判据可信度」→ 本批做；「文案订正 / 夹具治理 / 脚本拆分」被筛除（各自另批）。
