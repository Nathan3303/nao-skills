# #82 三项 #80 遗留（孤儿卡假绿 / 布局容量判据 / 夹具并行踩踏）—— QA 非作者复核

- 状态：**GO（0 P1 / 0 P2 / 3 P3 · 可授权合并）**
- 更新：2026-11-05 · Owner：qa · 分支 `fix/82-legacy-cleanup` · 复核 HEAD **`e49ed2c`**（本报告落盘前）
- 指针：Issue [#82](https://github.com/Nathan3303/nao-skills/issues/82)（B 项前提已由 PM 回帖订正）· PR [#83](https://github.com/Nathan3303/nao-skills/pull/83)（Draft）· 变更 7 文件 `+233 −4` · 台账 `docs/tasks-state.md` 首行
- 口径：**全部数字自跑**（不抄 RD/PM）；实现零改动（本批只动测试与文档）⇒ 「单条 revert」成立。

## TL;DR

- **A 孤儿卡 = 过**：真清单断言 + 4 类漂移负控；**独立构造**（`/tmp` 副本摘 `uiux-designer` 条目）⇒ **恰 3 条 FAIL**，与 PM 自跑一致；复位态绿由用例内 `A: 复位后断言复绿` 覆盖。
- **B 布局 = 过（RD 前提成立）**：静态 `n = ${#pane_ids[@]}` 取自 `tmux list-panes -t "$HOST_WINDOW"`（`nao-fleet.sh:978–983`）· 活体自测 **183 列 warn=1 / 184 列 warn=0**、两档均 **8 pane** ⇒ 守卫本就按「角色数 + 调用者」计，Issue 原表述有误；本批补断言是**最小正确改动**。
- **C 夹具 = 过**：新默认 `mktemp -d` ⇒ 并发两组 `--case 12` **均 PASS**、`/tmp/t517*` 零残留；显式 `T517_LAB` 复用旧路径并发 ⇒ **两组均 FAIL**（先红证据成立）。
- **`cases/25` 不空转（自造变异验证）**：我自己把 `n` 改成 `pane_ids-1`（模拟「只数角色」）⇒ 该用例 **2 条点名 FAIL**；M1 数学（137/184/184/230）由真脚本函数实跑得出。
- **发布说明回填 = 过（独立实测）**：`dist-tags.latest` = `0.22.0`；仓库同 tag 本地 `npm pack` = **168,344 B**、`sha512` 与 registry `dist.integrity` 及文档声明**逐字节一致**。
- **门禁（自跑串行）**：`check` rc=0（roles=7 · files=54 · 2 次同输出）· `npm test` rc=0（**24 例** / **900** 断言 = #80 的 868 **+32**：`cases/06` +11、`cases/25` +21）· `test:t4:full:dual` rc=0（组1 / 组2 均 rc=0 · SKIP=0 / DEGRADE=0 / 非白名单 NOTE=0）。

## 一、A 孤儿卡（`cases/06` 真清单断言）

- 正向（清白清单）10 条断言全 PASS；`t4_info` 打印 `真清单：7 个角色 · problems=无`。
- **独立负控 1**（摘 `roles.yaml` 的 `uiux-designer`）⇒ `RESULT: FAIL (3 项断言未过)`：
  - `A: 真 roles.yaml 与卡集一致…（实际=角色数=6（期望 7）` + 三行明细（角色集不一致 **点名 uiux-designer** / 别名=<空> / `uiux-designer.md：卡存在但 roles.yaml 未登记（孤儿卡）`）
  - `A: 真清单下 check 报 roles=7（未包含: roles=7）`
  - `A: 复位后断言复绿`（见 P3-1：该条在真清单漂移时标签误导）
- **独立负控 2**（删别名 `uiux`）⇒ 2 条 FAIL，文案**逐字点名**「别名=ui-designer,uiux-designer（期望 uiux,ui-designer,uiux-designer）」。
- **独立负控 3**（新增未登记卡 `stray-role.md`）⇒ 3 条 FAIL，点名「stray-role.md：卡存在但 roles.yaml 未登记（孤儿卡）」⇒ **card↔roles 反向也真敏感**。
- **独立负控 4（格式漂移）**：`aliases: [...]  # 尾注` 与多行 `aliases:` 列表两种变体 ⇒ `check` **rc=1** 并点名「行 N: 缩进/位置非法」，`cases/06` 各 3 条红 ⇒ 清单格式严格性与文件头约定一致，宽松正则**不产生假绿**（不是漏报）。
- 断言用的是**先快照再变异**的夹具副本，且期望集 `MANIFEST_EXPECT` 显式钉住（不从清单自推）⇒ 摘条目后不会「自洽空转」，这点是对的。
- **`check` 保持 rc=0 + warn 是否可接受 = 我的意见：接受**，理由三条：① `check` 同时服务下游项目，孤儿卡只意味着「文件没被引用」，运行期无影响，改成 error 会让「升级后删卡」这种正常操作硬失败（rc≠0 ⇒ 文档口径要求停止派发）；② 真正会坏的两类（canonical 未登记于 aliases、卡文件缺失）已是 error（实测：`card: ghost.md` ⇒ rc=1 + 2 条命名错误）；③ 机制包自身漂移的执法点放**测试**更合适（本批 `cases/06` 已补）。可选加固：给 `check` 加 `--strict-manifest` 开关而非改默认语义。

## 二、B 布局容量（静态 + 活体 + 自造变异）

- **静态**：`apply_tmux_layout()` 里 `n` 唯一来源 = `tmux list-panes -t "$HOST_WINDOW" -F '#{pane_id}'`（`nao-fleet.sh:978–983`），随后 `main_row2_min_col "$win_w" "$n" "$pct"`；`apply_tmux_layout` 内 `ROLE_ORDER` 出现 0 次 ⇒ **RD 的前提订正成立**，Issue 原文「按角色数算」是误判。
- **活体（我自己搭探针，不用 RD 用例）**：7 目标 `ensure` ⇒ 8 pane；`183` 列 `warn=1` 且回落 main-col（右列 122×4/5）；`184` 列 `warn=0`、main-row2（60 主 + 4 列 30 宽）。与 `cases/25` M2 与 M1 数学三方一致。
- **自造变异**（注入点与用例 M3 不同：改 `n` 的**来源**，而非守卫实参）：`.agents/scripts/nao-fleet.sh` 的 `local n=${#pane_ids[@]}` → `$(( ${#pane_ids[@]} - 1 ))` ⇒ `cases/25` **FAIL 2 条并点名**：`M2: n=8 @183 列 ⇒ 出「回退 main-col」warn（按 8 计，非 7）`、`M3: 变异后判定与真脚本不同`。⇒ 断言对「按角色数算」这类回归**真敏感**，非空转。
- 结论：B 结案为「补回归断言」正确且最小；B-2（按最终 pane 数预判、消除中途布局切换）不夹带合理，但注意 `cases/25` 已把「183 warn / 184 不 warn」固化为契约，将来做 B-2 必须同步改 M2 与 `cases/12` 冻结点（PM 已在台账记）。

## 三、C 用例 12 夹具并行

- 改动：`LAB="$(mktemp -d "${TMPDIR:-/tmp}/t517-reg.XXXXXX")"`（显式 `T517_LAB` 仍可覆盖）；收尾仍走机制 `cleanup -S` + `rm -rf "$LAB"`。
- **并发（新行为）**：两个 `bash tests/t4/run.sh --case 12` 同时跑 ⇒ A/B **均 `RESULT: PASS`**、`/tmp/t517*` **零残留**。
- **并发（旧行为复现）**：`T517_LAB=/tmp/t517-old` 两组同时跑 ⇒ **两组 rc=1**，失败形态与 #80 观测同型（`AC7② 隔离 server 创建失败` / `AC7① 派生落点不一致`）⇒ 先红证据成立，且证明确实是**目录撞车**而非 socket 隔离失效。
- 残留：可执行进程与目录均无；唯一已知边界 = `SIGKILL` 下 `mktemp` 目录会残（与旧固定路径同型，正常 EXIT 已清）。

## 四、P3（建议下批或随手改，均不阻断）

- **P3-1 `cases/06` 内部负控与真清单耦合**：负控先用「真清单副本」再造变异。当真清单本身漂移（正是本断言要抓的场景）时，`A: 复位后断言复绿` 与 `A 负控：check 只降到 warn=1` 会各自多出/误报一条（实测孤儿卡场景：`warn=2` ⇒ 该条 FAIL），标签读起来像「用例自身坏了 / check 语义不对」。有效信息是第一条。建议：负控夹具改为**自包含**固定清单（同 `cases/09` 写法），或复位从「变异前快照」`cp` 回、`warn>=1` 断言。
- **P3-2 `cases/25` M1 与脚本默认值双源**：M1 从真脚本抽函数（好），但 `pct=33` / `min=30` 是重敲的字面量；将来改默认值会出现「公式对、断言红」的困惑。建议 `grep '^TMUX_MAIN_WIDTH_DEFAULT=' / '^TMUX_MIN_PANE_WIDTH_DEFAULT='` 抽取后传入。
- **P3-3 Issue #82 标题未订正**：标题仍写「布局守卫未计入调用者分屏」（B 前提已证伪，仅评论订正）。建议改标题或 close 时一句说明，避免后来者按标题误解。

## 五、门禁与数字（串行自跑）

- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=7 · files=54 · layout=main-row2` · **rc=0** · 两次输出 `diff` 为空
- `npm test` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2）` · **rc=0** · 用例 **24** · 断言 **900**
- `npm run test:t4:full:dual` → **rc=0** · `组 1（保留 TMUX_PANE）rc=0` · `组 2（env -u TMUX_PANE）rc=0` · 每组 SKIP=0 / DEGRADE=0 / 非白名单 NOTE=0（2 条均 `06:static-contract`）
- 断言增量核对：`900 − 868 = 32` = `cases/06` +11 + `cases/25` +21（逐例 PASS 行计数一致）
- `git diff --shortstat main...HEAD` → `7 files changed, 233 insertions(+), 4 deletions(-)`（本报告为第 8 个文件）
- 敏感值：diff 内 JWT / 绝对家目录路径 = **0**；未读未抄 `.pi/mcp.json`
- 环境抖动：本轮 `npm test` 首跑即 `SKIP=0 · NOTE=2`（未命中 `07:pin-fallback`），无重跑需求

## 六、未做与边界

- 未改实现、未改 `cases/12` 断言、未 push、未合并；本报告为唯一新增文件。
- 清单解析器（`manifest_tsv`）是宽松正则，但**格式纪律由 `check` 兜住**：尾注/多行别名会被 `check` 判「缩进/位置非法」rc=1（§一负控 4）⇒ 不存在「测试宽松放过、运行时也放过」的组合。
- 未覆盖：`roles.yaml` 之外的角色来源（下游项目自有清单）不在本用例面——机制包侧才是执法对象，符合 `tests/README` 既有边界。
