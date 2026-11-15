# #130 闸调优（stash 年龄阈值 + `HERDR_*` 单源）—— 交付报告（rd-infra）

- 状态：待 QA 复核 · 更新：2026-11-15 · Owner：rd-infra
- 指针：Issue [#130](https://github.com/Nathan3303/nao-skills/issues/130)（D1 / D2=T543-O2）· 分支 `nao/M20261115-gate-tune`

## TL;DR

- D1：`check_stash_residue` 加**年龄阈值**（`NAO_STASH_WARN_HOURS`，默认 6）——只对**最老一条**超阈值的 warn；当天回填静默；warn-only / rc 不变 / `-v` 一条 / `NAO_STASH_ROOT` 语义不变。
- D2：`HERDR_*` 清理清单收敛为 `tests/t4/lib.sh` 的**单源数组**（8 个变量），4 处调用点全部改引用；新增一个变量只改一行。
- 结论：两条 AC 全过（含先红后绿与变异自证）；门禁 `check` rc=0 ×2、`npm test` 与双后端 full gate rc=0。
- 影响：`check` 的告警语义（当天回填不再报）；测试侧隔离清单单源化。零生产契约变化、不发版。
- 待办：QA 复核 → PM 验收 → 我执行 squash 合并（按 PM 指令，合并等验收后由我执行）。

## 变更清单（1 机制 + 6 测试，共 7 文件）

- `.agents/scripts/nao-fleet.sh:1537-1585`：`check_stash_residue` 加年龄阈值（`%ct` 最小值 + 阈值口径 + 未来时间戳不误报）。
- `tests/t4/lib.sh:196-208`：**单源** `T4_HERDR_ENV_VARS`（8 个变量名）+ 派生 `T4_HERDR_UNSET_ARGS`（`env -u` 参数）。
- `tests/t4/lib-backend.sh:703-737`：`be_herdr_unset_args`（单源 − 显式豁免）+ `be_run_fleet` 改引用（缺失即 fail loud）。
- `tests/t4/cases/06-contract-guards.sh`：`B3_CLEAN_ENV` 改引用；P2-1 旁证 stash 改为**8 小时前**；新增 D2①②③④⑤⑥⑦⑧ 判据组。
- `tests/t4/cases/28-naming-contract.sh:804,2207,2210`：`TMUX_FIELD_ENV` + 两条直连改引用（不再手写变量名）。
- `tests/t4/cases/35-stash-residue-warn.sh`：按年龄判据重写（A–J 组，含 fresh/aged/阈值覆盖/未来时间戳/非法阈值/双向/零副作用）。
- `tests/t4/cases/09-alias-guard.sh:198-204`：**超出 Issue 列出点位**——`HERDR_PANE_ID` 故意注入改用显式豁免通道（理由见 §三 D2 发现）。

## D1：年龄取法与时点口径

- **取 `git stash list --format='%ct'` 的最小值**（stash 提交的 committer date），不取 reflog 时间。理由：① `%ct` 是「事实被切出来」的时刻——`git stash store` 把**旧** stash 导入本仓时它保持原龄，而 reflog 时间会被刷成 now（旧事实被当新的、永久静默）；② 一次 `stash list` 取值，不必逐条 reflog 子进程。
- **阈值口径**：正整数 = 小时数；`0` = **立即**（关闭豁免，任何 stash 都 warn）；非数字 / 负数 = **非法** ⇒ 按 `0` 处理并在文案点名「取值无效」（配置坏了不得把闸门静默调松）。
- **不误报档**：未来时间戳（age<0）⇒ 不 warn；`%ct` 取不到/非数字 ⇒ 不 warn（时间不可信时不报，也不因算术崩）。
- 保留不变：warn-only（调用点 `|| true`）、不改 rc、聚合**一条** `  ! `、`NAO_STASH_ROOT` 注入根 / 根上无 `.git` 零输出 / 不向上 walk / 只读（无 push·pop·apply·drop）。

## D2：收敛与「枚举不得减少」的证明

- 收敛前并集（`git show HEAD:` 三文件，命令见下）⇒ **8 个**：`HERDR_ENV / HERDR_SESSION / HERDR_SOCKET_PATH / HERDR_SOCKET_FILE / HERDR_PANE_ID / HERDR_WORKSPACE_ID / HERDR_TAB_ID / HERDR_BIN_PATH`。
- 收敛后单源集合 ⇒ 同名 8 个；`diff` 两组**为空**（并集相等）：
  `diff <( { git show HEAD:tests/t4/lib-backend.sh; git show HEAD:tests/t4/cases/06-contract-guards.sh; git show HEAD:tests/t4/cases/28-naming-contract.sh; } | grep -oE -- '-u HERDR_[A-Z_]+' | sed 's/^-u //' | sort -u ) <(sed -n '/^T4_HERDR_ENV_VARS=(/,/)/p' tests/t4/lib.sh | grep -oE '\bHERDR_[A-Z_]+' | sort -u)`
- 单源定义处 = 1（`grep -c '^T4_HERDR_ENV_VARS=(' tests/t4/lib.sh` → 1）；手写残留 = 0（`grep -rnE -- '-u HERD[R]_' tests/ | wc -l` → 0）。
- 「新增一个 `HERDR_*` 只改一处」：调用点只引用派生参数（无变量名）⇒ 改单源一行即生效；D2⑦ 用副本**加**一个 `HERDR_DEMO_NEW` 实测派生参数 16→18、调用点零改动。
- PM 点名的行号全部核对成立：`nao-fleet.sh:1545`（函数定义）· `lib-backend.sh:711` · `cases/06:707` · `cases/28:804/2208/2211`。

## D2 两点判据修正（实测，需 PM/QA 知晓）

- **「删掉 `HERDR_SOCKET_FILE` ⇒ 至少一条**现有**断言红」在函数面不成立**：生产脚本从不读该变量（`grep -c HERDR_SOCKET_FILE .agents/scripts/nao-fleet.sh` → 0），它纯粹是防御性清理 ⇒ D 类用例不可能因它红。故判据落在**新增的枚举 golden 断言**上：实测删掉它 ⇒ D2②（并集 golden）/ D2⑤（派生参数 16→14）/ D2⑦×2 共 **4 条红**，还原复绿（不是空转）。
- **「清多了」有真实代价（本批实测回归）**：`be_run_fleet` 按单源**全集**清 ⇒ cases/09 AC3h③ 故意注入的 `HERDR_PANE_ID`（验「目标 pane = 调用者自身 ⇒ 保守拒」）被一起磨掉 ⇒ 3 条断言红（自 pane 被回收）。修法：默认全清 + **显式豁免** `BE_HERDR_KEEP="HERDR_PANE_ID"`（单点派生在 `be_herdr_unset_args`），并由 D2⑧ 钉住（默认 16 行 / 豁免后 14 行 / 被豁免变量不再出现）。这也说明「并集相等」是必要条件、不等于充分——**逐点清多**会破坏故意注入。

## 先红后绿

- D1（HEAD 脚本 + 新用例 35）⇒ **11 条红**：B2 / B4（fresh 仍 warn —— 病根）· C6 / D4 / E4（无年龄文案）· D2 · E7（最老一条判据）· H3（未来时间戳误报）· H6（非法阈值无提示）· J4 / J5（静态面）。现状全绿。
- D2（HEAD 测试树）⇒ D2① `0`（期望 1）· D2② 空集（期望 8）· D2③ 手写 6 行（期望 0）。现状全绿。
- 还原自证：两处临时覆盖（fleet 脚本 / lib.sh）后 `md5sum` 与覆盖前逐字节一致。

## 门禁（门禁时 HEAD=`9a59a8c` · `git status --porcelain` 空 · 本会话独占 worktree）

- `bash .agents/scripts/nao-fleet.sh check` ×2 → `check: OK · roles=7 · files=54 · layout=main-row2` · rc=0/0（两次逐字一致；`.agents/` 本批只改 `nao-fleet.sh`）。
- `npm run check:agents`（tsc）→ rc=0。
- `npm run test:t4:full:dual` → 组1 tmux `SKIP=0 · DEGRADE=0 · NOTE=9` rc=0 · 组2 herdr `SKIP=0 · DEGRADE=0 · NOTE=10` rc=0 ⇒ PASS（`cases/06`/`09`/`27`/`28`/`35` 均 PASS，golden 未破）。
- 另：`npm test`（默认 herdr 后端）亦 PASS；提交前同内容跑过一轮 dual 也 PASS。
- **一次瞬时 SKIP 已复跑排除**：某次 dual 的 herdr 组出现 `SKIP=1`（`T4_REQUIRE_FULL=1` 下计 FAIL）；随后同内容连跑两次 `SKIP=0` ⇒ 属用例 02/07 的外部依赖（pi 凭据 / registry）瞬时不可达，与本批改动无关（两者本轮均 PASS）。
- 敏感值扫描（7 文件：token/私钥/绝对家目录）→ **0 命中**；`codegraph status` → Index is up to date。

## 风险 / 边界

- 阈值 6h 是经验值（本仓两次噪声样本 7.5h / 7d）；若仍噪声，改 `NAO_STASH_WARN_HOURS` 或下一批再调，不引入「stash 标签豁免」特例。
- 用例依赖 GNU `date -d`（造 8h 前 / 未来时间戳）；缺能力时显式 `t4_bad`（不静默跳过时间判据）。
- `cases/35` 的 `HERDR_*` 清理仍是**动态枚举**（`env | grep -o '^HERDR_[A-Z_]*'`，超集）——故意不并入单源（并入会由超集降为 8 个定集，属枚举收缩）。
- 本批只合并不发版；合并 sha 由 PM 验收后我回填台账。

- 修订：2026-11-15 首次交付（D1 + D2 全过；D2 判据两点按实测修正并已落到断言）
