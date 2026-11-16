# #132 backlog sweep · E2 两条守卫（含 QA P3 返修）—— 交付报告（rd-infra）

- 状态：待 PM 验收（QA = GO，P3-1/P3-2/P3-3 已全部返修）· 更新：2026-11-16 · Owner：rd-infra
- 指针：Issue [#132](https://github.com/Nathan3303/nao-skills/issues/132)（E2-1 / E2-2）· 分支 `nao/M20261116-backlog-sweep`（PM 已建并 push，起点 HEAD `ff630c7`）· 台账部分（E1）由 PM 完成，本报告只覆盖 E2

## TL;DR

- **E2-1（pi 阈值一致性断言）**：文档里的版本号**一个没删**（用户要看到门槛），改为「文档声明的 `pi` 下限必须 == 脚本单源 `MIN_PI_VERSION`，漂移即红并点名 `文件:行`」。两条判据：① 下限声明取值比对 ② **完备性**（现行文档里任何「pi … x.y.z」提及都必须归类：或本身是下限声明，或该行带「截至」历史时点标注）。
- **E2-2（`NAO_STASH_ROOT` helper 守卫）**：`t4_run_shim` / `be_run_fleet` 两个单点的 `-u NAO_STASH_ROOT` 现在有断言守卫。判据 = **warn 数差**（注入根那次与外层非仓根基线的 `warn=N` 相等）+ 直连 `-v` 旁证恰 1 条 stash warn + 删 `-u` 后恰 +1（反空转）+ 解耦夹具（另有卡预算 warn 时差值仍 0）。
- **QA P3 三条全部返修**：`P3-1` 宿主 `NAO_SKILLS` 渗进夹具（同族真漏，11 处代码点统一清 + 正/负控 + 静态审计）；`P3-2` E2-2 判据改「warn 数差」（不再断言「无任何 `warn=`」）；`P3-3` 计数阈值留裕度（≥6 文件 / ≥9 处 / ≥40 扫描面）+ 自助说明补「未跟踪文件不扫」。
- **门禁**：`check` rc=0 ×2 输出**逐字一致**（`files=54` 不变）· `cases/06` PASS（断言 **284 → 324**，含 QA 场景 `NAO_SKILLS=$PWD` 复跑同样 324/0）· `npm test` rc=0 · golden 未破（`P2④` 旧 md5 断言仍 PASS）· 真仓 stash 0。
- **判据订正（实测）**：PM 给的行号/口径有 2 处不成立 ——
  1. 扫描面不是 4 个文件：实测 **7 个文件 / 10 行 / 11 处**（多了 `.agents/skills/nao-fleet/SKILL.md:32`、`.agents/skills/pm-operations.md:14`、`docs/ARCHITECTURE.md:45`；**订正**：本报告初版写「8 文件 / 9 行」是我笔误，PM 复算的 7 文件为准，三个数的可复算命令见 §E2-1「计数证据」）；
  2. PM 给的正则形态 `pi ≥?\s*x.y.z` **抓不到** `docs/INSTALL.md` 的三处（`:12` 是 `pi（≥ 1.4.0）`、`:22` 是 `需 ≥ 1.4.0`、`:34` 是 `pi 版本低于 1.4.0`）⇒ 扫描器改用「`pi` … `≥`/`低于`」两条形态 + 完备性兜底。
- 影响：纯测试侧新增断言，零生产代码/零文档改动、不发版。

## 变更清单（3 测试/说明 + 本报告）

- `tests/t4/cases/06-contract-guards.sh`：新增 **E2-1** 组（pi 阈值文档面一致性）· **E2-2** 组（两 helper 的 `-u NAO_STASH_ROOT` 守卫）· **E2-3** 组（夹具不得读宿主 `NAO_SKILLS`，断言落在 E1 段）；E1/E2 段全部 `check` 调用点清 `NAO_SKILLS`。
- `tests/README.md`：用例 06 段补 E2-1 完备性判据的**自助说明**（判据 + 两种改法 + 「扫描面 = `git ls-files '*.md'` ⇒ 未跟踪文件不扫」）。
- `docs/reports/132-sweep.md`：本报告。
- 未改：`.agents/scripts/nao-fleet.sh`（`MIN_PI_VERSION` 仍 `1.4.0`，脚本内该字面量仍恰 1 处）· `tests/t4/lib.sh` / `lib-backend.sh`（两个 `-u` 硬化本就存在，本批只补守卫）· 任何文档的版本号。

## E2-1 设计与判据（`cases/06` · E2-1①–④）

**为什么不是「清空文档数字」**：用户的可见门槛必须在文档里（README 前置环境 / INSTALL 安装校验 / AGENTS 约束）。删数字等于把门槛藏进脚本，用户看不到；保留数字又必然出现「脚本改了文档没改」的双源漂移 ⇒ 用断言把双源钉成「同一事实」。

**单源与扫描面**

- 基准 = 被测根下 `.agents/scripts/nao-fleet.sh` 的 `MIN_PI_VERSION`（当前 `1.4.0`）。取的是**根下**脚本而不是仓库常量：这样负控可以在副本里改常量而不碰真仓。
- 扫描面是 **fail-closed** 的，不是白名单文件清单：`git ls-files -- '*.md'` 减去三类**历史时点**目录/文件 —— `docs/{adr,prds,releases,reports,notes,designs,research}/`（as-of 记录，改写即伪造历史）· `docs/tasks-*.md`（台账/归档视图）· `tests/`（夹具与负控样本，故意构造漂移）。新增文档会自动进入扫描面（无需维护清单）；要豁免只能落进上述**类**。代价 = **未跟踪文件不扫**（新文档须 `git add` 后才纳入判据，已在 `tests/README.md` 写明）。

**两条判据**

- ① **声明式下限**：正则 `pi[^0-9]*(≥|>=|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+` 逐处抽取版本，必须 == 单源；不等则打印 `<文件>:<行> 声明 <版本> ≠ 单源 <MIN_PI_VERSION>`。形态覆盖 `pi ≥ 1.4.0` / `pi ≥1.4.0` / `pi（≥ 1.4.0）` / `需 ≥ 1.4.0` / `pi 版本低于 1.4.0`。
- ② **完备性**：同一批文件里凡出现「pi … x.y.z」的行，必须**已被归类** —— 要么其 `文件:行` 已在 ① 的命中集里，要么该行带 **「截至」**（历史时点标注）。否则打印 `<文件>:<行> 未归类：既非下限声明（≥/低于），也无「截至」历史时点标注`。这条是防「换一种写法写漂移而 ① 抓不到」的兜底，也是 `codegraph.md:21` 的豁免机制。

**`codegraph.md:21` 的豁免口径**：不按文件名硬编码。该行是「插件不供 system prompt 指引（**截至** pi 1.4.0 / pi-codegraph 0.1.0）」——`截至 pi 1.4.0` 是**历史时点事实**（版本戳），不是运行时门槛，因此既不含 `≥`/`低于`（① 天然不命中），也有「截至」标注（② 放行）。机制承重由 E2-1④ 证明：**把副本里那个「截至」摘掉** ⇒ 同一行立刻变「未归类」必红。

**现仓覆盖（实测 7 文件 / 10 行 / 11 处，全部 == `1.4.0`**；`intercom-protocol.md:36` 一行含 2 处 ⇒ 行数 ≠ 处数）

- `README.md:28`（`pi ≥ 1.4.0`）
- `AGENTS.md:18`、`AGENTS.md:33`
- `.agents/common/intercom-protocol.md:36`（同一行两处）
- `.agents/skills/nao-fleet/SKILL.md:32`
- `.agents/skills/pm-operations.md:14`
- `docs/ARCHITECTURE.md:45`
- `docs/INSTALL.md:12`（`pi（≥ 1.4.0）`）、`:22`（`需 ≥ 1.4.0`）、`:34`（`pi 版本低于 1.4.0`）

断言形态（计数只作「扫描器没坏」的防线，**完整性交给 ②**）：

- 现仓全绿（漂移 0 · 未归类 0）
- **扫描面**非空：现行 `*.md` **≥ 40** 个（防 `git ls-files` 取不到而无对象空转）
- 声明**处数** **≥ 9**（实测 11）· 声明**文件数** **≥ 6**（实测 7）
  - 为什么留裕度（QA P3-3b）：贴脸阈值（原写 `≥11 处`）在「合并 `intercom:36` 的重复声明 / 删一篇文档 / 改一处措辞」时会以**错误原因**红；文档面完整性本来就由 ② 完备性判据逐处兜住，不需要靠计数绊线。
- `codegraph.md` 不进声明面的显式断言

**计数证据（`文件:行:处` 三个数都可复算，口径 = `git ls-files -- '*.md'` 减历史类；正则如上）**

```bash
PRUNE='^(docs/(adr|prds|releases|reports|notes|designs|research)/|docs/tasks-[^/]*$|tests/)'
FILES="$(git ls-files -- '*.md' | grep -vE "$PRUNE")"
printf '%s\n' "$FILES" | xargs grep -nE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+'   # 逐条命中（10 行）
printf '%s\n' "$FILES" | xargs grep -lE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+' | wc -l   # 7 文件
printf '%s\n' "$FILES" | xargs grep -nE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+' | wc -l   # 10 行
printf '%s\n' "$FILES" | xargs grep -oE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+' | wc -l   # 11 处
```

- 差异来源：`intercom-protocol.md:36` 的一行里出现 2 次（`pi ≥ 1.4.0` 在「ADR 已被取代…语义不变」与「任一端都要求」各一次）⇒ **10 行 / 11 处**。用例里的 `≥ 9` 是**处数**下限（不是行数），与本节口径一致。

**先红后绿（全部在 `$T4_CACHE_DIR` 的副本里，真仓零触碰）**

- ② **只改脚本常量**（副本 `MIN_PI_VERSION="9.9.9"`，文档不动）⇒ 必红并点名：`README.md:28 声明 1.4.0 ≠ 单源 9.9.9`、`docs/INSTALL.md:12 声明 1.4.0 ≠ 单源 9.9.9`（同轮多处，不只报首个）。
- ③ **只改某文档**（副本 `README.md:28` → `pi ≥ 9.9.9`，脚本不动）⇒ `README.md:28 声明 9.9.9 ≠ 单源 1.4.0` 必红（两个方向都能抓）。
- ④ **摘掉历史时点标注**（副本 `codegraph.md` 去「截至」）⇒ `codegraph.md:21 未归类` 必红（证明豁免靠标注，不靠文件名）。

**开发期真实抓到的两个坑（留证：断言不是摆设）**

- `awk -v exp=…` 与 gawk 内置函数 `exp` 撞名 ⇒ gawk 直接 fatal、比对结果为空（假绿面）。是本组的②③断言把它打红，改名 `want` 后转绿 —— 这条正好证明「① 现仓全绿」单独存在时会空转。
- 完备性首版把 `README.md:66` 的 `pi install --local npm:@0.21.3` 判成未归类（那是**包版本 pin**，不是 pi 自身门槛）⇒ 正则排除前导 `@`（`pi[^0-9@]*x.y.z`）；口径已写进用例注释。

## E2-2 设计与判据（`cases/06` · E2-2①–⑤）

**缺口复述**：`NAO_STASH_ROOT` 的宿主泄漏硬化（#126 P3④）落在两个 helper 单点上 —— `tests/t4/lib.sh:639`（`t4_run_shim`）与 `tests/t4/lib-backend.sh:738-740`（`be_run_fleet` 的 `envs` 数组）。硬化只存在于文本里，**谁删掉都没有用例会红**。

**落点选择**：放 `cases/06` 而不是台账里点名的 `cases/34`。理由 —— 本组验的是**测试基座**（helper）不涉及端前提/闸门语义，与紧邻的 D2「helper 单点清理清单（`HERDR_*` 单源）」同主题；且 06 已有 `C6_GIT` 临时仓夹具（P2-1 段建的 `git init` 仓），无需新开仓、无跨用例耦合。

**判据（QA P3-2 后改「warn 数差」）**：helper 跑的是**摘要模式**（`t4_run_shim` 固定 `check`，不带 `-v`）⇒ 输出里只有 `warn=N` 汇总数、没有 `  ! ` 明细。原先断言「无任何 `warn=`」会把**无关 warn**（卡预算 / codegraph）一起算进去 ⇒ 垫卡夹具 + 注入根时假红（与 #126 P2-1 同族）。现在四条腿：

- ① **直连旁证**（`-v`）：注入根 + `NAO_STASH_WARN_HOURS=0` ⇒ 恰 1 条 `^  ! git stash` 且点名滞留消息（闸门活着、根注入本来生效）。
- ② **经 helper**：`warn=N(注入根)` **==** `warn=N(非仓根基线)` ⇒ 注入根被 `-u` 清掉（差值 0；其它 warn 两次都在，自然抵消）。
- ③ **反空转**：副本删掉 helper 的 `-u NAO_STASH_ROOT` ⇒ 注入根那次 **恰 +1**（基线 0 ⇒ 1）。
- ④ **解耦自证**：`.agents` 副本 + 把最大卡垫到 `CARD_MAX+1` ⇒ 该夹具直连 `-v` 先看到 `! product-manager.md（超阈值…）`（**非 stash** warn），再走 helper ⇒ 基线与注入根 **warn 数仍相等**（判据不被无关 warn 带红/带绿）。
- ⑤ 静态定位：两个 helper 各恰 1 处 `-u NAO_STASH_ROOT`。

**夹具纪律**：stash 只造在 `$T4_CACHE_DIR/c6-git<pid>`（P2-1 段 `git init` 的临时仓）；`NAO_STASH_WARN_HOURS=0`（= 立即）让判据与时钟解耦。真实仓库全程 `git stash list` = **0**（门禁后复核），worktree = 1。

## E2-3（QA P3-1 返修）：夹具不得读宿主 `NAO_SKILLS`

**现象（QA 实测 · 我复现）**：`NAO_SKILLS=$PWD bash tests/t4/run.sh --case 06` ⇒ **319 PASS / 3 FAIL**（`28b5d44` 同现象）。根因 = `nao-fleet.sh:125 SKILLS_DIR="${NAO_SKILLS:-<脚本>/../..}"`：宿主导出的包根**盖掉**「夹具根」⇒ 夹具 `check` 去读真仓的 `.agents`（卡预算 / 人数 / warn 全错）。与 E2-2 刚修的 `NAO_STASH_ROOT` **同族**（宿主 env 渗进夹具）。

**修法（11 处代码点；其中 3 处是共用 env 结构，按使用次数计 = `B1_ENV` 6 次 · `c6_check` 4 次 · `E1_ENV` 3 次，其余 8 处各 1 次）**：`cases/06` 内**每处**脚本调用都清 `NAO_SKILLS` ——

- 直连 8 处：`AC6` 真仓 `check` · `lab_check`（pi 版本活体夹具）· 显式 `=tmux` golden `check` · `c6_check`（P2-1 双向组，4 次）· 未设探针 · 空串探针 · `E1_REAL_OUT` · E2-2 的两处直连旁证。
- 共用结构 3 处：`B1_ENV`（herdr 模式 `check`/`ensure`/`close`/`session-start` 共用 6 次）· `E1_ENV`（E1 夹具 + 变异副本 3 次）· `E2_ENV` 调用侧用显式 `NAO_SKILLS=<夹具根>`（夹具自洽，比清空更确定）。

**三层验证**：

- **正控**：宿主 env 给 `NAO_SKILLS=<真仓>`，`E1_ENV` 的 `-u` 盖掉它 ⇒ 仍报夹具垫过的行数（`最大 product-manager.md 201 行`）。
- **负控镜像**：同一夹具、同一制品，只把 `-u NAO_SKILLS` 拿掉（`E1_ENV_LEAK`）⇒ 读到真仓 ⇒ 报不出夹具行数；且正负控输出**必不同**（否则「清了但没用」也会绿）。
- **静态审计**：`c6_check_sites_without_skills` 扫本用例每处 `nao-fleet.sh check`，要求同一代码块（向上 40 行）内出现 `NAO_SKILLS`；附一条负控（无菌样本必被点名）+ 一条正控（块内有 `NAO_SKILLS` ⇒ 放过）。

**结果**：QA 场景 `NAO_SKILLS=$PWD … --case 06` ⇒ **324 PASS / 0 FAIL**（修前 319/3）。

## QA 复核（GO · 0 P1/P2 · 3 P3 全裁修）

- **P3-1（真漏 · 已修）**：见 §E2-3。
- **P3-2（必修 · 防假红 · 已修）**：见 §E2-2「判据（warn 数差）」+ ④ 解耦自证。
- **P3-3(b)（必修 · 写死数字同类 · 已修）**：`≥11 处` → **≥9 处**、去掉逐文件贴脸覆盖 → **≥6 文件**、`≥40` 扫描面保留；完整性交给 E2-1② 完备性判据（每处提及必须归类）。
- **P3-3(a)（一行文档 · 已修）**：`tests/README.md` 自助说明补「扫描面 = `git ls-files '*.md'` ⇒ **未跟踪文件不扫**（新文档先 `git add` 才会被纳入判据）」。
- **P3-3(c)（只记录 · 不改）**：完备性正则会把「`pi-subagents 0.x`」这类**别的包的版本**判成未归类（现仓 0 命中，因为 `.agents/skills/*` 里没有这种写法）。若将来写进现行文档，处置同样是二选一：改写成门槛（`≥`）或加「截至」标注 —— 这正是 E2-1④ 演练的机制，故**不**为它开特例正则（开了就多一条需要维护的形态清单）。

## 门禁（本机实测 · HEAD = 本批工作树）

- `bash .agents/scripts/nao-fleet.sh check` ⇒ rc=0 **×2 输出 `diff` 空**（`check: OK · roles=7 · files=54 · layout=main-row2`；`files` 不变 —— 只加测试断言与一行说明）。
- `bash tests/t4/run.sh --case 06` ⇒ **324 PASS / 0 FAIL**（基线 284 ⇒ 本批 **+40** = E2-1 15 + E2-2 18 + P3-1 面 6 + 既有 1 条环境相关条件断言）；`NAO_SKILLS=$PWD` 复跑同样 **324 / 0**。baseline 对照 = 同仓 `git worktree add /tmp/base132 HEAD`（已删）。
- `npm test` ⇒ rc=0（**34 例 = 32 PASS + 2 TMUX-ONLY**；`SKIP=0 · DEGRADE=0 · NOTE=10` 全白名单；`P2④` 旧 golden md5 断言仍 PASS）。
- 真仓零副作用：`git stash list` = 0 · `git worktree list` = 1（仅主工作树）。

## 遗留 / 观测（不阻断）

- 完备性判据**有意偏严**（PM 裁定保持严）：现行文档里「本机 `pi --version` 实测 1.5.2」这类**非门槛**版本也会被判「未归类」而红，处置是「写 `≥`」或「加截至」。自助说明已在 `tests/README.md`（用例 06 段），报错文案也点名两种改法。
- 未跟踪文档不扫（`git ls-files` 口径）：这是「扫描面 fail-closed 但不追未跟踪」的已知边界，已写进自助说明。
- `cases/06` 的 E2 段把 `NAO_STASH_WARN_HOURS=0` 当夹具参数用（不改生产默认 6），属既有闸门的合法 env 覆盖面（`cases/35` H/D 组同理）。

## 待办

- PM 验收 / QA 复核 → 由我执行 squash 合并（`gh pr merge --squash --delete-branch`，subject 显式给、不带 `wip(`）；台账 `docs/tasks-state.md`（含 `M20261114-helper-u-guard` 的关闭依据）由 PM 随本 PR 处置。
