# T552 / Issue #151 · `close <core>@<fleet>` 全名分支双键三态（arch-lite 判据）

- 状态：待 PM 核可（D1–D5）· 更新：2026-11-18 · Owner：rd-infra（判据阶段，未写码）
- 指针：Issue [#151](https://github.com/Nathan3303/nao-skills/issues/151) · 前序判据 `docs/reports/146-arch-lite.md`（本批 = 其 §七 R1 出界项）· 代码 `.agents/scripts/nao-fleet.sh:4243-4249`（#151 正文的 `:4197-4203` 是 T551 合并前旧行号）· 复用 `:2179 intercom_cwds_for` · 夹具参照 `tests/t4/cases/37-close-bare-repo.sh`

**结论：有条件可行。** 改动面 = 全名分支 7 行 → 6 行；零新增函数、零 git 调用、零命名契约改动。语义从「按名册首命中定仓」收敛为「唯一采用 / 并列拒绝 / 0 保留回落」⇒ 缺陷修复、无新契约 ⇒ **本批不需要 ADR**。

## 一、现状断点（已核 HEAD `4b3019e`）

- `:4246` `repo="$(intercom_cwd_for "$name")"` —— 跨仓同名时**取首命中**；`:4248-4249` 的「按目标仓复核」**是同义反复**（拿首命中的 cwd 再过同一名册 ⇒ 恒等）⇒ 结构上零判别力。
- 本分支 `$repo` 的消费者只有 3 个：herdr 忙闲第二信号（`_term_herdr_busy` → `intercom_status_for <name> <repo>`，**按仓过滤**）· tmux 回收 warning 的 `cwd=$repo` 文案 · `pi_pids_for` 兜底。危害面比裸名分支窄但同型（错仓 ⇒ 忙闲读不到 ⇒ 误杀在跑 turn）。
- `$fallback_repo`（`:4236`/`:4239`）= `ROLE_WS`（值 `.` ⇒ 语义「调用方 cwd」）或卡所在仓根。
- 既有：本分支**不给** `scope` 赋值（`term_reclaim` 第 5 参沿革）⇒ tmux T516 歧义闸门只见无 scope 派生。本批不改，登记 R3。

## 二、数据通道（派单 ①）

- **判定键 = 全名字符串本身**：`fleet_name_build` 产出即 `<core>@<fleet>`，双键已编码在同名字符串里 ⇒ `intercom_cwds_for` 按 `name` 精确匹配**等价**双键。**原样复用：不加参、不新增函数、不传 anchor。**
- 输入：`$name`（本分支已有）+ `$roster_ok`（**本分支局部**取一次 `intercom_list_json >/dev/null 2>&1`；命 `_INTERCOM_JSON` 缓存 ⇒ 每命令探针仍 =1）。禁全局；**禁**用 rc / 空行承载「名册不可知」（沿用 T551）。
- 输出：`mapfile -t scoped_cwds < <(intercom_cwds_for "$name")` —— 0..N 行 cwd，**只查询不决策**。
- **Q2 锚的结论：锚不参与本分支判据**。① 全名是用户显式键，不需要锚消歧；② 双键多命中 ⇒ **一律 die**，**不**先按调用方仓过滤：过滤会把 AC3 的「他仓唯一」变 0（再回落 = 又猜），也会把跨仓并列静默收敛成本仓 1 条（d 态）；③ 与「保留跨仓唯一回收」自洽的关键 = **唯一命中根本不经锚**。全名分支因此**不调用** `_close_anchor`（零 git 调用），`$anchor` 保持 `local` 初值。

## 三、五态判据 + 断言作用域 + 变异必红（派单 ②③）

| 态（名册键 `<core>@<fleet>`） | 期望结论 | 断言作用域（每条作用域独立） | 变异必红 |
|---|---|---|---|
| a 唯一·本仓：1 条 cwd=PRA + 本仓 pane | h=1 ⇒ 回收本仓 | rc=0 · 本仓 pane 消失 · `@`=PRA · 无「歧义/未运行」· 探针调用=1 | 三态改 `h≥1 ⇒ die` ⇒ rc≠0 |
| b 唯一·他仓（AC3 不回归）：1 条 cwd=PRB + 他仓 pane | h=1 ⇒ **跨仓照旧回收** | rc=0 · 他仓 pane 消失 · `@`=PRB · 本仓零动作 · 无「歧义」 | 见 c/d（锚过滤向） |
| b3 唯一·他仓 + 名册 `status=working` | 忙闲闸门按**他仓**命中 ⇒ 拒绝 | herdr：rc≠0 +「拒绝回收」+「名册状态=working」+ pane 存活（**前提**：桩 `pi` 的 agent_status 须为 idle，否则闸门先按 agent_status 拒 ⇒ 失去仓判别力）；tmux 同结论但**无判别力**（忙闲按名不按仓）⇒ 该向显式 SKIP | h=1 不采用 cwd（保留回落）⇒ rc=0 + 他仓 pane 被回收 |
| a2 唯一·本仓 + 名册报在线但无 pane | rc≠0，且不谎报「未运行」 | tmux：warn 含 `cwd=<PRA 物理路径>`；herdr：rc≠0 即可（无仓字段 ⇒ 该向显式 SKIP） | h=1 不采用 cwd ⇒ warn `cwd=.`（回落原值） |
| c 多命中·都在他仓：cwd=PRB、PRC（各 1 pane） | h>1 ⇒ die 列全部候选，零回收 | rc≠0 ·「close 目标歧义」· 含全名 + PRB + PRC +「人工核对」· 无「未运行」· **两 pane 均存活** · 文案**不含**「用全名」 | h>1 取首条 ⇒ 回收一条 ⇒ 必红 |
| d 多命中·跨仓 1+1：PRA + PRB（各 1 pane，名册他仓在前） | h>1 ⇒ die（**禁**先按调用方仓过滤） | 同 c（候选含 PRA+PRB）· **本仓 pane 存活** · rc≠0 | 调用改 `intercom_cwds_for "$name" "$anchor"` ⇒ 过滤成 1 ⇒ rc=0 回收本仓 ⇒ 必红 |
| e 0 命中·裸名在跑：名册只有 `<core>`（cwd=PRA）+ 裸名 pane | h=0 ⇒ 保留回落 ⇒「未运行」 | rc=0 · stdout 含「未运行（无需回收）」· 裸名 pane 存活 · 无「歧义」 | h=0 改 die ⇒ rc≠0 |
| f 名册不可用：假探针非 0 | 不判并列，与改动前逐字等价 | rc=0 · stdout = 基线（「未启用 tasks-state」+「`<全名>` 未运行（无需回收）」）· 无「歧义」 | `roster_ok=0` 当 die ⇒ rc≠0 |

- **Q3 时序（`$fallback_repo` 位置）**：`repo="$fallback_repo"` **先赋值**（= 唯一回落值，不是「失败后补」）→ h=1 覆盖 / h>1 die / h=0 保留；删 `:4248-4249` 两行 `r2` 复核（新结构下恒等）。⇒「锚 / 回落」两套语义不再并存。
- **Q4 `_close_adopt_repo` 不适用、不调用**：其 die 文案假定「还能用全名消歧」（对已在用全名的用户是误导），复用需 append 第 3 参「文案模式」⇒ 触碰 T551 落地函数及其 `adopt_unit` 抽取断言，收益（省 4 行）< 风险 ⇒ 采用**分支内联三态**（与裸名分支同风格）。其 `roster_ok` 前置条件 = 本分支局部取一次；两分支互斥，共享同一份缓存。

## 四、先红后绿形态

- 新用例 `tests/t4/cases/38-close-scoped-repo.sh`（`37` 与 `09`/`13` 既有断言逐字不动）：登记 `run.sh` 的 `CASE_IDS`/`CASE_TITLES` + `backends/herdr.txt` 增 `38  shared  —  后端无关（#151 全名双键三态…）`；**不入** `FAST_CASES`（名册探针 + 三仓 pane 超预算）。
- 夹具沿用 37 三件套（`NAO_QA_FAKE_ROSTER` pretty-print / 探针计数文件 / `be_*` 门面）；三仓 `fx38-a`(=本仓·git 仓·调用方 cwd)/`fx38-b`/`fx38-c`（后两者**不在任何 git 仓内**），fleet `f38a|f38b|f38c`，会话名唯一派生（`qa-T4C38$$@…`，禁用宿主真名），名册顺序固定**他仓在前**。
- **先红**（旧脚本 `4b3019e` × 用例 38）：红点 = c/d 的 rc 与零回收断言（tmux：c/d 各 1 条 rc 红 + 1 条零回收红；herdr：c/d 各 1 条文案红，零回收在 pane 层本就拒 ⇒ **如实记录红点按后端不同**）；a/b/b3/a2/e/f 在旧脚本上本身即绿（唯一命中时首命中 ≡ h=1）⇒ **不得充作先红证据**。
- **后绿**：同用例双后端全绿 + `check` rc=0 + 全量 `npm test`（含新例）+ `test:t4:full` 双后端。

## 五、禁改区（同意 PM 清单，附两点补充）

- 裸名分支 `else` 支整段 · `intercom_cwd_for`（`:2162`）· **`intercom_cwds_for` 函数体与签名**（本批零改动，调用点只给 1 参）· `_close_anchor` / `_close_adopt_repo`（本批不调用、不改签名）。
- 句柄层 5 函数（`term_liveness`/`term_reclaim`/`_term_herdr_busy`/`self_pane_refuse`/`pane_cwd_snapshot`）· `repo_anchor_roots` · `fleet_*` 命名契约 + `roles.yaml` + `.agents/prompts/*`。
- `tests/t4/lib-backend.sh` · `cases/09`/`13`/`37` 既有断言（只允许新增 38 与登记行）· `docs/tasks-state.md`（归 PM）· 零新依赖 / 零网络 / 零密钥。

## 六、风险与否定条件

- **R1（P2 · 最大风险）采用层在结果层几乎不可观测**：两后端定位 pane 都按名字/标签、**不按 repo 过滤**（`find_pane_for_any_repo` / herdr label）⇒ h=1 取到的 cwd 用 pane 结局证不出来；唯一仓敏感层 = herdr 忙闲第二信号 + tmux `cwd=$repo` 文案。**否定**：a/b 若缺 b3/a2 两条仓敏感断言，判据不合格（重演 T551「锚退化仍绿」）。
- **R2（P2）** `ROLE_WS=`.` ⇒ 仓根调用时 `fallback_repo` 恰好 ≡ 本仓 ⇒ (a) 的回落类变异被掩盖；故 a 只认「h≥1 ⇒ die」向，回落向交给 a2/b3。
- **R3（P3）** 名册条目缺 `cwd` ⇒ `intercom_roster` 整条不可见 ⇒ 当 0 命中 ⇒ 回落 +「未运行」。否定：**禁**用 pane cwd 充当第二事实源。
- **R4（P3）** e 态：显式全名 + 场上只有 legacy 裸名 ⇒ `rc=0 未运行` 而会话仍在（既有行为，本批不改、不新增提示）。
- **R5（P2 · release note 一句）** 行为变更面：同一全名在**多仓并存**时，从「取首命中、可能改指」→「拒绝并列候选」；唯一命中不变。

## 七、待 PM 拍板（编号回执）

- **D1** 多命中**一律 die、不先按调用方仓过滤**（与「保留跨仓唯一回收」自洽：唯一命中不经锚）——建议：是。
- **D2** e 态保持 `rc=0 未运行`、不新增提示 ——建议：保持。
- **D3** 实现面 = 分支内联三态 + 删 `r2` 两行；**不**复用/不改 `_close_adopt_repo` ——建议：照此。
- **D4** 新用例 **38**（37/09/13 不动）、不入快档 ——建议：照此。
- **D5** 全名分支歧义文案**不出现**「用全名」指路（改「人工核对并关掉多余的」）——建议：照此。

- 修订：2026-11-18 首版（双键三态 + 八态断言 + 仓敏感层选择 + 禁改区 + 否定条件）
