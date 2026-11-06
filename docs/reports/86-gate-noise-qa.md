# #86 发布闸门降噪 —— QA 非作者复核

- 分支：`fix/86-gate-noise` · 复核基线 HEAD `2640601`（`git diff main...HEAD` = 9 文件 +160 −11，实现面 0 改动）
- Draft PR [#87](https://github.com/Nathan3303/nao-skills/pull/87) · Issue [#86](https://github.com/Nathan3303/nao-skills/issues/86)
- 结论：**CONDITIONAL GO（0 P1 / 1 P2 / 5 P3）** —— P2 是本批自定的「不掩盖真故障」口径在**一支边缘**上未闭合，修法 1 行 + 2 条断言；其余全过。
- 复核方式：全部证据由 QA 自造（自建桩、自造变异、自造 wired 负控），未复用 RD 的注入脚本。

## 一、逐 AC

**AC1（重试吸收延迟抖动）— 通过**

- 真跑（本机正常网络）：`cases/02` `pi-smoke: attempt1 rc=0 bytes=99964…146867 · attempt2 rc=- bytes=- · retry=no` ⇒ PASS，`SKIP=0`。
- 单测：`cases/26` R1（两次超时 ⇒ rc=4、恰 2 次调用）、R1b（首次超时 + 重试成功 ⇒ rc=0、产物落盘可解析）。
- dual 两组各跑一次真 `pi` 冒烟，均 `SKIP=0`。

**AC2（不掩盖真故障）— 部分未过（P2-1）**

- 「首次失败**有输出**」支：通过。QA 用 wired 负控（`PATH` 前置假 `pi`，rc=7 + 20B 输出）⇒ **1 次调用、不重试**、`SKIP`（full 轴判红），无掩蔽。
- 「首次失败**无输出**」支：**未过**。当前判据 `rc1=124 || b1=0` 会在 `rc≠0 且 b1=0` 时重试；若重试恰好成功，`t4_pi_smoke` 返回 0 ⇒ 用例转绿。QA 自造实测：桩「首次 exit 7 + 无 stdout，第二次输出 `{"ok":1}`」⇒ `pi-smoke: attempt1 rc=7 bytes=0 · attempt2 rc=0 bytes=8 · retry=yes`、**返回值 0（绿）**、调用 2 次。这正是 AC2 要禁的「重试把真故障洗成绿」，只是入口窄（要求首次快速失败且零 stdout）。
- 归因说明（不回避）：Issue/我早先的口径原文是「首次 rc=124 **或** 0 字节」，RD 是按字面实现的，`cases/26` 的 R3 也把该行为**显式钉住**（`empty` 桩 exit 3 + 0B ⇒ 期望 `retry=yes`/2 次调用）。所以这不是「RD 偏离」，而是**我的口径文本留了洞**，本轮由 QA 收口。
- 建议改法（缺陷，不给代码）：判据收成 `rc1=124 || (rc1=0 && b1=0)`；`cases/26` R3 改成「非零退出 + 0 字节 ⇒ 不重试（1 次调用、rc=4）」；补两条断言：① `rc=0 && 0 字节` ⇒ 仍重试；② 「首次 rc≠0（无输出）+ 第二次成功 ⇒ 仍返回 4 / 仍红」（把我上面那条假成功路径钉进用例）。

**AC3（语义不变：重试仍失败 ⇒ SKIP，full 轴照红）— 通过**

- `cases/26` R1/R3：两次都失败 ⇒ 返回 4；wired 负控（假 `pi` 恒失败）⇒ `cases/02` 报 `SKIP`、不报 PASS。

**AC4（护栏自身可验证 / 非空转）— 通过（QA 三组独立变异，全部精确翻红）**

- M1「把重试条件放宽成任何非 0 都重试」⇒ `cases/26` rc=1、**3 红全在 R2**：`R2 负控: 未重试（按实际调用次数证）（期望=1 实际=2）` + info 行两条。
- M2「只声称重试、实际不再调用」（假重试）⇒ rc=1、**7 红**：R1 `期望=4 实际=0` / `恰好两次 attempt（期望=2 实际=1）` / info 缺 attempt2；R1b `重试恰一次（2/1）` + 产物缺失；R3 `首次 0 字节 ⇒ 允许重试（2/1）` + `仍返回 4（4/0）`。**这条正面证明断言吃的是真实调用计数**：若只信 info 行（M2 的 info 仍宣称 retry=yes/success），这 7 条会全绿。
- M3「真重试但 info 谎报 retry=no」⇒ 2 红（R1/R3 的 `retry=yes` 断言）。⇒ info 行与计数器两侧都是硬断言，非装饰。

**AC5（门禁）— 通过（QA 自跑 · 串行 · 跑前 `ps`）**

- `check` rc=0 ×2，`check: OK · roles=7 · files=54 · layout=main-row2`，两次输出逐字一致。
- `npm test` rc=0 · 用例 **25** · 断言 **949** · `SKIP=0 · DEGRADE=0 · NOTE=2`（白名单 `06:static-contract` ×2）—— 与 RD 报数逐项一致。
- `npm run test:t4:full:dual` rc=0 · 组 1 / 组 2 各 **949 断言 / 25 例 / SKIP=0**、白名单 NOTE=2、**`[FAIL]` 0 条**；未撞到 `SKIP=1`（本批目标达成）。
- 变更面核查：`.agents/scripts/`、`bin/`、`package.json`、`.agents/roles.yaml`、`.agents/prompts/` 在 `main...HEAD` 上 **0 行**改动 ⇒ 未改实现；`git diff` 无家目录绝对路径/token/私钥字样。

## 二、B 追溯数字（QA 独立复核）

`git show -s --format=%b <sha> | grep -c 'wip('`（行数，与出现次数三者相同）：

- `#80` `57e5fad` = **8** ✓ · `#82` `b87bd00` = **4** ✓ · `#84` `34bc068` = **6** ✓（RD 报数 8/4/6 全部正确）。
- `%s` 三者均 = 0（subject 一直是干净的，问题只在自动 body）。
- body 首行：`#80` = `* feat(uiux): 立项 PRD …`、`#82` = `* fix(82): 立项三项 …` —— 属「历史 bullet」但不含被证伪表述；`#84` = `* fix(84): 立项测试用例与宿主窗口解耦…` —— **这一条才是被证伪的旧表述**。故「body 首行不得是被证伪的旧表述」这条判据在 #80/#82 上是**空的**，只在 #84 上有实义。

## 三、口径条文可执行性（`github-flow.md` + `checklists/pm.md`）

- 可执行部分：`gh pr merge <n> --squash --delete-branch --subject … --body-file <文件>` 明确；取描述的命令给了；判据 `%s` 与 `%b` 各 `grep -c 'wip('` = 0 两条都写到了（#84 的实测正是「subject=0、body=6」，只查 subject 会漏 —— 条文已覆盖）。
- 两处需要补一句（P3，见下）：① `grep -c` 在 0 命中时 **rc=1**，`set -e`/`&&` 链里会把「通过」读成失败；② 「body 首行不得是被证伪的旧表述」不可机械判（人工/judgement 项，应标明）。

## 四、缺陷与观察（全量入库）

**P2-1 · 重试在「非零退出 + 零 stdout」支上可把真故障洗成绿（AC2 该支未过）**
证据见 §一 AC2。影响：① 与 AC2 逆向；② 实际风险面窄（要求首次快速失败且无输出、第二次成功），但本批全部价值都在「不吸收真故障」，此洞留着等于口径自相矛盾；③ 修法成本极低（1 个判据 + R3 改钉 + 2 条断言）。

**P3-1 · `cases/02` 的 SKIP 文案丢了 rc/字节数**：原为 `pi 未成功启动或无输出（rc=7，stdout=0B）`，现为 `pi 未成功启动或无输出`;数字只在 info 行。可接受（同一输出流紧邻），但 grep `SKIP:` 的人会少一层信息。

**P3-2 · 断网时门禁最大耗时上升**：首次 120s + 重试 180s = 每轮最多 300s（dual 两轮 +10 分钟）。属可接受成本，建议在 `tests/README.md` 记一笔（当前未写）。

**P3-3 · `T4_PI_SMOKE_INFO` 是全局但在 `cases/02` 里由子 shell 调用**：全局变量不会传回调用方；注释「子 shell 调用也不丢」实际指的是 info **行**（stdout），易被未来的调用方误读成「拿得到全局」。

**P3-4 · `cases/26` R5 的两条默认值断言是静态文本匹配**（`T4_PI_TIMEOUT:-120` / `T4_PI_RETRY_TIMEOUT:-180`）：注释里出现同样字面量也能满足；默认值本身无法功能验证（120s 太慢），属可接受代理，建议注释说明「静态代理」。

**P3-5 · 口径判据的两个可执行性缺口**：见 §三（`grep -c` 的 rc=1；「首行旧表述」不可机械判）。

## 五、结论与条件

- **CONDITIONAL GO（0 P1 / 1 P2 / 5 P3）**。
- 条件（P2-1）：判据收成 `rc1=124 || (rc1=0 && b1=0)`，`cases/26` R3 改钉 + 补「非零无输出 ⇒ 不重试照原样判」与「首次非零失败 + 第二次成功 ⇒ 仍 4」两条断言；改完 QA 只需复跑 `--case 26` + `npm test`（约 3 分钟）即可闭合，不必再跑 dual。
- P3 全部不阻断；P3-1/P3-3 可随 P2 同批顺手，P3-2/P3-4/P3-5 转办下批（到期 2026-12-05）。

## 六、复行（round 2 · 基线 `4b2b6c9`）

RD 按 P2-1 改了判据并补测，QA 逐条复跑（未再跑 dual，按 PM 指示）。

**P2-1 — 已闭合**。判据现为 `rc1=124 || (rc1=0 && b1=0)`。QA 用**同一条洗白桩**复现：首次 `exit 7` + 0 字节、第二次本会成功 ⇒ `pi-smoke: attempt1 rc=7 bytes=0 · attempt2 rc=- bytes=- · retry=no`、**返回值 4、实际调用 1 次**（改前是 `0 / 2 次`）⇒ 洗白路径已封。`cases/26` R3 已反钉（非零 + 0 字节 ⇒ 1 次、rc=4），新增 R3b（`rc=0 && 0 字节` 仍重试）与 R2b（首次非零失败 + 第二次本会成功 ⇒ 不重试、仍 4）。

**新断言非空转（四组变异，全部精确翻红）**：M4「退回修前宽松判据」⇒ 5 红，正是 R3（`期望=1 实际=2`）+ R2b（`期望=1 实际=2`、`真故障不被重试洗成绿（期望=4 实际=0）`）；M1「放宽成任何非 0 都重试」⇒ 8 红（含 R2/R3/R2b）；M2「只声称重试、实际不再调用」⇒ 7 红（含 R3b `期望=2 实际=1`）；M3「info 谎报 retry=no」⇒ 2 红（R1/R3b）。⇒ 收严后的两条新断言与既有断言都吃真实计数/真实 info。

**P3-5 / P3-3 / P3-2 / P3-4 — 已落实**：`grep -c` 判据已统一 `|| true` 并注明「0 命中 rc=1」（QA 实跑：裸用 rc=1、加 `|| true` 后 rc=0）；「body 首行旧表述」已标**人工项**；`tests/README` 已记重试成本边界与 R5 静态代理性质；`lib.sh` 注释已改为「info 行是子 shell 下的唯一可靠出口」。

**P1-1（新发现 · 阻断）· P3-1 的修复引入了「SKIP 变 FAIL」回归**

- 现象：`cases/02` 的两条 `t4_skip` 文案现在插值 `$T4_PI_SMOKE_INFO`，但该用例是在**子 shell** 里调用 `t4_pi_smoke`（`( cd "$fx" && t4_pi_smoke … )`），函数内设置的全局在父 shell 不可见；`lib.sh` 是 `set -u` ⇒ 展开未绑定变量即中止用例。
- 实测（两条 SKIP 分支都中）：假 `pi`（`rc=7` + 20B / `rc=7` + 0B）⇒ `tests/t4/cases/02-skill-registration.sh: 行 75: T4_PI_SMOKE_INFO: 未绑定的变量`，用例 rc=1，套件 `02  FAIL`（改前应 `SKIP`）；假 `pi`（`No API key` + `rc=2`）⇒ `行 72: T4_PI_SMOKE_INFO: 未绑定的变量`，同样 FAIL。
- 影响：**只要 pi 不可用（断网 / 重试后仍超时 / 无凭据），门禁由 SKIP 变 FAIL** —— 正是本批要消灭的那类假红，而且更硬（SKIP 在 full 轴才判红，FAIL 任何模式都红）。网络正常时该路径不被触发，因此在本地 `npm test` 与 dual 里**看不出来**（本轮即如此：955 断言全绿）。
- 建议（缺陷，不改代码）：① `lib.sh` 顶层初始化 `T4_PI_SMOKE_INFO=""` 兜底（防中止）；② 让父 shell 真拿到内容 —— 例如 `cases/02` 去掉子 shell（`pushd` 后调用）或让 `t4_pi_smoke` 另写一份 info 到调用方指定的文件；③ **补一条 wired 负控**：假 `pi` 恒失败时 `cases/02` 必须 `SKIP`（而非 PASS/FAIL）—— 这条测试正是缺的那道闸，能挡住本次回归。

**门禁（复跑）**：`check` rc=0 ×2（`roles=7 · files=54`，逐字一致）· `npm test` rc=0 · 用例 **25** · 断言 **955** · `SKIP=0 · DEGRADE=0 · NOTE=2`（白名单 `06:static-contract` ×2）—— 与 PM 自证一致。

**复行结论：CONDITIONAL GO 未闭合 —— 新 P1-1 阻断合并**（P2-1 已闭合）。P1-1 修法 3 行以内 + 1 条 wired 负控；改完 QA 复跑 `--case 02`（假 pi 两态 + 无凭据态）+ `--case 26` + `npm test` 即可。

## 七、终审（round 3 · 基线 `41b5836` = `7a53799` 修复 + PM 台账 `41b5836`）

**P1-1 — 已闭合（四态实测）**

- 修复形态核对：`lib.sh` 顶层 `T4_PI_SMOKE_INFO=""`（`set -u` 兜底）+ `printf … > "${err}.info"`（给子 shell 调用方的**文件通道**）；`cases/02` 改为 `pi_info="$(cat "$ef.info")"`，不再插值全局（注释同时写明「勿插值全局」）。
- 四态自跑（用例脚本级，假 `pi` 走 `PATH` 前置）：

  | 态 | 用例 rc | SKIP 文案 |
  | :-- | :-- | :-- |
  | 真跑（真 `pi`） | 0（`PASS`，`attempt1 rc=0 bytes=185335`） | — |
  | 恒失败 + 有输出（`rc=7`/20B） | **77** | `pi 未成功启动或无输出（pi-smoke: attempt1 rc=7 bytes=20 · attempt2 rc=- bytes=- · retry=no）…` |
  | 恒失败 + 无输出（`rc=7`/0B） | **77** | `…（attempt1 rc=7 bytes=0 · attempt2 rc=- … retry=no）…`（未重试，符合收严判据） |
  | 无凭据（`No API key`/rc=2） | **77** | `pi 无可用凭据（No API key；… retry=no（no-api-key））…` |

  ⇒ 三条 SKIP 路径都不再中止，且 SKIP 文案带上 rc + 字节数（数据来自 `$ef.info`）。

**R6 wired 负控 — 非空转（QA 独立两组变异）**

- **M6「回退 P1 的两处修复」**（删顶层兜底 + `cases/02` 改回插值全局）⇒ `cases/26` rc=1、**4 红**，其中三条是**行为级**：`R6① 期望=77 实际=1`、`输出含 SKIP:` 缺失、`无 set -u 未绑定变量中止` 命中；另一条是 `R5` 静态断言。⇒ 本次 P1 若再犯，会被当场打红。
- **M5「只删 info 文件通道」**（`> "${err}.info"` 改成 `:`）⇒ **只有 1 红，且是 `R5` 静态断言**；`R6①` 那条「SKIP 文案带上 rc + 字节数」**仍是绿的** —— 因为该断言查的是**整段用例输出**，而 `-- pi-smoke: …` 那行本来就在输出里，所以它证明不了「数据通道」工作（见 P3-1）。

**门禁（终审自跑 · 串行）**：`check` rc=0 ×2（`roles=7 · files=54 · layout=main-row2`，逐字一致）· `npm test` rc=0 · 用例 **25** · 断言 **967** · `SKIP=0 · DEGRADE=0 · NOTE=2`（白名单 `06:static-contract` ×2）· `[FAIL]` 0 条 · `--case 02` 真跑 PASS · `--case 26` 43 断言全 PASS。断言数演进：949（round 1）→ 955（round 2：R2b/R3b）→ **967**（round 3：R6 九条 + R5 三条）。`main...HEAD` 对 `.agents/scripts/`、`bin/`、`package.json`、`roles.yaml`、`prompts/` **0 行**改动；`41b5836` 为 docs-only（`tasks-state` 1 行）；零敏感值。

**P3-1（新 · 不阻断）· `R6①` 的「SKIP 文案」断言精度不足**

- 现状：`t4_assert_contains "$C02_OUT" "rc=7 bytes=20"` 对整个输出断言，`-- pi-smoke:` 行即可满足 ⇒ 数据通道断了也绿（M5 实证）。
- 影响：真正的 P1 回归仍会被另外两条行为断言（`rc=77` / `无未绑定变量`）抓到，故不阻断；但「SKIP 文案带 rc/字节」这条**声明与实际判据不符**（声明比实际强）。
- 建议（缺陷，不改代码）：断言改为**只看 SKIP 行**（`printf '%s\n' "$C02_OUT" | grep '^SKIP:'` 再 `contains`），或加一条「断言里不得出现 `pi-smoke:` 之外的来源」；`R6②` 的 `no-api-key` 同理（它恰好只出现在 SKIP 行，风险较低）。

**终审结论：GO（0 P1 / 0 P2 / 1 P3 观察 · 不阻断合并）。** P3-1 建议随下批（或 PM 若愿意，可在合并前让 RD 顺手 1 行改断言；QA 复跑 `--case 26` 约 20 秒即可）。
