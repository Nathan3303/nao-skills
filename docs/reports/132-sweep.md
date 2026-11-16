# #132 backlog sweep · E2 两条守卫 —— 交付报告（rd-infra）

- 状态：待 PM 验收 · 更新：2026-11-16 · Owner：rd-infra
- 指针：Issue [#132](https://github.com/Nathan3303/nao-skills/issues/132)（E2-1 / E2-2）· 分支 `nao/M20261116-backlog-sweep`（PM 已建并 push，起点 HEAD `ff630c7`）· 台账部分（E1）由 PM 完成，本报告只覆盖 E2

## TL;DR

- **E2-1（pi 阈值一致性断言）**：文档里的版本号**一个没删**（用户要看到门槛），改为「文档声明的 `pi` 下限必须 == 脚本单源 `MIN_PI_VERSION`，漂移即红并点名 `文件:行`」。判据两条：① 下限声明取值比对 ② **完备性**（现行文档里任何「pi … x.y.z」提及都必须归类：或本身是下限声明，或该行带「截至」历史时点标注）。
- **E2-2（`NAO_STASH_ROOT` helper 守卫）**：`t4_run_shim` / `be_run_fleet` 两个单点的 `-u NAO_STASH_ROOT` 现在有断言守卫 —— 宿主导出注入根时**经 helper** 跑的 `check` 无 `warn=`，并给出「**是被清掉**（而非闸门没触发）」的区分证据 + 删 `-u` 必红的反空转。
- **门禁**：`check` rc=0 ×2 输出**逐字一致**（`files=54` 不变）· `cases/06` PASS（断言 **284 → 322**，其中 E2 新增 **37** 条）· `npm test` rc=0（34 例 = 32 PASS + 2 TMUX-ONLY · SKIP=0 · DEGRADE=0 · NOTE=10 白名单）· golden 未破（`P2④` 旧 md5 断言仍 PASS）。
- **判据订正（实测）**：PM 给的行号/口径有 2 处不成立 ——
  1. 扫描面不是 4 个文件：实测 **7 个文件 / 10 行 / 11 处**（多了 `.agents/skills/nao-fleet/SKILL.md:32`、`.agents/skills/pm-operations.md:14`、`docs/ARCHITECTURE.md:45`；**订正**：本报告初版写「8 文件 / 9 行」是我笔误，PM 复算的 7 文件为准，三个数的可复算命令见 §E2-1 末「计数证据」）；
  2. PM 给的正则形态 `pi ≥?\s*x.y.z` **抓不到** `docs/INSTALL.md` 的三处（`:12` 是 `pi（≥ 1.4.0）`、`:22` 是 `需 ≥ 1.4.0`、`:34` 是 `pi 版本低于 1.4.0`）⇒ 扫描器改用「`pi` … `≥`/`低于`」两条形态 + 完备性兜底。
- 影响：纯测试侧新增断言，零生产代码/零文档改动、不发版。

## 变更清单（1 测试 + 本报告）

- `tests/t4/cases/06-contract-guards.sh`：新增 **E2-1** 组（pi 阈值文档面一致性，21 条断言）与 **E2-2** 组（两 helper 的 `-u NAO_STASH_ROOT` 守卫，16 条断言）。
- `docs/reports/132-sweep.md`：本报告。
- 未改：`.agents/scripts/nao-fleet.sh`（`MIN_PI_VERSION` 仍 `1.4.0`，脚本内该字面量仍恰 1 处）· `tests/t4/lib.sh` / `lib-backend.sh`（两个 `-u` 硬化本就存在，本批只补守卫）· 任何文档的版本号。

## E2-1 设计与判据（`cases/06` · E2-1①–④）

**为什么不是「清空文档数字」**：用户的可见门槛必须在文档里（README 前置环境 / INSTALL 安装校验 / AGENTS 约束）。删数字等于把门槛藏进脚本，用户看不到；保留数字又必然出现「脚本改了文档没改」的双源漂移 ⇒ 用断言把双源钉成「同一事实」。

**单源与扫描面**

- 基准 = 被测根下 `.agents/scripts/nao-fleet.sh` 的 `MIN_PI_VERSION`（当前 `1.4.0`）。取的是**根下**脚本而不是仓库常量：这样负控可以在副本里改常量而不碰真仓。
- 扫描面是 **fail-closed** 的，不是白名单文件清单：`git ls-files -- '*.md'` 减去三类**历史时点**目录/文件 —— `docs/{adr,prds,releases,reports,notes,designs,research}/`（as-of 记录，改写即伪造历史）· `docs/tasks-*.md`（台账/归档视图）· `tests/`（夹具与负控样本，故意构造漂移）。新增文档会自动进入扫描面（无需维护清单）；要豁免只能落进上述**类**。

**两条判据**

- ① **声明式下限**：正则 `pi[^0-9]*(≥|>=|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+` 逐处抽取版本，必须 == 单源；不等则打印 `<文件>:<行> 声明 <版本> ≠ 单源 <MIN_PI_VERSION>`。形态覆盖 `pi ≥ 1.4.0` / `pi ≥1.4.0` / `pi（≥ 1.4.0）` / `需 ≥ 1.4.0` / `pi 版本低于 1.4.0`。
- ② **完备性**：同一批文件里凡出现「pi … x.y.z」的行，必须**已被归类** —— 要么其 `文件:行` 已在 ① 的命中集里，要么该行带 **「截至」**（历史时点标注）。否则打印 `<文件>:<行> 未归类：既非下限声明（≥/低于），也无「截至」历史时点标注`。这条是防「换一种写法写漂移而 ① 抓不到」的兜底，也是 `codegraph.md:21` 的豁免机制。

**`codegraph.md:21` 的豁免口径（PM 问的那条）**：不按文件名硬编码。该行是「插件不供 system prompt 指引（**截至** pi 1.4.0 / pi-codegraph 0.1.0）」——`截至 pi 1.4.0` 是**历史时点事实**（版本戳），不是运行时门槛，因此既不含 `≥`/`低于`（① 天然不命中），也有「截至」标注（② 放行）。机制承重由 E2-1④ 证明：**把副本里那个「截至」摘掉** ⇒ 同一行立刻变「未归类」必红。

**现仓覆盖（实测 7 文件 / 10 行 / 11 处，全部 == `1.4.0`**；`intercom-protocol.md:36` 一行含 2 处 ⇒ 行数 ≠ 处数）

- `README.md:28`（`pi ≥ 1.4.0`）
- `AGENTS.md:18`、`AGENTS.md:33`
- `.agents/common/intercom-protocol.md:36`（同一行两处）
- `.agents/skills/nao-fleet/SKILL.md:32`
- `.agents/skills/pm-operations.md:14`
- `docs/ARCHITECTURE.md:45`
- `docs/INSTALL.md:12`（`pi（≥ 1.4.0）`）、`:22`（`需 ≥ 1.4.0`）、`:34`（`pi 版本低于 1.4.0`）

断言形态：现仓全绿 + **扫描面**非空（现行 `*.md` ≥ 40 个，防 `git ls-files` 取不到而无对象空转）+ 声明处数下限（≥11）+ **逐文件覆盖**（上列 7 个文件各至少 1 处声明 —— 谁把某处版本号删了，那条会红）+ `codegraph.md` 不进声明面的显式断言。

**先红后绿（全部在 `$T4_CACHE_DIR` 的副本里，真仓零触碰）**

- ② **只改脚本常量**（副本 `MIN_PI_VERSION="9.9.9"`，文档不动）⇒ 必红并点名：`README.md:28 声明 1.4.0 ≠ 单源 9.9.9`、`docs/INSTALL.md:12 声明 1.4.0 ≠ 单源 9.9.9`（同轮多处，不只报首个）。
- ③ **只改某文档**（副本 `README.md:28` → `pi ≥ 9.9.9`，脚本不动）⇒ `README.md:28 声明 9.9.9 ≠ 单源 1.4.0` 必红（两个方向都能抓）。
- ④ **摘掉历史时点标注**（副本 `codegraph.md` 去「截至」）⇒ `codegraph.md:21 未归类` 必红（证明豁免靠标注，不靠文件名）。

**计数证据（`文件:行:处` 三个数都可复算，口径 = `git ls-files -- '*.md'` 减历史类；正则如上）**

```bash
PRUNE='^(docs/(adr|prds|releases|reports|notes|designs|research)/|docs/tasks-[^/]*$|tests/)'
FILES="$(git ls-files -- '*.md' | grep -vE "$PRUNE")"
printf '%s\n' "$FILES" | xargs grep -nE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+'   # 逐条命中（10 行）
printf '%s\n' "$FILES" | xargs grep -lE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+' | wc -l   # 7 文件
printf '%s\n' "$FILES" | xargs grep -nE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+' | wc -l   # 10 行
printf '%s\n' "$FILES" | xargs grep -oE 'pi[^0-9]*(≥|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+' | wc -l   # 11 处
```

- 差异来源：`intercom-protocol.md:36` 的一行里出现 2 次（`pi ≥ 1.4.0` 在「ADR 已被取代…语义不变」与「任一端都要求」各一次）⇒ **10 行 / 11 处**。用例里的 `≥ 11` 是**处数**下限（不是行数），与本节口径一致。

**开发期真实抓到的两个坑（留证：断言不是摆设）**

- `awk -v exp=…` 与 gawk 内置函数 `exp` 撞名 ⇒ gawk 直接 fatal、比对结果为空（假绿面）。是本组的②③断言把它打红，改名 `want` 后转绿 —— 这条正好证明「① 现仓全绿」单独存在时会空转。
- 完备性首版把 `README.md:66` 的 `pi install --local npm:@0.21.3` 判成未归类（那是**包版本 pin**，不是 pi 自身门槛）⇒ 正则排除前导 `@`（`pi[^0-9@]*x.y.z`）；口径已写进用例注释。

## E2-2 设计与判据（`cases/06` · E2-2①–⑤）

**缺口复述**：`NAO_STASH_ROOT` 的宿主泄漏硬化（#126 P3④）落在两个 helper 单点上 —— `tests/t4/lib.sh:639`（`t4_run_shim`）与 `tests/t4/lib-backend.sh:738-740`（`be_run_fleet` 的 `envs` 数组）。硬化只存在于文本里，**谁删掉都没有用例会红**：宿主若导出了注入根，夹具 `check` 会平白多一条 stash warn（假红面复活）。

**落点选择**：放 `cases/06` 而不是台账里点名的 `cases/34`。理由 —— 本组验的是**测试基座**（helper）不涉及端前提/闸门语义，与紧邻的 D2「helper 单点清理清单（`HERDR_*` 单源）」同主题；且 06 已有 `C6_GIT` 临时仓夹具（P2-1 段建的 `git init` 仓），无需新开仓、无跨用例耦合。`cases/34` 是端前提 warn 用例，既无 stash 夹具也无 helper 调用面。

**四段证据（把「warn=0 的两种解释」分开）**

- ① **直连旁证**：同一份 env 直接跑脚本（`NAO_STASH_ROOT=<临时仓>` + `NAO_STASH_WARN_HOURS=0` + 桩 `pi`/`herdr`/`tmux`）⇒ 摘要 `warn=1`。证明「根注入本来有效、闸门活着」。
- ② **经 `t4_run_shim`**（宿主 env 里带同一个 `NAO_STASH_ROOT`）⇒ `check: OK`、rc=0、**无 `warn=`** ⇒ 只能是 `-u` 清场的结果（配合 ① 排除「闸门没触发」）。
- ③ **经 `be_run_fleet`**（同宿主 env；`BE_FLEET_NO_HANDLES=1` + `BE_FLEET_SCRIPT` 指定被测脚本）⇒ 同样 rc=0、无 `warn=`。
- ④ **反空转**：副本删掉 helper 里的 `-u NAO_STASH_ROOT`（`lib.sh` 的 `env -u NAO_STASH_ROOT "$@"` → `env "$@"`；`lib-backend.sh` 的 `-u NAO_STASH_ROOT)` → `)`），并断言两个副本 `bash -n` 语法合法 + 变异锚点已生效 ⇒ 同一调用形态 `warn=1` **回来**，即 ①②③ 的断言必红。
- ⑤ **静态定位**：两个 helper 各恰 1 处 `-u NAO_STASH_ROOT`（行为判据之外的可定位面，防「判据过了但硬化被搬到别的分支」）。

**夹具纪律**：stash 只造在 `$T4_CACHE_DIR/c6-git<pid>`（P2-1 段 `git init` 的临时仓）里，用 `GIT_AUTHOR_DATE/GIT_COMMITTER_DATE` 之外无需 sleep —— `NAO_STASH_WARN_HOURS=0`（= 立即）让判据与时钟解耦。真实仓库全程 `git stash list` = **0**（门禁后复核），worktree = 1（基线 worktree 已删）。

## 门禁（本机实测 · HEAD 起点 `ff630c7` + 本批工作树）

- `bash .agents/scripts/nao-fleet.sh check` ⇒ rc=0 **×2 输出 `diff` 空**（`check: OK · roles=7 · files=54 · layout=main-row2`；`files` 不变，只加测试断言）。
- `bash tests/t4/run.sh --case 06` ⇒ **RESULT: PASS**（`[PASS]` 284 → **322**；E2 新增 **37** 条 = E2-1 21 + E2-2 16，其余差额来自按环境条件触发的既有 `P2④` md5 断言）。baseline 对照 = 同仓 `git worktree add /tmp/base132 HEAD`（已删）。
- `npm test` ⇒ **rc=0**（**34 例 = 32 PASS + 2 TMUX-ONLY**；`SKIP=0 · DEGRADE=0 · NOTE=10` 全白名单；后端索引对账 34 = `--list` 计数（共享 22 / 本后端专有 10 / tmux 专有 2 / PENDING 0）；`P2④` 旧 golden md5 断言仍 PASS）。
- 双后端 `test:t4:full:dual` **未重跑**（按 PM 口径：只加断言、未改 `lib*` 与生产脚本；且 E2 两段都不依赖父后端 —— `NAO_TERMINAL=tmux` 显式给定、`be_run_fleet` 走 `NO_HANDLES` 直连）。
- 真仓零副作用：`git stash list` = 0 · `git worktree list` = 1（仅主工作树）。

## 遗留 / 观测（不阻断）

- 完备性判据比 PM 原口径**更严**：现行文档里若有人写「本机 `pi --version` 实测 1.5.2」这类**非门槛**版本，会被判「未归类」而红。这是有意的（任何 pi 版本提及都必须归类），处置方式已写在报错文案里：改成下限声明，或加「截至」标注。若 PM 认为太紧，可降级为「只在 ① 面比对」（但会丢掉「换写法漂移」的护栏）。
- `cases/06` 的 E2 段把 `NAO_STASH_WARN_HOURS=0` 当夹具参数用（不改生产默认 6）；这是既有闸门的合法 env 覆盖面（`cases/35` H/D 组同理）。

## 待办

- PM 验收 → 由我执行 squash 合并（`gh pr merge --squash --delete-branch`，subject 显式给、不带 `wip(`）；台账 `docs/tasks-state.md`（含 `M20261114-helper-u-guard` 的关闭依据）由 PM 随本 PR 处置。
