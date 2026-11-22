# T554 · 舰队模型 v2：workspace 为绑定单位（lite 判据）

- 状态：已核可（D1–D8 已拍板）· v2 增量待核 · 更新：2026-11-21 · Owner：arch-designer · 修订：v2（D1/D2/D5 + 用户括号格式）
- 指针：Issue [#554](https://github.com/Nathan3303/nao-skills/issues/554) · PRD `docs/prds/2026-11-20-fleet-model-v2.md` · ADR `docs/adr/2026-11-20-workspace-as-binding-unit.md` · 骨架 `docs/reports/146-arch-lite.md`
- 代码（禁 cat 全文；行号随 HEAD `f436ed7` 漂移，按符号定位）：`fleet_core_build:1883` · `fleet_name_build:1897` · `fleet_name_parse:1917` · `fleet_scope_slug:1958` · `fleet_of_invocation:1991` · `fleet_scoped_candidates:2820` · `_term_herdr_require:461` · `_term_herdr_exec:430` · `_term_herdr_spawn:1120` · `_term_herdr_tab_id_for:1002` · `cmd_close:4385` · `cmd_cleanup:4667` · `cmd_ensure:4672`

**结论：有条件可行**（条件 = §二 通道 + §三 各态断言 + §四 迁移清单）。改动面 = 放置键来源、名字契约 v2、`default` 守卫分级、manifest 收窄；`close` 归属判据（anchor + pane cwd）不动。有结构性决策 ⇒ ADR 见上；本报告只放判据，不放闸门清单。
## 一、判据句（新契约，逐条可断言）

1. **放置键 = 仓**：workspace label = 仓基键（`place_key_label`：git common-dir 父目录名 / 非 git = 目录名，归一 `^[a-z0-9][a-z0-9_-]{0,15}$`）；两仓同基键 ⇒ 后者 `<key>2`…`<key>9`，全占 ⇒ die。名字**不含位置**（`@` 段删除）。
2. **名字文法（新形）**：常驻 = `<role>[<N>]`；派生 = `<role>[<N>](<task>)`（task 在括号内、紧贴角色名，**N 在 `(` 之前**）；`N ∈ {2..9}` 单字符；role = 事实表**最长匹配**；task = `^[A-Za-z0-9_-]+$` 逐字入括号（`T` 是任务号自带的约定前缀，格式不另加）；name ≤48，role 段（含 N）≤32（卡）；`--as` 只给常驻形（`<role>[<N>]`）或旧形自定义后缀（起得来、按 legacy 只读解析），带 `()` 即 die（指路 `--task`）。
3. **歧义边界（两条反例）**：① `rd-be2(T553)` 唯一分解 = `rd-be` + 槽位 2 + task `T553`；若把 N 放到 `)` 后（`rd-be(T553)2`）就与「task 尾部数字」不可区分 ⇒ 该串按文法直接 ERR（不以 `)` 结尾），故 N 只能在 `(` 前。② 新形 `rd-be(T553)` 与旧形 `rd-be-T553` 是不同字符串：parse 按**首个分隔符**分派（`(` ⇒ 新形 · `-` ⇒ 旧形只读 · `@` ⇒ legacy scope），三集合不相交；`qa-2` 仍是旧形任务号 `2`，`qa2` 是槽位 2。
4. **N = 角色槽位**：同 ws 内槽位已占 ⇒ 取最小空闲 2..9；派生复用同一槽位号（`pm2(T554)` = 槽位 2）；同槽位同 task 已在 ⇒ same（跳过），要第二个并发者才递增槽位。跨 ws 同名允许；`<role><N>` 撞注册角色 id ⇒ 跳过；全占 ⇒ fail loud 指路 `close`；`pm1`/`pm0`/`pm10` 与不配对括号结构上不可解析（N>9 必 fail loud）。
5. **`ensure <role>@<code>`**：`@` **只选目标仓**（manifest `code` / 既有仓路径），不进名字；code 未命中 / manifest 非法 ⇒ fail loud 列可用 code + `文件:行号`，零 pane。
6. **`default` 等价**：`ensure` / `status` / `close` / `cleanup`（herdr `--session default` / tmux `-S default` 生产 socket，内部含 `session stop default`）均放行；唯一差异 = 破坏性动作打印影响面（§三 S8–S10）。
7. **历史形态**：解析保留 **legacy 读模式**（旧形 `<core>[-<task>][@<scope>]`）—— 仅 `status`/`close` 接受，`ensure` 的自动命名永不生成（`--as` 为用户显式名，旧形按只读解析）；`close` 依次试新形精确名 → 由 role+task 重建的新形 → 旧形（AC6）。
## 二、数据通道（派单 ①）

- **放置键**：`place_key_label <repo_phys>`（原 `fleet_scope_slug` 改名，单一实现）→ stdout 恰 1 行；空输出 = 实现缺陷 ⇒ die（**禁** rc / 空行承载「不可知」）。冲突号来自 `workspace list` **一次**快照 + `pane list` **一次**快照（`wsid → label`、各 ws 的 pane cwd 集）；归属判据 = 「该 ws 的 pane cwd 全在目标仓内」⇒ 复用，空 ws ⇒ 关旧建新（既有行为）。
- **名字冲突号**：相位 1 算定，承载在 **index 对齐局部数组** `t_nums[]`（与 `t_names[]`/`t_labels[]` 同批）；来源 = 目标 ws 的 pane label 集（同一快照）+ **本批预留**（同批两个 `pm` ⇒ `pm`,`pm2`；带任务 ⇒ `pm2(T554)`）。**禁全局变量**、**禁 rc/空行承载**。
- **算定后相位 2 禁重算**：`t_labels[]` 改存放置 label（来源 = `place_key_label`，不再 `fleet_of_invocation`）；`t_nums[]` 存后缀。唯一构造点 `fleet_core_build <role> [<task>] [<N>]` → 常驻 `<role><N>` / 派生 `<role><N>(<task>)`；`fleet_name_build` 去掉 scope 参（传非空 ⇒ rc≠0，防静默残留）。
- **parse 输出**：`OK <kind>,<role>,<task>,<num>` —— 新形 task 入第 3 段、槽位入第 4 段；旧形走**只读** `LEGACY OK <kind>,<role>,<task>,<scope>`；按首个分隔符 `(` / `-` / `@` 分派，**ensure 自动命名只生成新形**（`--as` 例外）；调用点禁把 legacy 值当 num（否则 `pm@todo` 被当 `pm<todo>`）。
- **字符集（P6/P7 老坑）**：读面名字过滤统一放行 `[A-Za-z0-9_@()-]`（`-` 置末位），四处硬编码必须同步：`:2935` 标题 sed · `:3803` pane cwd awk · `fleet_name_parse` · `card_name_problem`/`--as`；漏一处 ⇒ 带括号会话在 status/归属层整条消失。tmux 标题与 pi `--name` 实测接受 `()`（PM 2026-11-21）；herdr session 名拒绝括号但我们不按角色命名 session。
- **herdr 查询上限**：`ensure` ≤1 `workspace list` + ≤1 `pane list`（当前 `_term_herdr_spawn` 每目标各查一次 ⇒ 必须上提复用快照）；`status` = 既有 1 快照 + ≤1 `workspace list`；`close` ≤1 名册 + ≤1 `pane list`。**禁** per-target 重复查询（假探针计数断言）。
- **弃用单源**：`--fleet` / `--scope` / `.agents/fleet-scope` 命中 ⇒ 同一函数打**恰一行** warn（「本版忽略，下一 MINOR 移除」），随后**不读取、不校验、不影响放置**。
## 三、各态 wired（派单 ②；每态必 PASS 或 SKIP，禁 FAIL/静默；tmux 无 ws/tab ⇒ NOTE「后端无该信号」）

- **S1 单仓首拉**：`ensure pm`（仓 `fx554a`）⇒ rc=0 · 名字 `pm` · ws label `fx554a` · tab label `pm` · pane cwd=仓根。作用域：rc + 三个 label/cwd；变异「label 取名字」⇒ S1 红。
- **S2 同 ws 追加**：再 `ensure rd-be` ⇒ wsid 不变、新增 tab `rd-be`、ws 计数仍 1。变异「按角色新开 ws」⇒ 计数 2 红。
- **S3 二次 pm / 递增**：再 `ensure pm` ⇒ `pm2`；`pm`+`pm2` 在场 ⇒ `pm3`；带任务 ⇒ `pm2(T554)`（槽位 2 + 括号 task，tab label 同步）。作用域：pane 数 +1 + 名字 + tab label；变异「复用名字」⇒ 计数 +0 红、「N 写到 `)` 后」⇒ parse ERR 红。
- **S4 N>9**：2..9 全占 ⇒ rc≠0 + 「先清理」指路 + 零 pane；变异「允许 `pm10`」⇒ `parse(pm10)` / `parse(pm10(T1))` 非 ERR 红。
- **S5 基键冲突 / 复用判据**：两目录同名 `fx554-api` ⇒ label `fx554-api` / `fx554-api2`，各仓 pane 各在自己 ws；label 命中且 pane cwd ⊆ 目标仓 ⇒ 复用（wsid 不变），cwd 属它仓 ⇒ 走后缀。变异「只按 label 无脑复用」⇒ 第二仓 pane cwd 落在第一仓 ws 红；「按 fleet/slug/code 找 ws」⇒ 红。
- **S6 `@code` 目标**：manifest `api: ../api`；`ensure rd-be@api` ⇒ 名字 `rd-be`（无 `@`）、cwd=api、ws label=`<api 基键>`；带任务 ⇒ `rd-be(T553)`；变异「名字拼进 `@api`」⇒ 名不符红。
- **S7 未命中/非法**：`@nope` / manifest 坏 ⇒ rc≠0 + 列 code（manifest 坏另给 `文件:行号`）+ 零 pane；变异「回落主仓」⇒ pane 数 +1 红。
- **S8 `default` 读/写**：`HERDR_SESSION=default` 下 `ensure`/`status`/`close` rc=0（无 exit 3）；变异「保留旧守卫」⇒ rc=3 红。
- **S9 破坏性动作**：`cleanup`（herdr `--session default` / tmux `-S default`）打印「将停止 session=default，影响 N 个 workspace / M 个 pane」；无 `--force` ⇒ rc=2 零动作，有 ⇒ 执行并点名本 pane 将终止。变异「静默执行」⇒ 无影响面行红。
- **S10 护栏不回退**：自面板守卫（含 default 内自拆）/ 归属不可判定即拒（pane cwd 与名册均无 ⇒ die）/ 忙闲闸门（含 working pane ⇒ 无 `--force` 拒绝）三条逐条断言；各删一条 ⇒ 对应态红。
- **S11 legacy 回收 / 跨仓不误杀**：名册有 `pm@todo`（本仓）⇒ `close pm` 与 `close pm@todo` 都命中（AC6，不打印「未运行」）；两仓各 `pm` ⇒ `close pm` 只回收本仓（anchor + pane cwd），他仓 pane 存活。变异「只认新形」⇒ 假成功红；「全局取首条」⇒ 他仓 pane 消失红。
- **S12 弃用告警**：`--fleet x` / `--scope x` / 存在 `fleet-scope` ⇒ 各恰 1 行 warn、rc=0、放置仍 = 仓基键；变异「静默忽略」⇒ warn 计数 0 红。
- **S13 status ego**：本仓行格式不变（`✓ pm 在线 …`）；**仅当它仓有同名**时追加 `· 他仓同名 N 个（ws=<label>）`，且他仓 pane 不得被打成「本仓 pm 在线」（tmux 无 ws 信号 ⇒ NOTE）。变异「按全局 label 判在线」⇒ 本仓无 pm 却出 ✓ 红。
## 四、既有断言迁移（旧 → 新，逐处；**禁删**）

- `28:81-84` ① 表：builder 改 `build(kind,role[,num][,task])`；14 行期望逐条改形：`rd-be-T1`→`rd-be(T1)`、`qa-T508`→`qa(T508)`、`arch-designer-96b`→`arch-designer(96b)`、`pm-M2026…`→`pm(M2026…)`、`rd-infra-M2026…`→`rd-infra(M2026…)`、`sec-review-T42`→`sec-review(T42)`、`sec-review-notes`→`sec-review(notes)`；**补** `pm2`→`OK resident,pm,,2`、`rd-be2(T553)`→`OK derived,rd-be,T553,2`。
- `28:109-114` ③：`build(card,sec-review,todo)`→ 新 `build(card,sec-review)`=`sec-review`（第三参非空 ⇒ rc≠0）；`build(card,sec-review,T42,2)`=`sec-review2(T42)`；`parse(sec-review@todo)` 仍 ERR；`parse(sec-review2(T42))`=`OK card,sec-review,T42,2`；`parse(rd-be-T1@todo)`=`LEGACY OK derived,rd-be,T1,todo`。
- `28:119-130` ④：`rd-fe@…` 16 例**保留**（`@` 全域非法）；新增 `pm1`/`pm0`/`pm10`/`pm2x`、`arch-designer(T554`、`arch-designerT554)`、`arch-designer((T554))`、`arch-designer(T5)4` 必 ERR；`$L49` 超 48 保留；build 拒非法 num / 缺 task 的派生形态保留。
- `28:133-171` ⑤ fleet 三档（文件/CLI/CRLF/目录/symlink 逃逸 20+ 条）⇒ 弃用面：文件缺失 ⇒ 零 warn；其余一律 rc=0 + 恰 1 行 warn + 放置键仍 = 仓基键（旧 fail loud 断言改向「不再读取」）。
- `28:155-156` core 位保留前缀：`subagent-x@y`/`nao-x@y` → `subagent-x`/`nao-x` 仍 ERR。
- `28:160-186` ⑤b slug → `place_key_label`：归一/16 截断/worktree 同键三处**值不变**；新增同基键两仓 ⇒ `-2`（herdr 态，tmux SKIP NOTE）。
- `28:637-650` fixture stub label `rd-be@todo`/`qa@todo` → `rd-be`/`qa`；**新增**标题 fixture `π - arch-designer(T554) - …`（P6 字符集守门，漏 `()` 该行整条消失）；`28:762-767` 异常节期望串同改。
- `28:1118-1119` `B2_RD_FE="rd-fe@$B2_WS_LABEL"` → `"rd-fe"`；派生 `rd-be-$TASK` → `rd-be($TASK)`；`28:1384` 前缀断言随值变。
- `28:1505-1517` C2 期望表：`grep '^$_n@$LAB_SLUG'` → `grep -qxF "$_n"`；`已拉起 $_n@$LAB_SLUG` → `已拉起 $_n`；`grep -cF '@$LAB_SLUG'`=0 → `grep -cF '('` = 带任务条数，且 `grep -c '@'`=0。
- `33:85-101` 前提/U1/U2：ws label 断言不变（`repo-b`），pane label `rd-fe@repo-b`→`rd-fe`、`qa@repo-b`→`qa`；`u1_verdict` 参数去 `@`。
- `33:113-120` U3 worktree：名字 `arch-designer`；ws 仍 `git-repo`（同键断言不变）。
- `33:126-134` U4a/U4b：`--scope bk` / `fleet-scope=todo` ⇒ 1 行 warn + **label = 仓基键**（`repo-b`/`repo-scope-b`）；旧「label=bk / label=todo」两条改向。
- `33:137-144` D4 体检：`fleet 生效值 = todo` / `来源：.agents/fleet-scope` → `弃用：.agents/fleet-scope 已忽略`；rc=0、不计 warn 保留。
- `33:147-163` U5 + 负控：两仓默认名字均 `rd-infra`（各自 ws）；`--fleet dup` 由「撞车 rc≠0」**反转为** warn + 两仓 rc=0；`与在场会话同 core`、`两仓同 --fleet` 文案断言退役。
- `33:168-190` AC3/AC4：`--fleet cli` ⇒ warn、label=`repo-priority`；`pm@nao-skills`→`pm`、label `nao-skills`；`--fleet BAD` 由 rc≠0 **反转为** warn+rc=0（保留「零 pane 断言」→ 期望 +1 pane）。
- `33:194-201` AC5 `--fleet x --scope y`：由「拒绝」→ 双 warn + rc=0；用法错只剩「缺参/给参为空」。
- `33:206-238`（含 `274-330`）AC11/AC12 + 负控：`pm@<slug>` 全名 close → `close pm`；`--task N1` ⇒ `rd-fe(N1)`；名长双态（32+`@`+16=49）退役 ⇒ 默认 tier「32 字卡 role 直接可用（≤48）」+ 显式 tier 改「32 字 role + `(T…)` 使 name>48 ⇒ fail loud」；`fleet 值超长` 提示退役。
- `37:54-55` 正例改新形 `CORE=qa($T37)`（`rent` 同步）；legacy 态**保留** `qa-$T37` 作 AC6 对照；`at_field`（回收行 `@ <path>`）保留；态 c「仅他仓 1」→ 不回收 + 指路（D4）；b/d/e 断言保留。
- `38:60-62` 全名 `$CORE@$F_*` 保留为 legacy 读面（AC6）；「b 唯一·他仓跨仓回收」只对 legacy 名成立；新形同名跨仓走 37 的 anchor 面（D4）；g1/g2 与 L368/L410 负控保留、正例 `$CORE` 改 `qa($T38)`。
- `39:147-190` A/B/C/D：名字去 `@…`；B ws label `alpha`→`fx39-main`；C 由「同一 workspace」→ **新 ws `fx39-api`**、`main/`|`api/` 前缀退役；M5 `·fleet=alpha ·code=api`→`·code=api ·path=<api>`；D `@alpha`（slug 退役）→ `@main` 或 `@<path>`。
- `39:195-290` E/F/G/H/I：E 保留（stderr 改列 code + 主仓 code）；F 中「缺 slug」「code==slug」「slug 超 16」三条退役（改 warn+忽略，D7），其余 8 条保留；G/H 分歧 fail loud **反转为** warn+忽略；I 旧 49 场景不可复现 ⇒ 改「32 字 role + `(T…)` ⇒ name>48」fail loud。
- `20/22/24`（**清单外同源回归面**）：`20:195-262` `code-reviewer-T537@$BASE`→`code-reviewer(T537)`、`qa@$BASE`→`qa`、`--as code-reviewer-notes` 去 `@`（按 legacy 只读）；`22:122-198` 输出行 `已拉起 arch-designer@$FLEET`→`已拉起 arch-designer`；`24:195-250` 卡名 `-T24A@$BASE`→`(T24A)`。
- `39:294-310` J 保留（legacy 读面，回收行 `@ <api path>` 不变）；K 保留（并列拒绝 + tmux no-signal NOTE）；L 保留。
## 五、禁改区 / 风险

- 禁改：`close` 的 anchor 三态（T551）与全名复数查询（T552）、`_term_herdr_self_refuse`、`_term_herdr_busy`、`pane_cwd_snapshot`、`repo_contains_path`、`fleet_manifest_load` 的 fail-loud 口径（未知键/行号）、`tests/t4/lib-backend.sh` 的 #145 隔离。
- R1（P1）文法/迁移双风险：文法唯一判据 = 括号位置 + 槽位紧贴单字符 + 最长角色匹配 + 首个分隔符分派（出现第二种分解即打回）；迁移面 `28` ⑤/C2、`33` AC4/AC5、`39` C/G/H/I 是**行为反转**，逐条改向、禁删旧断言换绿灯。
- R3（P2）`default` 放行扩大破坏面（靠 S9/S10 钉住：影响面 + 三护栏不旁路）；同名跨 ws 后名册多条目 ⇒ `close` 依赖 anchor（否定：出现「全局首命中」回退）。
## 六、拍板记录（PM 2026-11-21；D1/D2/D5 为 v2 改形）

- **D1（改）** 名字文法 = 常驻 `<role>[<N>]` / 派生 `<role>[<N>](<task>)`（用户拍板括号格式；N 在 `(` 前，理由见 §一.3）。
- **D2（改）** 第 4 槽位保留、新形语义 = num；parse 必须吃 `(...)`，legacy `@` 形态并存（首个分隔符分派）。
- **D3** N 判重域 = **目标 workspace**（跨 ws 同名允许，PRD S2/AC7 的前提）。
- **D4** 跨仓 close：legacy `@` 名保留唯一回落；v2 裸名只在锚内，他仓同名 ⇒ 不回收 + 指路（37 态 c / 38 态 b 的旧行为废止）。
- **D5（改）** `cleanup`/`session stop` 对 default = 放行（不再 exit 3）；破坏性执行加 `--force` 门槛（无 ⇒ 打印影响面 + rc=2 零动作）；含 working pane 同。
- **D6** 「`session stop default`」无独立子命令 ⇒ 口径 = cleanup 内部 stop 步，不新增子命令（否则超 M 范围）。
- **D7** 旧 `fleet.yaml` 的 `slug:` 与 `fleet-scope`、`--fleet/--scope` 一律 warn + 忽略（不校验、不 fail），下一 MINOR 移除。
- **D8** status ego 采「本仓行不变 + 仅它仓同名时追加一行」（保 `28` C2 golden 不动）。
