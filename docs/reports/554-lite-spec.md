# T554 · 舰队模型 v2：workspace 为绑定单位（lite 判据）

- 状态：待 PM 拍板（D1–D8）· 更新：2026-11-21 · Owner：arch-designer · 修订：首版（判据句 + 数据通道 + 13 态 + 5 用例逐处迁移）
- 指针：Issue [#554](https://github.com/Nathan3303/nao-skills/issues/554) · PRD `docs/prds/2026-11-20-fleet-model-v2.md` · ADR `docs/adr/2026-11-20-workspace-as-binding-unit.md` · 骨架 `docs/reports/146-arch-lite.md`
- 代码（禁 cat 全文；行号随 HEAD `f436ed7` 漂移，按符号定位）：`fleet_core_build:1883` · `fleet_name_build:1897` · `fleet_name_parse:1917` · `fleet_scope_slug:1958` · `fleet_of_invocation:1991` · `fleet_scoped_candidates:2820` · `_term_herdr_require:461` · `_term_herdr_exec:430` · `_term_herdr_spawn:1120` · `_term_herdr_tab_id_for:1002` · `cmd_close:4385` · `cmd_cleanup:4667` · `cmd_ensure:4672`

**结论：有条件可行**（条件 = §二 通道 + §三 各态断言 + §四 迁移清单）。改动面 = 放置键来源、名字契约 v2、`default` 守卫分级、manifest 收窄；`close` 归属判据（anchor + pane cwd）不动。有结构性决策 ⇒ ADR 见上；本报告只放判据，不放闸门清单。
## 一、判据句（新契约，逐条可断言）

1. **放置键 = 仓**：workspace label = 仓基键（`place_key_label`：git common-dir 父目录名 / 非 git = 目录名，归一 `^[a-z0-9][a-z0-9_-]{0,15}$`）；两仓同基键 ⇒ 后者 `<key>2`…`<key>9`，全占 ⇒ die。名字**不含位置**（`@` 段删除）。
2. **名字文法 v2**：`name := <role>[<N>][-<task>]`，`N ∈ {2..9}` **紧贴**角色名且单字符；role = 事实表**最长匹配**；task = `^[A-Za-z0-9_-]+$`；name ≤48，卡 core（含 N）≤32。
3. **歧义边界（反例）**：`qa-2` = 任务号 `2`（有 `-`）；`qa2` = qa#2；v1 名字角色名后恒有 `-` ⇒ 任何 v1 名字都不匹配 `role[2-9]` ⇒ 新旧名字集合**不相交**（注册角色名本身以数字结尾者由 §一.4 的跳号规则排除）。`arch-designer-96b`（task 首字符是数字）不受影响 —— 后缀只在无分隔符时成立；`rd-be2-T553` 唯一分解 = `rd-be` + N2 + task `T553`（若把它读成 task `2-T553`，v1 拼法必为 `rd-be-2-T553`，串不同）。
4. **N 的判重域 = 目标 workspace**：同 ws 内 `<role>` 已存在 ⇒ 取最小空闲 N；跨 ws 同名（两仓都叫 `pm`）**允许**；`<role><N>` 撞已注册角色 id ⇒ 跳过该 N；2..9 全占 ⇒ fail loud 指路 `close`。`pm1`/`pm0`/`pm10` 结构上不可解析（⇒ N>9 必 fail loud，不会静默变成任务号）。
5. **`ensure <role>@<code>`**：`@` **只选目标仓**（manifest `code` / 既有仓路径），不进名字；code 未命中 / manifest 非法 ⇒ fail loud 列可用 code + `文件:行号`，零 pane。
6. **`default` 等价**：`ensure` / `status` / `close` / `cleanup`（herdr `--session default` / tmux `-S default` 生产 socket，内部含 `session stop default`）均放行；唯一差异 = 破坏性动作打印影响面（§三 S8–S10）。
7. **历史形态**：解析保留 **legacy 读模式**（`<core>@<旧 fleet|code>`）—— 仅 `status`/`close` 接受，`ensure` 永不生成（AC6）。
## 二、数据通道（派单 ①）

- **放置键**：`place_key_label <repo_phys>`（原 `fleet_scope_slug` 改名，单一实现）→ stdout 恰 1 行；空输出 = 实现缺陷 ⇒ die（**禁** rc / 空行承载「不可知」）。冲突号来自 `workspace list` **一次**快照 + `pane list` **一次**快照（`wsid → label`、各 ws 的 pane cwd 集）；归属判据 = 「该 ws 的 pane cwd 全在目标仓内」⇒ 复用，空 ws ⇒ 关旧建新（既有行为）。
- **名字冲突号**：相位 1 算定，承载在 **index 对齐局部数组** `t_nums[]`（与 `t_names[]`/`t_labels[]` 同批）；来源 = 目标 ws 的 pane label 集（同一快照）+ **本批预留**（同批两个 `pm` ⇒ `pm`,`pm2`）。**禁全局变量**、**禁 rc/空行承载**。
- **算定后相位 2 禁重算**：`t_labels[]` 改存放置 label（来源 = `place_key_label`，不再 `fleet_of_invocation`）；`t_nums[]` 存后缀。唯一构造点 `fleet_core_build <role> [<task>] [<N>]` → `<role><N>[-<task>]`；`fleet_name_build` 去掉 scope 参（传非空 ⇒ rc≠0，防静默残留）。
- **parse 输出**：`OK <kind>,<role>,<task>,<num>`（v2）与 `LEGACY OK <kind>,<role>,<task>,<scope>`（读面）—— 第 4 槽位保留、语义由 `scope` 换 `num`（11 处接线只改语义不改字段数）；**调用点禁把 legacy 值当 num**（否则 `pm@todo` 会被当成 `pm<todo>`）；与 `ensure` 的 positional `@<code>` 是两个命名空间。
- **herdr 查询上限**：`ensure` ≤1 `workspace list` + ≤1 `pane list`（当前 `_term_herdr_spawn` 每目标各查一次 ⇒ 必须上提复用快照）；`status` = 既有 1 快照 + ≤1 `workspace list`；`close` ≤1 名册 + ≤1 `pane list`。**禁** per-target 重复查询（假探针计数断言）。
- **弃用单源**：`--fleet` / `--scope` / `.agents/fleet-scope` 命中 ⇒ 同一函数打**恰一行** warn（「本版忽略，下一 MINOR 移除」），随后**不读取、不校验、不影响放置**。
## 三、各态 wired（派单 ②；每态必 PASS 或 SKIP，禁 FAIL/静默；tmux 无 ws/tab ⇒ NOTE「后端无该信号」）

- **S1 单仓首拉**：`ensure pm`（仓 `fx554a`）⇒ rc=0 · 名字 `pm` · ws label `fx554a` · tab label `pm` · pane cwd=仓根。作用域：rc + 三个 label/cwd；变异「label 取名字」⇒ S1 红。
- **S2 同 ws 追加**：再 `ensure rd-be` ⇒ wsid 不变、新增 tab `rd-be`、ws 计数仍 1。变异「按角色新开 ws」⇒ 计数 2 红。
- **S3 二次 pm / 递增**：再 `ensure pm` ⇒ 会话/tab `pm2`（不是「已在运行」跳过）；`pm`+`pm2` 在场 ⇒ `pm3`。作用域：pane 数 +1 + 名字；变异「复用名字」⇒ 计数 +0 红、「写死 2」⇒ 名字凭空 `pm2` 红。
- **S4 N>9**：2..9 全占 ⇒ rc≠0 + 「先清理」指路 + 零 pane；变异「允许 `pm10`」⇒ parse(`pm10`) 非 ERR 红。
- **S5 基键冲突 / 复用判据**：两目录同名 `fx554-api` ⇒ label `fx554-api` / `fx554-api2`，各仓 pane 各在自己 ws；label 命中且 pane cwd ⊆ 目标仓 ⇒ 复用（wsid 不变），cwd 属它仓 ⇒ 走后缀。变异「只按 label 无脑复用」⇒ 第二仓 pane cwd 落在第一仓 ws 红；「按 fleet/slug/code 找 ws」⇒ 红。
- **S6 `@code` 目标**：manifest `api: ../api`；`ensure rd-be@api` ⇒ 名字 `rd-be`（无 `@`）、cwd=api、ws label=`<api 基键>`；变异「名字拼进 `@api`」⇒ 名不符红。
- **S7 未命中/非法**：`@nope` / manifest 坏 ⇒ rc≠0 + 列 code（manifest 坏另给 `文件:行号`）+ 零 pane；变异「回落主仓」⇒ pane 数 +1 红。
- **S8 `default` 读/写**：`HERDR_SESSION=default` 下 `ensure`/`status`/`close` rc=0（无 exit 3）；变异「保留旧守卫」⇒ rc=3 红。
- **S9 破坏性动作**：`cleanup`（herdr `--session default` / tmux `-S default`）打印「将停止 session=default，影响 N 个 workspace / M 个 pane」；无 `--force` ⇒ rc=2 零动作，有 ⇒ 执行并点名本 pane 将终止。变异「静默执行」⇒ 无影响面行红。
- **S10 护栏不回退**：自面板守卫（含 default 内自拆）/ 归属不可判定即拒（pane cwd 与名册均无 ⇒ die）/ 忙闲闸门（含 working pane ⇒ 无 `--force` 拒绝）三条逐条断言；各删一条 ⇒ 对应态红。
- **S11 legacy 回收 / 跨仓不误杀**：名册有 `pm@todo`（本仓）⇒ `close pm` 与 `close pm@todo` 都命中（AC6，不打印「未运行」）；两仓各 `pm` ⇒ `close pm` 只回收本仓（anchor + pane cwd），他仓 pane 存活。变异「只认 v2」⇒ 假成功红；「全局取首条」⇒ 他仓 pane 消失红。
- **S12 弃用告警**：`--fleet x` / `--scope x` / 存在 `fleet-scope` ⇒ 各恰 1 行 warn、rc=0、放置仍 = 仓基键；变异「静默忽略」⇒ warn 计数 0 红。
- **S13 status ego**：本仓行格式不变（`✓ pm 在线 …`）；**仅当它仓有同名**时追加 `· 他仓同名 N 个（ws=<label>）`，且他仓 pane 不得被打成「本仓 pm 在线」（tmux 无 ws 信号 ⇒ NOTE）。变异「按全局 label 判在线」⇒ 本仓无 pm 却出 ✓ 红。
## 四、既有断言迁移（旧 → 新，逐处；**禁删**）

- `28:81-84` ① 表：`build(kind,core,"")` 不变；parse 末段语义 scope→num（空值形态逐字不变）⇒ **补 3 行**：`pm2`→`OK resident,pm,,2`、`rd-be2-T553`→`OK derived,rd-be,T553,2`、`sec-review2-T42`→`OK card,sec-review,T42,2`。
- `28:109-114` ③：`build(card,sec-review,todo)`→ 新 `build(card,sec-review)`=`sec-review`，第三参非空 ⇒ rc≠0；`parse(sec-review@todo)` 仍 ERR；`parse(sec-review)`=`OK card,sec-review,,`；「往返带 scope」→「往返带 num」。
- `28:119-130` ④：`rd-fe@…` 16 例**保留**（语义改「`@` 全域非法」）；新增 `pm1`/`pm0`/`pm10`/`pm2x` 必 ERR；`$L49` 超 48 保留；build 拒非法 num / 未知 kind 保留。
- `28:133-171` ⑤ fleet 三档（文件/CLI/CRLF/目录/symlink 逃逸 20+ 条）⇒ 弃用面：文件缺失 ⇒ 零 warn；其余一律 rc=0 + 恰 1 行 warn + 放置键仍 = 仓基键（旧 fail loud 断言改向「不再读取」）。
- `28:155-156` core 位保留前缀：`subagent-x@y`/`nao-x@y` → `subagent-x`/`nao-x` 仍 ERR。
- `28:160-186` ⑤b slug → `place_key_label`：归一/16 截断/worktree 同键三处**值不变**；新增同基键两仓 ⇒ `-2`（herdr 态，tmux SKIP NOTE）。
- `28:637-650` fixture stub label `rd-be@todo`/`qa@todo` → `rd-be`/`qa`；`28:762-767` 异常节期望串同改（4 处）。
- `28:1118-1119` `B2_RD_FE="rd-fe@$B2_WS_LABEL"` → `"rd-fe"`（派生 `rd-be-$TASK` 无 `@`）；`28:1384` 前缀断言随值变。
- `28:1505-1517` C2 期望表：`grep '^$_n@$LAB_SLUG'` → `^$_n$`；`已拉起 $_n@$LAB_SLUG` → `已拉起 $_n`；`grep -cF "@$LAB_SLUG"`=0 → `grep -c '@'`=0。
- `33:85-101` 前提/U1/U2：ws label 断言不变（`repo-b`），pane label `rd-fe@repo-b`→`rd-fe`、`qa@repo-b`→`qa`；`u1_verdict` 参数去 `@`。
- `33:113-120` U3 worktree：名字 `arch-designer`；ws 仍 `git-repo`（同键断言不变）。
- `33:126-134` U4a/U4b：`--scope bk` / `fleet-scope=todo` ⇒ 1 行 warn + **label = 仓基键**（`repo-b`/`repo-scope-b`）；旧「label=bk / label=todo」两条改向。
- `33:137-144` D4 体检：`fleet 生效值 = todo` / `来源：.agents/fleet-scope` → `弃用：.agents/fleet-scope 已忽略`；rc=0、不计 warn 保留。
- `33:147-163` U5 + 负控：两仓默认名字均 `rd-infra`（各自 ws）；`--fleet dup` 由「撞车 rc≠0」**反转为** warn + 两仓 rc=0；`与在场会话同 core`、`两仓同 --fleet` 文案断言退役。
- `33:168-190` AC3/AC4：`--fleet cli` ⇒ warn、label=`repo-priority`；`pm@nao-skills`→`pm`、label `nao-skills`；`--fleet BAD` 由 rc≠0 **反转为** warn+rc=0（保留「零 pane 断言」→ 期望 +1 pane）。
- `33:194-201` AC5 `--fleet x --scope y`：由「拒绝」→ 双 warn + rc=0；用法错只剩「缺参/给参为空」。
- `33:206-238` AC11/AC12：`pm@<slug>` 全名 close → `close pm`（裸名即本仓名）；名长双态（32+`@`+16=49）退役 ⇒ 改「卡 core（含 N）≤32，超即 fail loud」；`fleet 值超长` 提示退役；`33:274-330` 夹具名去 `@`、放置/cwd 断言不变。
- `37:54-55` `LSCOPED`/`OSCOPED` → 均 `=$CORE`（两仓同名，仅 cwd 区分）；`at_field`（回收行 `@ <path>`）保留；态 c「仅他仓 1」由「唯一回落跨仓回收」→ **不回收 + 指路**（D4）；b/d/e 断言保留（d 因同名更依赖 anchor）；`37:429` 负控保留。
- `38:60-62` 全名 `$CORE@$F_*` 保留为 legacy 读面（AC6）；「b 唯一·他仓跨仓回收」只对 legacy 名成立；v2 同名跨仓走 37 的 anchor 面（D4）；g1/g2 与 L368/L410 负控保留、夹具名去 `@`。
- `39:147-190` A/B/C/D：名字去 `@…`；B ws label `alpha`→`fx39-main`；C 由「同一 workspace」→ **新 ws `fx39-api`**、`main/`|`api/` 前缀退役；M5 `·fleet=alpha ·code=api`→`·code=api ·path=<api>`；D `@alpha`（slug 退役）→ `@main` 或 `@<path>`。
- `39:195-290` E/F/G/H/I：E 保留（stderr 改列 code + 主仓 code）；F 中「缺 slug」「code==slug」「slug 超 16」三条退役（改 warn+忽略，D7），其余 8 条保留；G/H 分歧 fail loud **反转为** warn+忽略；I 49 超长不可复现 → 改「core（含 N）≤32 / name ≤48」。
- `39:294-310` J 保留（legacy 读面，回收行 `@ <api path>` 不变）；K 保留（并列拒绝 + tmux no-signal NOTE）；L 保留。
## 五、禁改区 / 风险

- 禁改：`close` 的 anchor 三态（T551）与全名复数查询（T552）、`_term_herdr_self_refuse`、`_term_herdr_busy`、`pane_cwd_snapshot`、`repo_contains_path`、`fleet_manifest_load` 的 fail-loud 口径（未知键/行号）、`tests/t4/lib-backend.sh` 的 #145 隔离。
- R1（P1）名字文法歧义面：唯一判据 = 紧贴 + 单字符 + 最长角色匹配；否定条件 = 出现第二种分解（任何 `pm10`/`pm-2` 可解析即打回）。
- R2（P1）迁移面最大：`28` 的 ⑤ 与 C2 期望表、`33` 的 AC4/AC5 行为**反转**、`39` 的 C/G/H/I 语义反转 —— 逐条迁移，禁「删掉旧断言换绿灯」。
- R3（P2）`default` 放行扩大破坏面：靠 S9/S10 两条钉住（打印影响面 + 三条护栏不旁路）；否定 = 任一护栏在 default 路径被跳。
- R4（P2）跨 ws 同名后，名册/`intercom` 层面同名多条目 ⇒ `close` 依赖 anchor；否定 = 出现「全局首命中」回退。
## 六、待 PM 拍板

- **D1** 名字文法采「紧贴 + 单字符 `[2-9]` + N>9 fail loud + 撞注册角色跳号」（§一.2–.4）。
- **D2** `fleet_name_parse` 第 4 槽位保留、语义 scope→num（字段数不变）—— 否则 11 处接线与 28 的 C1/C2 全量改形。
- **D3** N 判重域 = **目标 workspace**（跨 ws 同名允许，PRD S2/AC7 的前提）。
- **D4** 跨仓 close：legacy `@` 名保留唯一回落；v2 裸名只在锚内，他仓同名 ⇒ 不回收 + 指路（37 态 c / 38 态 b 的旧行为废止）。
- **D5** `cleanup default`：无 `--force` 打印影响面 + rc=2 零动作；`--force` 才执行；含 working pane 亦需 `--force`。
- **D6** 「`session stop default`」无独立子命令 ⇒ 口径 = cleanup 内部 stop 步，不新增子命令（否则超 M 范围）。
- **D7** 旧 `fleet.yaml` 的 `slug:` 与 `fleet-scope`、`--fleet/--scope` 一律 warn + 忽略（不校验、不 fail），下一 MINOR 移除。
- **D8** status ego 采「本仓行不变 + 仅它仓同名时追加一行」（保 `28` C2 golden 不动）。
