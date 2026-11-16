# #130 闸调优（stash 年龄阈值 + `HERDR_*` 单源）—— 交付报告（rd-infra）

- 状态：待 PM 验收（QA 复核后返修已完）· 更新：2026-11-15 · Owner：rd-infra
- 指针：Issue [#130](https://github.com/Nathan3303/nao-skills/issues/130)（D1 / D2=T543-O2）· 分支 `nao/M20261115-gate-tune` · QA 复核 `docs/reports/130-qa-verify.md`

## TL;DR

- D1：`check_stash_residue` 加**年龄阈值**（`NAO_STASH_WARN_HOURS`，默认 6）——只对**最老一条**超阈值的 warn；当天回填静默；warn-only / rc 不变 / `-v` 一条 / `NAO_STASH_ROOT` 语义不变。
- D2：`HERDR_*` 清理清单收敛为 `tests/t4/lib.sh` 的**单源数组**（8 个变量），4 处调用点全部改引用；新增一个变量只改一行。
- **末轮返修（QA P2×2 + P3×4 + 末轮 D2⑩）**：前导零阈值不再让体检崩（`08` ⇒ 旧实现 rc=1）；`%ct` 取不到时留降级注记；补**行为**反渗漏（D2⑨）与**清理→注入顺序**（D2⑩）两条子例；逗号分隔真生效；`cases/33` 注释订正。
- 结论：两条 AC 全过 + 返修全闭环（含先红后绿与变异自证）；门禁 `check` rc=0 ×2、`npm test` 与双后端 full gate 均 rc=0。
- 影响：`check` 的告警语义（当天回填不再报）；测试侧隔离清单单源化。零生产契约变化、不发版。
- 待办：PM 验收 → 我执行 squash 合并（按 PM 指令，合并等验收后由我执行）。

## 变更清单（1 机制 + 5 测试 + 本报告）

- `.agents/scripts/nao-fleet.sh:1537-1585`：`check_stash_residue` 加年龄阈值（`%ct` 最小值 + 阈值口径 + 未来时间戳不误报）。
- `tests/t4/lib.sh:196-208`：**单源** `T4_HERDR_ENV_VARS`（8 个变量名）+ 派生 `T4_HERDR_UNSET_ARGS`（`env -u` 参数）。
- `tests/t4/lib-backend.sh:703-737`：`be_herdr_unset_args`（单源 − 显式豁免）+ `be_run_fleet` 改引用（缺失即 fail loud）。
- `tests/t4/cases/06-contract-guards.sh`：`B3_CLEAN_ENV` 改引用；P2-1 旁证 stash 改为**8 小时前**；新增 D2①–⑩ 判据组（含 `D2⑧b` 逗号、`D2⑨` 行为反渗漏、`D2⑩` 清理→注入顺序）。
- `tests/t4/cases/28-naming-contract.sh:804,2207,2210`：`TMUX_FIELD_ENV` + 两条直连改引用（不再手写变量名）。
- `tests/t4/cases/35-stash-residue-warn.sh`：按年龄判据重写（A–J 组，含 fresh/aged/阈值覆盖/未来时间戳/非法阈值/双向/零副作用）。
- `tests/t4/cases/09-alias-guard.sh:198-204` + `cases/33:54-58`：**超出 Issue 点位**——`HERDR_PANE_ID` 故意注入改用显式豁免通道；`cases/33` 注释订正（不是「枚举清」，是按单源固定名单清）。

## 末轮返修（QA 复核 P2×2 + P3×4 · #130 末轮）

- **P2-1 阈值前导零 ⇒ `check` 硬红（必修）**：根因 = `$(( hours * 3600 ))` 把前导零当八进制（`08` 直接报「值对于底数而言过大」⇒ rc=1 且无汇总行；`010` 静默按 8 生效、文案却写 010）。修法 = 算术前 `hours=$((10#$hours))`。实测（9h stash，HEAD `709b397`）：`08` ⇒ rc=0 + `warn=1`（按 8）；`010` ⇒ rc=0 无 `warn=`（按 10）；`0008` ⇒ rc=0 + `warn=1`（按 8）；文案回显「最老一条 9 小时前 > 阈值 8 小时」。断言：`cases/35 H8/H9`（三档 + 文案回显）+ `J7`（`10#` 单点）。
- **P2-2 `%ct` 取不到 ⇒ 与「无 stash」不可区分（必修）**：仍不 warn（方向不变），但加一条 `  ·` 降级注记（只进 `-v`、不计 warn、不改 rc）。实测输出：`  · 暂存滞留检查跳过：\`stash list --format=%ct\` 不可解析（1 条 stash 仍在）⇒ 无法做年龄判定（未 warn，也未据此判「无滞留」）`；摘要模式仍只 2 行（注记不进摘要）。断言：`cases/35 H10`（假 git 把 `%ct` 打成 `n/a`，对照真 git 同一条 9h stash ⇒ 1 条 warn）+ `J8`。
- **P3① 红数订正**：本报告原文写「删 `HERDR_SOCKET_FILE` ⇒ 4 红」有误。QA 在 `1414c37` 实测 **6 红**；本轮新增 `D2⑧b` 后实测 **7 红**（`D2②` / `D2⑤` / `D2⑦×2` / `D2⑧×2` / `D2⑧b`，还原复绿、lib.sh md5 逐字节一致）。
- **P3② 补 1 条行为反渗漏断言（本轮最重要）**：新断言 `D2⑨ 行为反渗漏：父进程注入 8 个 HERDR_* ⇒ 被测子进程 env 里 0 条`——把 `be_run_fleet` 的被测脚本换成「打印自身 env 里 `HERDR_*`」的桩（`BE_FLEET_NO_HANDLES=1`），断言对象是**子进程真实 env**，不是 argv 文本。先红证据：删 `HERDR_ENV`（生产确读）⇒ **8 红**，其中 `D2⑨` 是唯一的行为红（旧口径 7 红全静态、0 行为红）；还原复绿。
- **P3③ 逗号分隔**：选择「**支持逗号**」（不改注释、改实现）：`be_herdr_unset_args` 先把 `BE_HERDR_KEEP` 的逗号归一为空格再匹配；断言 `D2⑧b`（`HERDR_PANE_ID,HERDR_ENV` ⇒ 12 行且两个变量都真被豁免）。
- **P3④ 不改（QA 已实证）**：`AC3h③` 理由确为「判为调用者自身」、移除 `BE_HERDR_KEEP` ⇒ 3 红 ⇒ 非假绿，仅记录。
- **D2⑩ 「清理 → 注入」顺序面（末轮 B 方案 · QA 4 点判据）**：给足 `BE_BACKEND`/`BE_SESSION`/`BE_CFGROOT`（`be_fleet_handles` 真能注入）、**不设** `NO_HANDLES`，父进程注入 8 个**可识别**值（`HOSTLEAK-*`，不用 `1`/空值）。判据：① 8 值**逐条** `not_contains`（不数条数；ENV/SESSION/SOCKET_PATH 会被句柄覆盖 ⇒ 真正承重的是另 5 个）② 实验句柄**具体值**在场（`HERDR_ENV=1` / `HERDR_SESSION=d2h-fixture-sess` / `HERDR_SOCKET_PATH=$T4_CACHE_DIR/…/<sess>/herdr.sock` / `NAO_TERMINAL=herdr` —— 父给定 `tmux` ⇒ 只能来自注入，两种后端都承重）③ 输出无 `BE_BACKEND: 未绑定的变量`（上下文真初始化）。
  变异三连（各还原复绿；`lib-backend.sh` md5 `36923955…` 逐字节一致）：删 `"${hu[@]}"` ⇒ **① 5 红 / ② 全绿**（① 测清理）；`be_fleet_handles` 返回空 ⇒ **② 5 红 / ① 全绿**（② 测注入）；把注入挪到清理之前 ⇒ **② 5 红**（`env` 把 `-u` 当命令，连 `BE_RC` 都不是 0）。
- **判据订正（PM 自认 + 本批落地）**：`D2⑨` 的 `BE_FLEET_NO_HANDLES=1` **不承重** —— 该子例是 bare 子壳、无 BE 上下文 ⇒ `be_fleet_handles` 本就注不出句柄（注入面为空）；注释已写明「顺序面由 D2⑩ 覆盖」。

## D1：年龄取法与时点口径

- **取 `git stash list --format='%ct'` 的最小值**（stash 提交的 committer date），不取 reflog 时间。理由：① `%ct` 是「事实被切出来」的时刻——`git stash store` 把**旧** stash 导入本仓时它保持原龄，而 reflog 时间会被刷成 now（旧事实被当新的、永久静默）；② 一次 `stash list` 取值，不必逐条 reflog 子进程。
- **阈值口径**：正整数 = 小时数；`0` = **立即**（关闭豁免，任何 stash 都 warn）；非数字 / 负数 = **非法** ⇒ 按 `0` 处理并在文案点名「取值无效」（配置坏了不得把闸门静默调松）。
- **不误报档**：未来时间戳（age<0）⇒ 不 warn；`%ct` 取不到/非数字 ⇒ 不 warn（时间不可信时不报，也不因算术崩）。保留不变：warn-only（`|| true`）、不改 rc、聚合**一条** `  ! `、`NAO_STASH_ROOT` 注入根 / 根上无 `.git` 零输出 / 不向上 walk / 只读。

## D2：收敛与「枚举不得减少」的证明

- 收敛前并集（`git show HEAD:` 三文件，命令见下）⇒ **8 个**：`HERDR_ENV / HERDR_SESSION / HERDR_SOCKET_PATH / HERDR_SOCKET_FILE / HERDR_PANE_ID / HERDR_WORKSPACE_ID / HERDR_TAB_ID / HERDR_BIN_PATH`。
- 收敛后单源集合 ⇒ 同名 8 个；`diff` 两组**为空**（并集相等）：
  `diff <( { git show HEAD:tests/t4/lib-backend.sh; git show HEAD:tests/t4/cases/06-contract-guards.sh; git show HEAD:tests/t4/cases/28-naming-contract.sh; } | grep -oE -- '-u HERDR_[A-Z_]+' | sed 's/^-u //' | sort -u ) <(sed -n '/^T4_HERDR_ENV_VARS=(/,/)/p' tests/t4/lib.sh | grep -oE '\bHERDR_[A-Z_]+' | sort -u)`
- 单源定义处 = 1（`grep -c '^T4_HERDR_ENV_VARS=(' tests/t4/lib.sh` → 1）；手写残留 = 0（`grep -rnE -- '-u HERD[R]_' tests/ | wc -l` → 0）。
- 「新增一个 `HERDR_*` 只改一处」：调用点只引用派生参数（无变量名）⇒ 改单源一行即生效；D2⑦ 用副本**加**一个 `HERDR_DEMO_NEW` 实测派生参数 16→18、调用点零改动。
- PM 点名的行号全部核对成立：`nao-fleet.sh:1545`（函数定义）· `lib-backend.sh:711` · `cases/06:707` · `cases/28:804/2208/2211`。

## D2 两点判据修正（实测，需 PM/QA 知晓）

- **「删 `HERDR_SOCKET_FILE` ⇒ 至少一条**现有**断言红」在函数面不成立**：生产脚本从不读它（`grep -c HERDR_SOCKET_FILE .agents/scripts/nao-fleet.sh` → 0）⇒ D 类行为用例不可能因它红。故判据落在**新增的枚举 golden** 上：实测删掉它 ⇒ `D2②`/`D2⑤`/`D2⑦×2`/`D2⑧×2`/`D2⑧b` 共 **7 条红**（QA 在 `1414c37` 无 `D2⑧b` 时实测 6 条；P3① 已按此订正），还原复绿。
- **「清多了」有真实代价（本批实测回归）**：`be_run_fleet` 按单源**全集**清 ⇒ cases/09 AC3h③ 故意注入的 `HERDR_PANE_ID`（验「目标 pane = 调用者自身 ⇒ 保守拒」）被一起磨掉 ⇒ 3 条断言红（自 pane 被回收）。修法：默认全清 + **显式豁免** `BE_HERDR_KEEP="HERDR_PANE_ID"`（单点派生在 `be_herdr_unset_args`），并由 D2⑧ 钉住（默认 16 行 / 豁免后 14 行 / 被豁免变量不再出现）。这也说明「并集相等」是必要条件、不等于充分——**逐点清多**会破坏故意注入。

## 先红后绿

- D1（HEAD 脚本 + 新用例 35）⇒ **11 条红**：B2 / B4（fresh 仍 warn —— 病根）· C6 / D4 / E4（无年龄文案）· D2 · E7（最老一条判据）· H3（未来时间戳误报）· H6（非法阈值无提示）· J4 / J5（静态面）。现状全绿。
- D2（HEAD 测试树）⇒ D2① `0`（期望 1）· D2② 空集（期望 8）· D2③ 手写 6 行（期望 0）。现状全绿。还原自证：两处临时覆盖（fleet 脚本 / lib.sh）后 `md5sum` 与覆盖前逐字节一致。

## 门禁（门禁时 HEAD=`709b397` · `git status --porcelain` 空 · 本会话独占 worktree）

- `bash .agents/scripts/nao-fleet.sh check` ×2 → `check: OK · roles=7 · files=54 · layout=main-row2` · rc=0/0（两次逐字一致；`.agents/` 本批只改 `nao-fleet.sh`）。
- `npm run check:agents`（tsc）→ rc=0。
- `npm test`（默认 herdr 后端）→ rc=0 · `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=10 · NOTE白名单=10）`。
- `npm run test:t4:full:dual` → 组1 tmux `SKIP=0 · DEGRADE=0 · NOTE=9` rc=0 · 组2 herdr `SKIP=0 · DEGRADE=0 · NOTE=10` rc=0 ⇒ PASS（`cases/06`/`09`/`28`/`33`/`35` 均 PASS，golden 未破）。前一轮 `SKIP=1` 已定位为用例 07（npm registry 瞬时不可达，与本批无关），同内容重跑 `07 PASS · SKIP=0`。
- 敏感值扫描（5 改动文件：token/私钥/绝对家目录）→ **0 命中**；`codegraph status` → Index is up to date。

## 风险 / 边界

- 阈值 6h 是经验值（本仓两次噪声样本 7.5h / 7d）；若仍噪声，改 `NAO_STASH_WARN_HOURS` 或下一批再调，不引入「stash 标签豁免」特例。
- 阈值解析：前导零按十进制（`08`/`010`/`0008` = 8/10/8）；**超长数字**（>19 位）按 bash 64 位回绕 —— 实测 `99999999999999999999` 回绕成负数 ⇒ `warn=1`（方向偏暴露，不静默；rc 恒 0）。未加位数上限（如需硬校验可加）。
- 用例依赖 GNU `date -d`（造 8h 前 / 未来时间戳），缺能力时显式 `t4_bad`；`cases/35` 的 `HERDR_*` 清理仍是**动态枚举**（超集）——故意不并入单源（并入会由超集降为 8 个定集 = 枚举收缩）。
- 本批只合并不发版；合并 sha 由 PM 验收后我回填台账。

- 修订：2026-11-15 首次交付（D1 + D2 全过；D2 判据两点按实测修正并已落到断言）
- 修订：2026-11-15 末轮返修（QA P2-1/P2-2 + P3①②③⑤ 全闭环；新增 D2⑨ 行为反渗漏与 H8/H9/H10）
- 修订：2026-11-16 补 D2⑩（清理→注入顺序面 · QA 4 点判据 + 变异三连）
