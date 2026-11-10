# #96 步 2a 交接口径：舰队命名契约（BR8）

> 来源：arch-designer 窄设计（2026-11-10）· PM 六项裁定 D1=P1 显式 scope / D2 `fleet-scope` 文件 + `--scope` / D3 `@` / D4 冲突 fail loud / D5 AC 双签 / D6 名册同名守卫。
> 用途：rd-infra 实现清单。**行号以 `main@2692b42` 为准，定位以函数名为准。**
> 本文件不含实现代码，只含契约、必改点与判据。

## 0. 契约（唯一事实）

- **名字**：`<core>[@<scope>]`；`core` = `<role>[-<task>]` 或 `<card_role>[-<task>]`
- **scope**：`^[a-z0-9][a-z0-9_-]{0,15}$`（≤16、尾非 `-`、禁 `subagent-` / `nao-` 开头、禁 `@` `.` `:` 与空白）；**scope 空 ⇒ `@` 整段不出现**
- **预算**：card core ≤32（沿用现行）· 总名长 ≤48
- **四个符号**（单一实现点，须可独立抽取单测 ⇒ 加起止标记注释）：
  - `fleet_name_build <kind> <core> <scope>`
  - `fleet_name_parse <name>` → `OK kind,role,task,scope` | `ERR`
  - `fleet_scope_slug <repo>`
  - `fleet_scope_of_invocation <target_repo> <cli_scope>`
- **硬约束**：① 名字 = 路由标签，**不作身份证明** ② `parse` 必 total（全输入有定义结果），**禁 `#${role}-` 切片** ③ 可换面仅后两个符号 ④ **语法冻结** ⑤ builder 之外禁名字拼接

## 1. 构造侧（2 项，合并进 `fleet_name_build`）

- **B1** `cmd_ensure`（`:2101,2103` + `:2124-2125`）：相位 1 卡名 `disp`、相位 2 `disp="${t_names[$i]}"` + `-${task}` ⇒ 删两处手写拼接改走 builder；scope 在**相位 1** 由 `fleet_scope_of_invocation "$CARD_REPO"/"$repo" "$CLI_SCOPE"` 一次算入 `t_scopes[]`，相位 2 **禁重算**。
- **B2** `cmd_close`（`:1906-1907` + `:1912-1913`）：重建名三处 ⇒ 走 builder。**scope 来源分歧**：`$target` 含 `@` ⇒ 用 parse 出的 scope（忽略文件）；否则用目标仓的 invocation scope（裸别名 = 调用者所在仓）。

## 2. 解析侧（11 项必须改）

- **P1** `:1753` status 常驻/派生切分（`[[ "$dname" == "$role-"* ]]`、`id="${dname#"$role"-}"`）⇒ 先 `fleet_name_parse`，用返回 role/task 替代前缀切片；card 或 ERR 才落原 `id=""` 分支。
- **P2** `:1756-1761,1771-1773` status 卡集最长前缀 + `suff` ⇒ 同上，role/suff 一律取自 parse，禁再对 `$dname` 做前缀比较。
- **P3** `:1792,1795-1798,1811,1815-1818` `task_state_class` + 四类 tag 里的 `${dname%-"$id"}` ⇒ 分类输入改 parse 的 task；回收命令里的角色名改用 parse 的 core（现尾剥法带 scope 时剥错）。
- **P4** `:1865-1901` close 目标解析五级 ⇒ 头部加一步 `fleet_name_parse "$target"`：命中直接用 `(role,task,scope)`；不命中走原五级；多 scope 可命中且无法定 ⇒ die 列候选。
- **P5** `:706-712` `derived_in_field`（`"$1"-?*`）⇒ 比 **core**：候选 parse 后要求 role==`$1` **且** scope 一致；否则他仓派生被算本仓（T516 AC3 误拒复发）。
- **P6** `:739` `visible_session_names` 标题正则 `\([A-Za-z0-9_-]*\)` ⇒ 字符集加 `@`。**不改则带 scope 会话在 status 里整条消失（已实测）**。
- **P7** `:1463` `pane_cwd_snapshot` 名字正则 `name !~ /^[A-Za-z0-9_-]+$/` ⇒ 同上加 `@`。**不改则 pane cwd 归属层丢会话 ⇒ 归他仓/unknown**。
- **P8** `:504-516` `intercom_cwd_for` 首命中 ⇒ 增可选第 2 参 repo：只返 `cwd==realpath(repo)`；调用点 `:1909`、`:1914` 必须传目标仓。
- **P9** `:1524-1546` `card_name_problem`（整名校验）⇒ 改校验 **core**（≤32 / 保留前缀 / 撞常驻）+ scope 校验（字符集 / ≤16 / 尾 `-` / 禁 `@`）+ 总长 ≤48 单判。
- **P10** `:2093-2100` `--as` 命名契约 + D9 前缀 ⇒ 校验对象改 core；`--as` 含 `@` ⇒ 显式 die（scope 只能 builder 追加）。
- **P11** `:724-734` `running` 二态 ⇒ 改三态 `running_verdict → same|conflict|absent`；调用点 `:2130` 改分支：`same` ⇒ 跳过（现文案不变）/ `conflict` ⇒ **die + 指路** / `absent` ⇒ 拉起。

## 3. 不变量（不改代码，但漏守会复发已修缺陷）

- **N1** `find_pane_by_title:518-529` 不用改，但**入参必须完整名**，且**禁**再用 basename 单独定性（同 basename 两仓已实测互串）。
- **N2** `session_repo_verdict:1472-1498` 保持现状（pane > 名册、fail-closed）；scope 可收紧文案，**不得**取代三态判定。

## 4. 文案/文档（6 处）

- **D1** `:16` `--name <别名>-<编号>` ⇒ 补 `[@<scope>]`（scope 见 `--scope` / `.agents/fleet-scope`）。
- **D2** `:17-19` `--card` 三行说明 ⇒ 补「`--as` 只给 core；`--scope <slug>` 覆盖 `<目标仓>/.agents/fleet-scope`；名字 `<role>[-<task>][@<scope>]`」。
- **D3** `:24` `close <别名|派生会话名>` ⇒ 加「全名」+ 注「裸别名 = 调用者所在仓 scope；`@` 全名忽略文件」。
- **D4** `:1902` die「派生名形如 `rd-be-T1` …」⇒ 增「全名形如 `rd-be-T1@todo`」+ 本仓 scope 现值（或「未设」）+ 多 scope 候选。
- **D5** `:1720` status 分节标题示例 ⇒ `rd-be-T1 / rd-be-T1@todo`；scope 非空时行尾追加 `·scope=<x>`（**只加字段、不改既有行格式**，否则 C2 崩）。
- **D6** `README.md` 角色段 + `.agents/common/intercom-protocol.md` 寻址示例 + `docs/INSTALL.md` ⇒ 补 §0 契约块 + 一句「两仓并发必须设 scope，否则 `ensure` fail loud」；细节只写一处其余给指针。

## 5. scope 优先级与错误行为（全部 fail loud）

- **优先级**：`ensure --scope` > `<目标仓>/.agents/fleet-scope` > 空。读取对象 = **目标仓** realpath（`--card …@repo` 取卡的仓），**不是**调用者 cwd；`status` 不读文件（从名字 parse）。
- 文件不存在 ⇒ 空、**静默**（BR1 全靠这条）。
- 存在但非普通文件 / 不可读 ⇒ die；symlink 逃出仓（`nao_phys_path` 不在 repo 前缀）⇒ die（同卡边界口径）。
- **空文件 / 仅空白 ⇒ die**（「声明了却没值」，静默回落会把 typo 变成静默撞名）。
- 多行 ⇒ die（歧义）；CRLF ⇒ 剥 `\r` 后校验（不因 EOL 拒绝，EOL 归 `check`）。
- 非法字符 / `@` / `.` / `:` / 空白 / 超 16 / 尾 `-` / 首字符非 `[a-z0-9]` / 保留前缀 ⇒ die + 回显规则。
- `--scope ""`（给参但空）⇒ die（照 `--task` 先例）。
- `--scope` 与文件并存 ⇒ `--scope` **静默胜出**（覆盖语义），来源仅 `-v` 打印。
- **`fleet_scope_slug` 规格（防 worktree 分裂，已实测）**：`slug = basename(dirname(realpath(git --git-common-dir)))`，非 git 仓用 `realpath(repo)` 的 basename；再 lowercase / 非 `[a-z0-9]`→`-` / 压缩 `-` / 去首尾 / 截 16 / 空则 `repo`。**用 `--show-toplevel` 会在 worktree 分裂**。

## 6. 判据（C1/C2/C3）

**C1 codec 恒等**（纯函数、不启 tmux）四组断言：
- ① 字面量恒等（scope=""）：常驻 7（`pm` `arch-designer` `uiux-designer` `rd-fe` `rd-be` `qa` `rd-infra`；别名 `arch`/`uiux`/`ui-designer`/`infra` 须先 `resolve_role` 成 id，**不得输出别名**）；派生 5（`rd-be-T1` `qa-T508` `arch-designer-96b` `pm-M20261109-queue-slim` `rd-infra-M20261014-pi-ext-update`）；卡 3（`sec-review` `sec-review-T42` `sec-review-notes`）
- ② 往返：`parse(build(x))` 回原 `(kind,role,task,"")`
- ③ 语法钉住：scope=`todo` ⇒ `sec-review@todo` / `sec-review-T42@todo` 精确相等
- ④ parse 全函数（全 ERR）：`rd-fe@` `@todo` `rd-fe@@todo` `rd-fe@TODO` `rd-fe@a.b` `rd-fe@:x` `rd-fe@`+17 字符 `subagent-x@y` `nao-x@y` 48+ 字符名
- 变异负控（不红 = 用例无效）：M1 尾追加 `-x`；M2 丢 task；M3 parse 改切片；M4 非法输入返猜测值

**C2 golden diff 空**：
- fixture `tests/t4/fixtures/nao-fleet-baseline-2692b42.sh` = **改动前** `git show 2692b42:.agents/scripts/nao-fleet.sh` + 10 行头注释（照 `nao-fleet-baseline-2b4ade3.sh` 格式）。
- **必须在动脚本之前生成**（否则自等价，case 19 的 P3-1 护栏会打 `baseline-selfequiv`）。
- 比**两样**（同套隔离夹具：`env -u TMUX -u TMUX_PANE` + 私有 `TMUX_TMPDIR` + pi 桩，照 case 22）：① `status` 全文 md5（只比名册正常路径，同 case 19 口径）② `ensure` 的 `[tmux] 已拉起 …` 行 + pi 桩 argv 里 `--name` 值，拼接后 md5。目标集 9 个（7 常驻 + `--task T1` + `--card`），**全不设 scope**。
- **不许动** `2b4ade3` fixture 与 case 19（它自动成为 status 零回归的第二重见证，红了即证明漂移）。**不比断言总数**。

**C3 单写点 lint**（新用例 `28-naming-contract.sh`，tmux 后端；herdr 登记留步 2b 之后的批，不夹带）：
- ① `grep -c 'exec pi --name' == 1`
- ② 契约函数体外正文 0 命中 `(name|disp)="?\$\{[^}]+\}-\$\{?(task|TASK)`
- ③ `grep -c fleet_name_parse` ≥ 11（11 解析点全接线）
- 负控：close 里手写 `name="${NAME}-${task}"` ⇒ ②红；删任一 parse 调用 ⇒ ③红
- 门禁：`check` rc=0 + `npm test` rc=0 + C1/C2/28 全绿

## 7. BR8 定稿（可入 PRD）

**BR8 命名契约**：舰队会话名统一为 `<core>[@<scope>]` —— `core` 为 `<role>[-<task>]` 或 `<card_role>[-<task>]`，`scope` 为仓级命名空间 slug，**末位、`@` 分隔、非空才出现**（为空时名字与改动前逐字相同）；名字由唯一一对纯函数（build/parse）生成与解析，所有构造/解析点必须经该函数，语法冻结，二期只允许替换 scope 的来源与归一化实现；**名字是路由标签，不作身份证明**。

## 8. AC 文案（D5 双签结果，PM 已签）

- **AC1.6 Then** 改为：「scope 不同 ⇒ 各自可见；相同/未设 ⇒ 第二仓 **fail loud**（列候选与改法）」。
- **AC1.2** 保留原文，并把对照对象明确为「**scope 为空时**」。
