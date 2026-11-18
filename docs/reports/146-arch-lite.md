# T551 / Issue #146 · `close` 裸名解析加仓过滤（arch-lite 判据）

- 状态：待 PM 拍板（D1–D4）· 更新：2026-11-18 · Owner：arch-designer
- 指针：Issue [#146](https://github.com/Nathan3303/nao-skills/issues/146) · `docs/tasks-state.md`「本批 T551」· 代码 `.agents/scripts/nao-fleet.sh:4204-4259`（裸名分支）· `:2162`（`intercom_cwd_for`）· 夹具参照 `tests/t4/cases/09-alias-guard.sh:145` / `13-close-guards.sh:70`

**结论：有条件可行**（条件 = §二 通道 + §四 五态断言 + §六 禁改区）。改动面 = 裸名分支的**仓来源** + 一个新复数查询 + 新用例 37；命名契约 / 句柄层 / status 锚集零改动。语义从「取首命中」收敛为「本仓唯一 / 并列拒绝」，属缺陷修复、无新契约 ⇒ **本批不需要 ADR**。

## 一、现状断点（已核代码）

- `:4206` `repo="$(intercom_cwd_for "$base_name")"` —— 名册**首命中即定仓**；同名跨仓时任一条都能改写 `repo`。
- 该 `repo` 有 5 个消费者：`:4211` 派生 `caller_fleet`（错仓 ⇒ 错 fleet ⇒ 错 `caller_name`）· `term_reclaim` 定位 · `_term_herdr_busy`→`intercom_status_for name repo`（忙闲信号按错仓取状态）· `_term_herdr_liveness` 按 `repo` 过滤 pane · 回收日志 `@ <仓>`。
- `:4207` `fallback_repo="${ROLE_WS[$NAME]:-$PWD}"`；`ROLE_WS` 是 `roles.yaml` 的**相对值** `.`（cmd_close 未归一，ensure 在 `:4252` 归一）⇒ 不可直接当锚。
- `:2162` `intercom_cwd_for` 命中即 `return 0`，**无命中也 `return 0` 且 0 行**：单值通道结构上无法表达「并列」与「名册不可知」⇒ 必须新增复数查询，而非给旧函数加参数。
- 后果闭环 = Issue 实证：调用方仓在跑的 `pm` 被改指他仓 ⇒ liveness 命中他仓 pane ⇒ 忙闲闸门拒 / 他仓 pane 被误回收。
- 定位阶梯：`codegraph_explore` 对本仓 shell 脚本无符号（索引 4 files 全为 `bin/`+`apps/document` 的 JS/TS）⇒ 按项目口径回退 `grep -n` + `sed` 行段；影响面靠 `intercom_cwd_for` 全部 6 个调用点（`:2624`/`:4201`/`:4206`/`:4222`/`:4235`/`:4251`）人工枚举，无遗漏。

## 二、数据通道（派单 ①）

- **锚（调用方仓号）**：仅来自 `$PWD`，**单值、stdout**：`git -C "$PWD" rev-parse --show-toplevel` 物理归一且为 `$PWD` 祖先时取 toplevel，否则取 `pwd -P`；复用 `nao_phys_path:3502` / `repo_contains_path:3513`，禁复制归一逻辑。**禁**以 `$repo` / `fallback_repo` / `ROLE_WS` / 名册反查当锚（循环依赖）。card 目标（`is_resident=0`）的锚 = `card_path` 所在仓（本地事实）。每次 close ≤1 次 git 调用。
- **查询**：新增 `intercom_cwds_for <name> [anchor]` → stdout **0..N 行**；`intercom_roster` 单次、复用 `_INTERCOM_JSON` 缓存（禁新增 probe）；给 anchor 时只留 `cwd` 等于或在 anchor 内（`repo_contains_path`）的条目。
- **可判定性**：`roster_ok` 由调用点**显式局部变量**取一次（`intercom_list_json >/dev/null 2>&1`，命缓存 ⇒ 0 额外调用）。禁全局变量；**禁**用 rc / 空行承载「名册不可用」（`mapfile < <(fn)` 丢 rc，且空行语义已被 0 命中占用）。
- **三态决策（禁猜）**：`h=1` ⇒ `repo=$h`；`h>1` ⇒ `die` 列全部候选；`h=0` ⇒ 保留锚（**禁**回退「名册首命中」）。
- **采用候选后的 repo 复核**：`:4222/:4235/:4251` 由「按仓过滤确认」改为「该名**唯一** cwd ⇒ 采用；>1 ⇒ die；0 ⇒ 保留现值」。理由（实现级）：跨仓 close 采用唯一候选 `pm@x` 时，按调用方仓过滤必得 0 ⇒ `repo` 停在调用方仓 ⇒ herdr liveness 按仓过滤 ⇒ `未运行` rc=0 **假成功**（R2 同类）。

## 三、模式对照（含「维持现状」基线）

- **维持现状（首命中）**：零改动、跨仓即用；代价 = 本缺陷（跨仓改指）⇒ 不采纳。
- **A 复数查询 + 调用点计策（采纳）**：名称路由与仓归属分离，能表达「并列 / 不可知」；代价 = +1 函数 + 1 次 `git rev-parse`。适用：同名跨仓可并存（现状）。
- **B 旧函数加 anchor 参数、早退首个本仓命中**：改动最小；但结构上仍判不出「本仓内并列」，需旁路再计数 = 双判据 ⇒ 不采纳。
- **C 同名不唯一即拒（不回落）**：最安全；破跨仓 close（`cases/09` AC3）与旧裸名回收 ⇒ 行为回归 ⇒ 不采纳。

## 四、五态判据（派单 ②③，每态必有断言）

| 名册态 | 期望结论 | 断言作用域 | 变异必红 |
|---|---|---|---|
| a 无同名 | `h=0` → 锚 → ⑤「未运行」rc=0 | rc + stdout 整行含「未运行（无需回收）」；无 die | `h=0` 改 die ⇒ rc≠0 |
| b 仅本仓 1 | `h=1` → 回收本仓 | `已回收 <名>` 行 `@ ` 后字段 = 本仓物理路径 + 本仓 pane 消失 | anchor 匹配写错 ⇒ 恒空 ⇒ 落回落/未运行 |
| c 仅他仓 1 | `h=0` → 回落「全 session 唯一同 core」 | 他仓 pane 消失 + `@` = 他仓；本仓无同名 pane | 删回落档 ⇒ 报「未运行」 |
| d 两仓各 1 | `h=1` → 只回收本仓，他仓存活 | 本仓 pane 消失 + 他仓 pane 存活 + `@本仓` | 恢复首命中（他仓条目排首）⇒ 选中他仓 |
| e 名册不可用 | `roster_ok=0` → 不过滤、不判并列 | 与基线（case 13 ⑥）rc/输出去向逐字一致；无「目标歧义」 | 当 `h=0` 走唯一回落、或直接 die |

- d 的并列子态（同表判据）：**本仓 2 条** / **本仓 0 + 他仓 2 条** ⇒ `die` 列全部候选 + **零回收**（两 pane 均存活）+ 无「未运行」；变异 = `>1` 取首条 ⇒ 必红。
- 拒绝文案作用域（单行字段）：`die` 必含 core 名 + 每候选 cwd + 指路「`intercom({action:'list'})` 人工核对」；**禁**对同仓两条同名说「用全名 `<core>@<fleet>` 指定」（无区分力，误导）。
- 机械旁证：假探针自增计数文件 ⇒ 每次 close 的 `intercom_list_json` **实际调用 ≤1**（零新增 I/O 面）。

## 五、先红后绿基线（形态建议）

- 新用例 `tests/t4/cases/37-close-bare-repo.sh`：登记 `run.sh` 的 `CASE_IDS`/`CASE_TITLES`（未登记即硬错）+ `backends/herdr.txt` 增 `37 shared —`（不登记 = `[PENDING]` 点名）；**不入 `FAST_CASES`**（名册探针 + 双仓 pane 超 15s 预算）。
- 夹具 hermetic：假探针 `NAO_QA_FAKE_ROSTER`（仿 case 13/09），两仓 `fx37-a`/`fx37-b`，会话名用唯一派生名（`qa-T4C37$$` 类，**禁**用 `pm` 等宿主真名，防 #145 回潮），pane 一律走 `be_*` 门面（双后端）；名册顺序固定「他仓在前」使 (d) 变异必红。
- **先红**：新用例在旧脚本上跑 ⇒ (d)/(d2)/(d3) 三条必红并留红点；实现后转绿，再跑 `check` + 全量双后端。
- **负控五向**（各一句断言）：过滤写空 / 过滤用 `$repo`（循环） / `>1` 取首条 / 删回落档 / `roster_ok=0` 当 die —— 每一向都对应上表一条红。

## 六、禁改区

- `:4197-4203` 全名分支（含 `:4201` 首命中）**逐字不动** —— 同类缺陷出界（R1）。
- `intercom_cwd_for` 签名与语义、`:2624`（running_verdict）调用点：若必须改，只能**追加**可选参且默认行为逐字等价。
- 命名契约 `fleet_*`（build/parse/core/scoped/same_core）、`fleet_of_invocation`、`roles.yaml`、`.agents/prompts/*`。
- 句柄层 `term_liveness` / `term_reclaim` / `_term_herdr_busy` / `self_pane_refuse` / `pane_cwd_snapshot`。
- `repo_anchor_roots:3517`（只读复用，不改语义/输出形状）· `tests/t4/lib-backend.sh` 的 #145 隔离（`HOME`/`PI_CODING_AGENT_DIR`/`HERDR_*` 单源清理）· 既有用例断言（只允许新增 37 与登记行）。
- `docs/tasks-state.md`（归 PM）· 零新依赖 / 零网络。

## 七、风险与否定条件

- **R1（P2）** 全名 `pm@<fleet>` 跨仓同名仍取首命中 ⇒ 同类假成功。出界，建议单开 Issue；否定：若本批顺手改，必须补 d2/d3 等价断言，否则打回。
- **R2（P2）** 名册条目缺 `cwd` 时 `intercom_roster` 整条不可见（awk 需 name/cwd 成对）⇒ 过滤看不到它，靠 pane 证据兜底（tmux `find_pane_for_any_repo` / herdr snapshot）。否定：**禁**用 pane cwd 充当「名册唯一」判据（第二事实源）。
- **R3（P2）** worktree：锚 = 物理 toplevel ⇒ 同 fleet slug 的兄弟 worktree 算「他仓」。否定：**禁**改用 `fleet_scope_slug` 当锚（两条都算本仓 ⇒ 恒拒，跨 worktree 不可回收）。
- **R4（P3）** 成本：+1 次 `git rev-parse`（~5ms）。否定：出现 per-candidate 的 git/roster 调用即打回（§三 计数断言兜住）。
- **R5（P2 · 写 release note 一句）** 行为变更面：同名跨仓、本仓 0 命中且他仓不唯一时，「取首命中」→「拒绝列候选」；唯一命中时行为不变。
- **R6（P3 · 既有边界）** 名册缺该名 cwd + herdr 后端 ⇒ 采用候选后 repo 无法校正，仍可能 `未运行` rc=0。否定：**禁**为堵它把 0 命中改 die（旧会话将不可回收）。

## 八、待 PM 拍板

- **D1** 跨仓「唯一回落」保留（建议保留，否则 case 09 AC3 跨仓 close 回归）——确认不收紧。
- **D2** 新用例 37 **不入**快档（建议不入：超 15s 预算）——拍。
- **D3** R1 全名分支同类缺陷：本批不修、单开 Issue（建议）——拍。
- **D4** 同仓两条同名只能指路人工 `intercom list`（不加 `--repo` 旗标，建议不加）——拍。

- 修订：2026-11-18 首版（五态判据 + 禁改区 + 先红后绿 + 风险否定条件）
