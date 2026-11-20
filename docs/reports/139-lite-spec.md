# T553 / Issue #139 · 联动仓 manifest（arch-lite 判据）

- 状态：待 PM 拍板（D1–D6）· 更新：2026-11-19 · Owner：arch-designer
- 指针：Issue [#139](https://github.com/Nathan3303/nao-skills/issues/139) · PRD `docs/prds/2026-11-19-fleet-manifest.md` · ADR `docs/adr/2026-11-19-fleet-repo-manifest.md` · 代码 `.agents/scripts/nao-fleet.sh:4439`（positional `@` 旧义）`:4564`（名字 scope）`:4597`（放置入参）`:1209-1241`（放置）`:1073-1109`（布局 A 收敛）`:1985-2043`（fleet 三档）· 夹具参照 `tests/t4/cases/33-herdr-placement-key.sh`

**结论：有条件可行**（条件 = §二 通道 + §三 各态断言 + §五 禁改区）。改动面 = 新 manifest 解析器 + `ensure` 相位 1 的「目标仓 / 名字 scope / 放置键 / tab 组前缀」四元解析 + `close` 期望仓回落 + tab label 四处同源。命名契约语法、`fleet_of_invocation`、布局 A 结构判据、零回归断言面**不动**。

## 一、现状断点（已核代码）

- `:4439` positional `@` 段既有语义 = **目标仓路径**（`role="${spec%%@*}"; repo="${spec#*@}"`）⇒ PRD M2 的 `@<code>` 与之**同名不同义**，全批最大歧义源（R1）。
- `:4564`（名字 scope）与 `:4597`/`:4599`（`spawn_one` 第 8 参 = 放置入参）取**同一个** `$fleet` ⇒ 跨仓必然散成多个 workspace（`:1221` `workspace create --label`）。
- 布局 A 收敛按 `tab label == "$name"` 等值判（`:1073-1109`），`tab_id_for` 按 label 查（`:1002`），建/改 tab 用 name 作 label（`:1228`/`:1238`）⇒ 加组前缀必须**四处同源**。
- 全仓无 manifest 读取点（`.agents/` 内 `fleet.yaml` 零命中）⇒ M1 全新；`fleet-scope` 唯一读点 `:2000-2037`。

## 二、数据通道（派单 ①）

- **解析（AC10 单点）**：`fleet_manifest_load <repo_phys>` → stdout **记录流**：`NONE`（无 manifest，属**合法事实**）· `FLEET<TAB><slug><TAB><root_phys>` · `REPO<TAB><code><TAB><path_phys>`×N。rc=0 合法（含缺席）/ rc=1 非法（stderr = `<文件>:<行号> <字段> <原因>`）。**禁** rc 承载「不可知」、**禁**空行承载缺席、**禁**磁盘缓存（AC8 由「每命令一次、无落地」构造性满足）。空输出 = 实现缺陷 ⇒ 调用方 die，**不得**当 `NONE`。
- **消费**：每条命令入口取一次 `MN="$(fleet_manifest_load "$phys")" || die`（**禁** `mapfile < <(…)`：丢 rc，T551 教训）。消费点仅三处：`cmd_ensure` 相位 1（唯一解析）· `cmd_status`（`fleet=`/`code=` 两字段，不可读印 `?`）· `cmd_close`（code ⇒ 期望仓作**回落值**）。
- **判定**：`fleet_repo_resolve <段> <<<"$MN"` → 一行 `OK<TAB><main|linked><TAB><repo_phys><TAB><name_scope><TAB><placement>`；未命中/冲突 rc=1 + stderr 列 codes + slug。纯函数（stdin/stdout），无全局。
- **下传**：`t_fleets[]` 拆成 `t_scopes[]`（名字）· `t_labels[]`（放置）· `t_groups[]`（tab 前缀）；`spawn_one` 增**第 9 参** group（空 ⇒ 逐字旧行为）。**禁全局变量**；`fleet_of_invocation` 不改，manifest 只在其**之外**叠加。
- **manifest 受限子集（零新依赖）**：顶层键仅 `slug` / `repos`；项键仅 `code` / `path`；缩进空格、整行 `#` 注释、单/双引号可省可留；`..`/绝对路径显式允许；锚点/别名/流式/多文档/制表符缩进/未知键 ⇒ 非法。逃逸判据 = **文本看似仓内**（不以 `..` 起首且非绝对）但物理归一后出仓 ⇒ symlink 间接逃逸 ⇒ 拒绝；显式 `..` 出仓 ⇒ 允许（PRD 例 `../api`）。

## 三、各态判据（派单 ②③ · 断言作用域 + 变异必红）

| 态 | 期望结论 | 断言作用域 | 变异必红方向 |
|---|---|---|---|
| A 无 manifest | 与 v0.25.2 逐字一致 | rc=0 · 摘要行 · 名字 `rd-be@<slug>` · `workspace label` · **tab label = 名字（无 `code/` 前缀）** · pane cwd | 无 manifest 也加前缀/改放置 ⇒ 用例 01/33 既有断言红 |
| B 合法·主仓 `ensure rd-be` | 落主仓，scope = slug | 名字 `rd-be@alpha` · tab label `main/rd-be@alpha` · cwd = 主仓 · ws label `alpha` | scope 取仓 slug ⇒ 名字红；前缀缺 `main/` ⇒ 红 |
| C 合法·`ensure rd-be@api` | 落 api 仓，**同一 workspace** | 名字 `rd-be@api` · cwd = api 物理路径 · `workspace_id` **等于 B 的 wsid** · tab label `api/rd-be@api` | 用 code 当放置 ⇒ 多一个 workspace（wsid 不等）红；cwd 用主仓 ⇒ 红 |
| D 合法·`ensure rd-be@alpha`（= slug） | 主仓语义（非 unknown、非 linked） | rc=0 · cwd = 主仓 · tab 前缀 `main/` | 当 unknown 拒 ⇒ rc 红；当 linked 找 code=alpha ⇒ 红 |
| E `@nope` 未命中 | 拒绝并列候选 | rc≠0 · stderr 含**全部** code + slug · 无「已拉起」行 · pane 数不变 | 回落仓 slug ⇒ rc=0 红（AC4） |
| F 各字段非法（逐项） | fail loud 指字段+行号 | 缺 slug · 未知键 · code 重复 · code=`main` · code==slug · code 非法字符或 >16 · path 不存在 · path 非目录 · symlink 间接逃逸 · slug 非法/超 16 | 每项均 rc≠0 + `fleet.yaml:<行号>` + 零 pane；忽略未知键 ⇒ 该行不红（负控咬解析层） |
| G `fleet.yaml` + `fleet-scope` 共存 | 同值放行 / 分歧 fail loud | 同值：rc=0 且放置 = 该值；分歧：rc≠0 点名两文件两值 + 零 pane | 静默取第一档 ⇒ 红（AC6） |
| H `--fleet beta` + manifest(slug alpha) | fail loud（放置键两来源冲突） | rc≠0 · stderr 点名 manifest 值与 `--fleet` 值 · 零 pane；`--fleet alpha` ⇒ rc=0 | 让 `--fleet` 静默生效 ⇒ 红 |
| I 名字预算三向 | fail loud 点名段 | ① 卡 core >32 ② code >16（**落在 manifest 解析期**，属 F）③ full >48（core 31 + `@` + code 16） | 放宽任一条 ⇒ 红；自动截短 code ⇒ 红（AC5） |
| J `close rd-be@api` 唯一 | 回收 api 仓 pane | 回收行 `@` 后字段 = api 物理路径 · 该 pane 消失 · 他仓无副作用 | 期望仓取 `$PWD` ⇒ 报「未运行」/ 误回收红（AC7） |
| K `close rd-be@api` 并列/跨仓同 code | 拒绝列候选、零回收 | rc≠0 · 候选逐条列出 · 两 pane 均存活 · 无「未运行」 | 取首条 ⇒ 红（T551/T552 口径） |
| L 运行期改坏 manifest | 下一次调用 fail loud | 改坏后 rc≠0 · 无沿用上次结果 · 零 pane | 落磁盘缓存 ⇒ 红（AC8） |
| M 后端差异 | 必 PASS 或 SKIP | tmux：rc / 名字 / cwd 断言照跑；tab 分组 ⇒ `[NOTE] backend-no-signal`（后端无 tab 模型）；herdr 0.9.x 无重排 ⇒ 相邻性**不作**判据（同上 NOTE 点名） | 把分组断言写成「相邻」⇒ 恒假/空转 ⇒ 红 |

- 通道自证：`load` 空输出 ⇒ die（不得静默 `NONE`）；`fleet.yaml` 读点计数 ≤1（AC10 静态层）。

## 四、先红后绿与门禁

- 新用例 `tests/t4/cases/39-fleet-manifest.sh`：登记 `run.sh` 的 `CASE_IDS`/`CASE_TITLES` + `backends/herdr.txt`；**不入 `FAST_CASES`**（建 pane 超 15s 预算，同 T551 D2 口径）——实现期以 `--case 39` 直跑。
- 先红：A 应绿；B/C/D/E/F/G/H/I/J/K/L 在旧脚本上必红并留红点；实现后转绿 ⇒ `check` + `test:fast` + 合并前一次 `test:t4:full:dual`（PRD §七）。
- 夹具 hermetic：临时主仓/联动仓（`fx39-main`/`fx39-api`）、`HOME`/`HERDR_*` 单源清理、会话名唯一派生（`qa-T4C39$$` 类，**禁** `pm` 等宿主真名，防 #145 回潮）、pane 一律走 `be_*` 门面。

## 五、禁改区

- `fleet_name_build` / `fleet_name_parse` / `fleet_scope_problem` / `fleet_core_build`（语法与三预算冻结；禁为 code 加第二套构造）。
- `fleet_of_invocation`（AC2 承重墙：manifest 判定在其之外）；`spawn_one` 的「禁由名字反解放置键」禁令；pane label = 会话名（身份唯一源）。
- 布局 A 结构判据「每 tab 恰 1 pane」（只允许把**期望标签**改成组复合标签，收敛语义不变）。
- T551/T552：裸名锚、全名双键三态、`_close_anchor`；`:4197-4203` 全名首命中（#151 已单开，不得顺手改）。
- `.agents/prompts/*`（AC9③ 指针由 PM 落）· `docs/tasks-state.md`（归 PM）· 既有用例断言行（只允许新增 39 与登记行）· 零新依赖 / 零网络。

## 六、风险与否定条件

- **R1（P2 · 最高）** positional `@` 双义（仓路径 vs code）：静默二选一会把「派错仓」伪装成成功。否定条件 = code 与仓路径同时命中且物理路径不同 ⇒ **必 fail loud**（用例 39 有该项）。
- **R2（P2 · 48 预算）** 本设计**不拼接** slug+code ⇒ 三预算数值不变；逼线仅来自长 task（core 31）+ code 16。否定条件 = 出现自动截短 code 或改任何上限 ⇒ 打回。
- **R3（P2）** 跨 fleet 同 code 撞 pane label（全 session 唯一）⇒ 由既有「同名 label 多命中 fail loud」兜底；边界写文档，本批不治理。
- **R4（P2）** tab 前缀四处漏改 ⇒ tab 被收敛回裸名或重复 tab。否定条件 = 四处任一未同源，或 A 态 tab label 出现 `/` ⇒ 打回。
- **R5（P3）** 若未来 herdr 提供重排，则「相邻」可升级为判据；当前禁止把相邻写进断言（避免空转）。
- **R6（P2 · AC8）** 缓存：出现任何落地缓存/跨进程共享 ⇒ 打回（本设计构造性满足）。
- **R7（P3）** manifest 源限调用方仓：从联动仓 `ensure` 无 manifest 语义，属**已知边界**（不是缺陷）；否定条件 = 引入向上查找/自动发现 ⇒ 越界。

## 七、连带同步清单（含 Owner）
- `docs/adr/2026-11-17-fleet-identity-source.md` 与 `2026-11-13-herdr-workspace-scope-key.md`（arch-designer）：已加「后续演进」段并指向本篇；`docs/adr/README.md` 索引已加行。
- `docs/INSTALL.md` · `README.md`（PM / rd-infra · 实现批 M6）：manifest 写法与边界、`@` 双语义、tab 前缀分组。
- `AGENTS.md` 一行指针 + PM 卡的「能派到哪些仓」（PM）+ `docs/tasks-state.md` 状态推进（PM）：事实源 = 各仓 manifest；`.agents/**` 本批不动。

## 八、待 PM 拍板

- **D1** PRD **M2「未命中 ⇒ 回落三档」与 AC4「拒绝并列可用 code」冲突** ⇒ 建议按 AC4 收敛（fail loud），M2 措辞改一行；请确认。
- **D2** `--fleet` ≠ `manifest.slug` ⇒ 建议 **fail loud**（同一 manifest 只有一支舰队名）；替代 = 允许显式覆盖但 warn（会造出「同 manifest 两支舰队」，不建议）。
- **D3** tab 分组唯一形态 = **`<code>/<name>` 前缀命名空间**（不追求物理相邻；tmux 不加前缀，NOTE 点名）。
- **D4** 主仓组前缀固定 **`main`**（不用 slug），与 manifest 保留代号一致。
- **D5** 用例 39 **不入快档**（建 pane 超预算）；全量 + 双后端各一次。
- **D6** AC9③「能派到哪些仓」= 各仓 manifest 为事实源 + `AGENTS.md` 一行指针（本批不改 PM 卡 / `.agents/**`）。
- 附带确认：PRD **AC5 的「code ≤16」判定落在 manifest 解析期**（非命名期），文案点名字段+行号。
