# PRD：`--force` 文案订正 + t4 夹具缓存生命周期自洽（遗留小项合并批）

- 状态：**已交付并发布（v0.18.2 · npm 已重发并核验）** · Owner：PM · 更新：2026-10-14
- **验收记录** = 2026-10-14 PM 验收**通过（AC1–AC8 全过）**：PR [#42](https://github.com/Nathan3303/nao-skills/pull/42) squash **`e83ced2`**（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 独立复跑 **GO（终）**（`check` rc=0 roles=6 files=46 · `npm test` rc=0 · 106.7s · **14/14 PASS · 断言 282→313** · SKIP=0/DEGRADE=0/NOTE=3 · 空载 `test:t4:full` rc=0）+ ⑯ 双向变异（各恰 2 条 FAIL）+ ⑮ 25+ 守卫探针 + 存量 129→0 · 验收评论见 PR #42
- **发布记录** = 2026-10-14 **v0.18.2（PATCH）已发布**：发布提交 `d56de97`（pin 升 0.18.2）· **tag `v0.18.2` + Release 已发**（**AC9 自证：`gh release view` name = `v0.18.2`**）· 发布前置 `test:t4:full` rc=0（空载 1m27s · SKIP=0/DEGRADE=0）· **npm 重发已核验**（用户执行 `npm publish`；`dist-tags.latest` = `0.18.2` + `dist.integrity` 与本地 tarball **逐字节一致**（`sha512-pXgAgzq…` · 129,985 B）；registry 由 `0.17.3` 直跳 `0.18.2`）。
- 开工确认卡（2026-10-14 · ask-me 用户拍板 5 项）：D1 范围 = **按 QA 定稿**（⑯ 删净子句 + `cases/13` 双向断言 · ⑮ S1 + mode 感知 + env 逃生口 + 三态文案 + `mktemp` 失败非 0 · 新增 `cases/14` · 存量 X2）· D2 npm = **发布时重发 0.18.2**（⑯ 在包内 ⇒ 用户执行 `npm publish`；registry 将从 0.17.3 直接跳 0.18.2）· D3 版本 = **v0.18.2（PATCH）** · D4 立项 = **降级 `nao/cache-warn-cleanup`**（无 Issue）· D5 存量 = **X2 一次性清理**（执行前查无在跑批次 + 前后计数留痕）
- 指针：上游 = 用户 2026-10-14 选定**台账待裁量项 ⑯ + ⑮ 合并小批**（⑯ 由 T523 QA 实测发现；⑮ 由 T522 QA R4 发现）· 成熟度判定 = 命中 `pm-to-spec.md` §一.4（用户明示范围 + 两项均有实测证据）· **QA 接缝复核** = 2026-10-14 `done(full)`（⑯ 采 **C1 扩 `cases/13` + 双向断言 + 删净 `--force` 子句**；⑮ 采 **S1**（trap + mode 感知 + env-only 逃生口）+ 新增 `cases/14-cache-lifecycle.sh`；存量 **X2 一次性清理**）
- 优先级：中低（一致性 + 卫生 · 低成本）· 战略筛子：命中「机制可信度 / 交付卫生」→ 做 · MoSCoW：Should · Kano：基本型 · RICE ≈6.0（附录）

## TL;DR（≤5 行）

- **做什么**：① 删净 `nao-fleet.sh` 末段那条与实现不符的 `--force` 提示，并加双向文案断言；② 把 t4 夹具缓存改成**自洽生命周期**（成功即清理 / 失败必保留并打印路径 / 用户传入目录永不删 / 只读命令不再建目录），新增用例 14 守护；③ 一次性清掉 `/tmp` 存量 129 个目录。
- **给谁**：本仓维护者与交付批次 QA（不再被误导、不再擦 /tmp）、下游三仓维护者（照抄缓存纪律）。
- **成功标准**：注入「文案回填 `--force`」⇒ 用例 13 FAIL；`--list`/`--preflight`/参数错误 **净增 0 个目录**；成功跑批后缓存目录消失、失败跑批保留且路径可查；`/tmp/nao-t4.*` 存量归 0；断言数只增不减（基线 **282**）。
- **不做什么**：**不让 `--force` 在该分支真正生效**（行为变更，会抹掉 T516/T523 的「不可验证 ⇒ 不静默」不变量，且需 arch）· 不改 usage 头的 `--force` 说明（与实现一致）· 不加 `--keep-cache` CLI 旗标（逃生口只用 env）· 不加常驻 `--clean-cache` 破坏性入口（存量走一次性动作）。

## 一、问题证据

- **⑯（文案与实现不符）**：`.agents/scripts/nao-fleet.sh:1676` warn 尾句「请用 intercom list 人工核对；确认已退出后忽略本提示，**或用 `--force` 跳过闸门**」，但该分支是「`offline_verifiable` 三子句全假 ⇒ 不可知」的兜底（`:1674-1678`），**不消费 `--force`** —— `--force` 只在闸门①（tasks-state 未推进，`:1613-1615`）与闸门②（在跑 turn，`:1696`）生效，解析见于 `:1821`。T523 用例 13 的 ⑥ 已实测锁定「`--force` 不改本分支 rc」。
  - 5 Whys：提示错 ← 复用了闸门①②的「逃生口」句式 ← 末段兜底分支后加、未复查 `--force` 在该路径的可用性 ← 无任何断言约束文案与实现的一致性 ← 「提示语属注释」的默认假设（T522/T523 才把「判据/接线须有护栏」立为口径）。
  - 可观察代价：使用者按提示加 `--force` 仍被拒绝 ⇒ 误判为「工具坏了」；或反向以为该分支已确认在线状态。
- **⑮（夹具缓存累积 + 早退建目录 + 空值隐患）**：`tests/t4/run.sh:68` **无条件** `mktemp -d "${TMPDIR:-/tmp}/nao-t4.XXXXXX"`（`lib.sh:22` 同型兜底），**无 `trap`、无收尾清理**，`:149` 无条件打印「缓存目录: …」。实测 `/tmp/nao-t4.*` 存量 **129** 个（最老 10-13，最新本日）。另两处现状缺陷：① `--list` / `--preflight` **只读命令也建目录**（纯累积）；② `mktemp` 失败时 `T4_CACHE_DIR=""` 会被后续 `mktemp -d "$T4_CACHE_DIR/fx.XXXXXX"` 变成 **`/fx.XXXXXX`**（根下路径）⇒ 以空值续跑而非明确失败。
  - 5 Whys：目录累积 ← 每次跑批独立 `mktemp` 且不回收 ← 早期把「保留现场供诊断」当默认（`case-<id>.log` 是失败诊断依据）← 未区分「成功」与「失败」两种需要的证据强度 ← 无任何生命周期契约与断言。
- 证据留痕：`docs/tasks-state.md` 待裁量项 ⑯/⑮（O-1 观察项同区）· `docs/reports/2026-10-14-T523-qa-verify.md`（⑯ 实测）· `docs/reports/2026-10-14-T522-qa-verify.md`（R4 存量）· 本轮 PM 实测（`ls -d /tmp/nao-t4.* | wc -l` = 129 · `npm pack --dry-run` 含 `.agents/scripts/nao-fleet.sh`）。

## 二、目标指标

- **北极星**：**提示语只说真话** + **缓存目录生命周期自洽**（既有量归零、且不再累积）。
- **预期**：① 回填 `--force` 文案 ⇒ 用例 13 FAIL；删整条 warn ⇒ 正向断言 FAIL；② `--list` / `--preflight` / 参数错误在私有 `TMPDIR` 下 **净增 0**；③ 成功跑批 ⇒ 自建目录消失；失败跑批（含 `T4_REQUIRE_FULL=1` 判 FAIL）⇒ 目录保留且打印可读路径；④ 用户传入 `T4_CACHE_DIR` ⇒ **永不删**；⑤ 存量 129 → **0**；⑥ 断言数只增不减（基线 **282**）。
- **观测**：`npm test` rc + 用例 13/14 逐条断言 + 私有 `TMPDIR` 净增/净减计数 + `/tmp` 前后值 + 变异/守卫探针结论。

## 三、范围 / 非范围

- **范围**
  1. **⑯ 文案订正**：`.agents/scripts/nao-fleet.sh:1676` **删净**「或用 `--force` 跳过闸门」子句（保留「请用 intercom list 人工核对；确认已退出后忽略本提示」）。
  2. **⑯ 护栏**：扩 `tests/t4/cases/13-close-guards.sh` —— 复用既有两次实跑捕获的 `T4_OUT`/`T4_ERR`（零新增子进程），**双向断言**：负 = 输出（stdout+stderr）**不含 `--force`**；正 = stderr **仍含「人工核对」/「确认已退出」**（防「整段 warn 被懒删」）。
  3. **⑮ 实现（单点）**：`tests/t4/lib.sh` 新增 `t4_cache_cleanup`（**唯一实现点**，`run.sh` 复用不复制）+ 装 `EXIT` trap；`T4_CACHE_OWNED`（**不导出**）· `T4_CACHE_PARENT`（创建时捕获 `${TMPDIR:-/tmp}`，禁硬编码 `/tmp`）· env-only 逃生口 `T4_KEEP_CACHE=1`。
  4. **⑮ 语义**：**成功（rc=0）且自建 ⇒ 清理；rc≠0 ⇒ 保留 + 打印路径；用户传入 `T4_CACHE_DIR` ⇒ 永不删**；`rm` 失败 ⇒ 仅 warn、**不改 rc**；`mktemp` 失败 ⇒ **明确非 0 退出**（堵空值续跑）。
  5. **⑮ mode 感知**：`run.sh` 把默认 `mktemp` **下移到 `--list`/`--preflight` 早退之后、run 循环之前**（参数错误路径已在更早处早退）。
  6. **⑮ 打印与实况一致（三态，口径按实现订正 · D-1）**：自建且成功 →「（已清理）」· 自建且 `T4_KEEP_CACHE=1` →「（已保留（T4_KEEP_CACHE=1））」· 自建且 `rc≠0` →「（已保留：失败证据）」· 用户传入 →「（用户提供 · 不删）」；断言只钉「打印 disposition 与 `[ -d ]` 实况一致」，**不吃死字符串**。
  7. **新增 `tests/t4/cases/14-cache-lifecycle.sh`**（≥12 条断言，全 hermetic：私有 `TMPDIR`，不依赖 tmux/tsx/网络）+ `run.sh` 注册 `"14"` / usage `<01-13>` → `<01-14>` + `tests/README.md` 用例表与缓存纪律说明。
  8. **存量 129 一次性清理（X2）**：`pgrep -af 'tests/t4/run.sh'` 确认无在跑批次 → 记录前值 → `rm -rf /tmp/nao-t4.*`（**限定一层、限定前缀，禁 `find -delete`**）→ 记录后值 0 + 命令 + 时间戳（PR 评论/回执留痕）。
  9. **文档同步**：`docs/releases/v0.18.2.md`（PATCH）· `tests/README.md` 缓存纪律段 · `docs/tasks-state.md` ⑯⑮ 收口。
- **非范围**（各带理由）
  - **不让 `--force` 在该分支生效**：理由 该分支拒绝的原因是**不可知**（三子句全假），`--force` 无法创造知识；放行 = 对「可能仍在线」的会话回报 rc=0，正好抹掉 T516 AC3 / T523 的核心不变量「不可验证 ⇒ 不静默 no-op」（QA 判定更差，且需 arch）。
  - **不改 usage 头 `--force` 说明（`:12-16`）**：理由 它与实现一致（`--force` 确实作用于闸门①②），不得顺手清（PRD 明列以防误删）。
  - **不加 `--keep-cache` CLI 旗标**：理由 逃生口与 `T4_ALLOW_MISSING`/`T4_REQUIRE_FULL` 同族（env 单开关、单一消费点、对 `--case` 与单跑用例同时生效）；旗标需新增解析 + 文档 + 用例，收益低。
  - **不加常驻 `--clean-cache` 破坏性入口（X1 否决）**：理由 模式匹配删除无法排除**并发活批**（另一会话正在跑批时被删 ⇒ 随机 FAIL + 证据丢失）；一次性存量不值得引入常驻破坏面（QA 给出 X1 的完整安全边界亦不建议）。
  - **不动其它 `--force` 文案点**（`:1609`/`:1615`/`:1696`）：理由 各自分支语义正确，改则扩大回归面。
  - **不重做 `tests/README.md` 陈旧「最近一次跑批」行**：理由 T522 已清（本轮复核 `grep` 0 命中），非问题。
  - **不做脚本拆分（⑫后半）**：理由 未立项，待 arch 评审后另议。

## 四、用户场景

- 画像 A（本仓维护者）：`close` 被拒时按提示读到的每条建议都真实可用；跑完 `npm test` 不再留下新目录。
- 画像 B（交付批次 QA）：失败跑批时缓存目录**一定**在，且汇总打印的路径可直达 `case-<id>.log`；成功跑批不留垃圾。
- 画像 C（下游三仓维护者）：照抄「成功清理 / 失败保留 / 用户目录永不删」三态，避免自家套件擦 /tmp。
- 状态清单（缓存生命周期）：**成功** = 自建 ⇒ 清理 + 打印「已清理」；**失败** = 自建 ⇒ 保留 + 打印「已保留：失败证据」；**用户传入** = 不删 + 打印「用户提供 · 不删」；**逃生口** = `T4_KEEP_CACHE=1` ⇒ 恒保留；**只读命令** = 不建目录；**`mktemp` 失败** = 明确非 0 退出。

## 五、业务规则

- **BR1 接缝复用**：门禁接缝 = `npm test` rc=0（不新增接缝）。
- **BR2 文案只写真话**：提示语中的每个动作建议必须在**该分支真的可用**；负向断言「输出不含 `--force`」+ 正向断言「仍含人工核对指引」双向钉住（只加负向会放任整段被删）。
- **BR3 归属语义（OWNED）**：只有「本进程自己 `mktemp` 成功」的目录可被删；`T4_CACHE_OWNED` 仅在自建时置 1 且**不导出**（`lib.sh` 侧兜底：`T4_CACHE_DIR` 非空 ⇒ 强制 `OWNED=0`），防子进程先于父进程删掉本批缓存。
- **BR4 删除守卫**：`rm -rf -- "$dir"` 前置全过才执行 —— 非空 · 前缀匹配 `"$T4_CACHE_PARENT"/nao-t4.*`（前缀取自创建时捕获的 `${TMPDIR:-/tmp}`，**禁硬编码 `/tmp`**）· 是目录且**非软链** · 非 `/` · 仅删本进程 `mktemp` 返回值（**禁一切 glob 删除**）。
- **BR5 rc 保真**：清理在 `EXIT` trap 内以 `local rc=$?; …; return $rc` 实现，**禁 `exit`**（不得吞/改退出码）。
- **BR6 打印与磁盘实况一致**：汇总打印的 disposition 必须与 `[ -d ]` 实况相符（三态文案，见 §三.6）。
- **BR7 失败一律保留**：`rc≠0`（FAIL/BLOCKED/MISSING/NOT_RUN，**含 `T4_REQUIRE_FULL=1` 因 SKIP/DEGRADE 判 FAIL**）⇒ 保留目录；失败证据优先于卫生。
- **BR8 早退零净增**：`--list` / `--preflight` / 参数错误（`--case` 缺值 / 无匹配 / 裸位置参数）在私有 `TMPDIR` 下**净增 0 个目录**。
- **BR9 失败要响**：`mktemp` 建目录失败 ⇒ 明确非 0 退出（**禁**空值续跑成 `/fx.XXXXXX`）；`rm` 失败 ⇒ warn 但不改 rc（否则静默留下目录 = 换个方式累积）。
- **BR10 单点实现 + 已知 trap 洞**：清理逻辑只在 `lib.sh` 定义一处（`run.sh` 复用），加一条静态契约断言钉住；`tests/t4/cases/09-alias-guard.sh:20` 自带 `trap cleanup_c09 EXIT`（会覆盖）⇒ 在其 cleanup 内串一行 `t4_cache_cleanup` 并注明「仅影响单跑 09（经 `run.sh` 时 OWNED=0，无害）」。

## 六、NFRs

- **时长**：与现状同量级（用例 14 为纯本地文件生命周期断言，无网络/无 tmux/无 T2 依赖）。
- **可移植性**：必须支持自定义 `TMPDIR`（前缀守卫取自运行时捕获值）；不得假设 `/tmp` 固定存在。
- **网络**：不适用（零网络）。
- **可诊断**：失败跑批保留目录并打印可读路径；清理动作不静默（失败会 warn）。
- **安全**：删除面 = 单目录 + 五道守卫（BR3/BR4）；探针只在私有 `TMPDIR` 下操作；本批一次性存量清理仅限 `/tmp/nao-t4.*` 一层且执行前确认无在跑批次。

## 七、AC

- **验证接缝（QA 已确认 2026-10-14）**：`npm test` rc=0（复用唯一机械门禁，接缝数不增）。QA 复核改定 = ⑯ 采 C1（扩 `cases/13`，双向断言、复用既有实跑）+ ⑮ 采 S1（trap + mode 感知 + **env-only** 逃生口）+ 新增 `cases/14` 挂 `CASE_IDS`；存量采 **X2**；**两者均不需 arch**。
- **AC1（主路径 · 接缝复核）**：Given 本批需求，When QA 复核候选，Then 确认/改定并记录日期 —— **已完成 2026-10-14**（QA `done(full)`）。
- **AC2（主路径 · 文案与实现一致）**：Given 改后 `nao-fleet.sh`，When 走「不可验证」分支，Then 输出（stdout+stderr）**不含 `--force`** 且 stderr 仍含「人工核对」/「确认已退出」；**负控**：把 `--force` 子句回填 ⇒ 用例 13 **FAIL**；删整条 warn ⇒ 正向断言 **FAIL**（BR2）。
- **AC3（主路径 · 用例注册）**：Given 新用例 14，When 跑 `npm test`，Then 13 与 14 均在册且基线全 PASS；**负控**：把 `"14"` 从 `CASE_IDS` 摘掉 ⇒ 不执行（BR/流程同 T523 BR2）。
- **AC4（业务规则 · 生命周期三态）**：Given 自建缓存目录，When 跑批 `rc=0`，Then 目录**消失** + 打印「已清理」；When 失败（含 `T4_REQUIRE_FULL=1` 判 FAIL），Then 目录**保留** + 打印可读路径；Given 用户显式传入 `T4_CACHE_DIR`，When 跑批，Then 目录**存在**且含 `case-<id>.log`（BR3/BR6/BR7）。
- **AC5（边界 · 逃生口与守卫）**：Given `T4_KEEP_CACHE=1`，Then 成功/失败两情形目录**恒在**（BR/§三.4）；**守卫负控**：OWNED=1 但路径不匹配 `nao-t4.*` 前缀 ⇒ **不删**；目录被替换为软链 ⇒ **不删**；`export T4_CACHE_OWNED=1` 经 `lib.sh` ⇒ 强制不删（BR3/BR4）。
- **AC6（异常 · 早退与失败要响）**：Given 私有 `TMPDIR`，When 分别跑 `--list` / `--preflight` / `--case 99` / 裸位置参数，Then 目录**净增 0**；When `mktemp` 建目录失败（桩）⇒ **非 0 退出**；When `rm` 失败（桩）⇒ rc **不变** + warn（BR8/BR9）。
- **AC7（设计一致性 · rc 保真与单点）**：Given 用例以 rc=1 退出，Then 进程 rc **仍为 1**（trap 不吞/不改）；且清理逻辑在 `lib.sh` 仅一处（静态契约断言），`cases/09` 的 `cleanup_c09` 已串 `t4_cache_cleanup`（BR5/BR10）。
- **AC8（收尾 · 存量与文档）**：Given 执行前确认无在跑批次，When 一次性清理，Then `/tmp/nao-t4.*` 由 **129 → 0**（前后计数 + 命令 + 时间戳留痕）；且 `tests/README.md` 缓存纪律已同步、`docs/releases/v0.18.2.md` 已落盘、`docs/tasks-state.md` ⑯⑮ 已收口；断言数**只增不减**（基线 282）。

## 八、上线闭环

- **版本**：**v0.18.2（PATCH）** —— ⑯ 改到**入包文件**（`package.json.files` 含 `.agents/`，`npm pack --dry-run` 实测含 `.agents/scripts/nao-fleet.sh`）⇒ **消费者要拿到新文案必须重发 npm**（与 T523「不重发」的前提不同）。
- **npm 重发**：**已拍板（用户 2026-10-14）= 发布时重发 `0.18.2`** —— 理由 ⑯ 改到入包文件（`files` 含 `.agents/`）；由**用户执行** `npm publish`，成功判据 = 直连 registry 实测 `dist-tags.latest` + `dist.integrity` 与本地 `npm pack` tarball 逐字节一致（`PUT 202` 不作判据）；registry 由 `0.17.3` 直接跳 `0.18.2`（同时携带 v0.18.0/0.18.1 的包内变化），须记入 release notes。
- **回滚**：revert 文案 + 清理实现并发下一 PATCH；已 push tag 不删。
- **发布前置**：`npm run test:t4:full` **rc=0**（**空载**跑，O-1 观察项）。
- **监控**：不适用；指标 = `npm test` rc + 用例 13/14 状态 + 断言数 + `/tmp/nao-t4.*` 计数。

## 九、变更治理

- **流程**：降级批次分支 `nao/cache-warn-cleanup`（无 Issue）→ PR → QA 独立复跑 + 变异/守卫探针 → PM 验收 → RD `--squash` 合并（显式 `--subject` + `--match-head-commit`）→ PM 发 tag/Release（按 §八 决定是否重发 npm）→ PRD 归档。
- **实现分工（同分支顺序写，禁并发）**：① **rd-infra** 落 `nao-fleet.sh` 文案 + `lib.sh`/`run.sh` 缓存生命周期 + `cases/13` 断言扩展 + 新增 `cases/14` + `tests/README.md` + `docs/releases/v0.18.2.md` + **存量 X2 一次性清理（按 §三.8 纪律留痕）** → 回执；② **qa** 独立复跑 + 变异（文案回填 / 结构懒删）+ 守卫探针（OWNED/前缀/软链/rc 保真/早退净增）+ 报告（`docs/reports/2026-10-14-T524-qa-verify.md`）→ `done(full)`。
- **架构评审闸门**：**跳过**（QA 判定：⑯ 语义已由 T516 arch 定型且本批不动行为、⑮ 只在 `tests/` 内且不入包、无被测机制耦合；唯一会触发 arch 的分叉「让 `--force` 真生效」已被排除）。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-cache-warn-cleanup.md`（本文件；归档时登记 `docs/prds/README.md`）；运行时状态记 `docs/tasks-state.md`（⑯、⑮ 收口）。
- **交付记录**：PR [#42](https://github.com/Nathan3303/nao-skills/pull/42) squash **`e83ced2`**（main 恰 1 条 · 无 `wip()` · 分支删净）· RD 4 条 + QA 2 条 `wip(T524)` 提交（9 文件 / +403 −18）· QA 报告 `docs/reports/2026-10-14-T524-qa-verify.md`（79 行）· 无 ADR（D5 拍板跳过 arch）· 未 bump 版本（发布节点 PM 执行）。
- **本批残差（已记录）**：**R-4** 用例 14 的 `function` 形态为前缀匹配 ⇒ 只会**误红**不会误绿（非阻塞，报告 §八）· **D-1** 本 PRD §三.6 措辞已按实现订正 · **O-1** 发布判据须**空载**跑 `test:t4:full`。
- **待裁量项**：本批关闭 ⑯、⑮；维持 ⑫后半（脚本拆分）· ①–⑨ 更早遗留 · O-1 观察项。

## 附：RICE 与依据

- Reach 2（本仓维护者 + 交付批次 QA）· Impact 2（提示可信 + /tmp 不再累积）· Confidence 0.9（两处证据均已实测，QA 已给完整守卫/探针清单）· Effort 0.6（1 行文案 + 生命周期实现 + 2 处断言/新用例 + 一次性清理 + 文档）⇒ **RICE ≈6.0**。
- 战略筛子：命中「机制可信度 + 交付卫生」→ 本批做；「`--force` 行为变更 / 常驻清理入口 / 脚本拆分」被筛除（前两项已论证更差或风险倒挂，第三项未立项）。
