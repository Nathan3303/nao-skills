# T551 / Issue #146（`close` 裸名仓来源）—— QA 独立复核报告

- 状态：**GO**（0 阻塞 · 3 条 P3 非阻塞建议）· 更新 2026-11-18 · Owner qa
- 复核 HEAD **`1ea8d35`**（分支 `fix/146-close-bare-name`；本地领先 `origin/fix/146-close-bare-name` **6** 提交，`HEAD..@{u}`=0）
- 判据单源：`docs/reports/146-arch-lite.md`（PM 已拍 D1–D4）+ `docs/tasks-state.md`「本批 T551」+ Issue [#146](https://github.com/Nathan3303/nao-skills/issues/146) · 口径：全部自跑（不采信 RD 自述）；变异/换版一律临时副本或临时换入 + **md5 还原**；收尾 `git status --porcelain` 空

## 一、门禁（独立复跑，默认 herdr + 回退 tmux）

- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=7 · files=52` · **rc=0**；`find .agents -type f | wc -l` = **52**（一致）
- 默认 herdr `npm test` **rc=0** → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=9）`；`grep -c '\[PASS\]'` = **2254**；`后端索引：共享 24 / 专有 10 / tmux 专有 2 / PENDING 0`，`对账 = 36（--list 36）`
- `NAO_TERMINAL=tmux npm test` **rc=0** → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=10）`；`[PASS]` = **2027**；tmux 路径无登记集行（AC1.2）
- 例数 `bash tests/t4/run.sh --list | tail -n +2 | wc -l` → **36**（不以最大编号推断；`11` 已退役属正常）· 变更：`5c7463f` = `1 file, +71 −9` · `1ea8d35` = `5 files, +320 −4` · `git diff --stat d1b3524..HEAD` = `6 files, +391 −13`
- 敏感值扫描（`/home/`·`/Users/`·token·`PRIVATE KEY`，扫 6 个改动文件）→ **0** 命中

## 二、先红真实性（换入旧版 `d1b3524`：md5 `b88a6439…` → 还原 HEAD `8550fcb5…`）

- `bash tests/t4/run.sh --case 37`：herdr **rc=1（8 项未过）** · tmux **rc=1（8 项未过）**
- 五态结果 = **与预期一致**：(a)/(b)/(b2)/(c)/(c2)/**(e) 全绿**；**(d)/(d2)/(d3) 全红**（双后端）
- 红点原文（自跑 raw，tmux；herdr 同形态）：
  - **(d)** `rc=1` + stderr `[fleet] close 目标歧义：同 core 的 legacy 裸名 qa-… 与 qa-…@f37a 同时在场（…用全名…）`；本仓/他仓 pane **均存活**（旧版无法完成正确的本仓回收）
  - **(d2)** `rc=0` + `[fleet] 已回收 qa-…（tmux pane %5）@ …/fx37-a`；两条同名 pane **被回收 1 条**（并列未拒）
  - **(d3)** `rc=0` + `[fleet] 已回收 qa-…（tmux pane %7）@ …/fx37-b`；按名误杀他仓 1 条
- herdr 侧 d2/d3 旧版红点不同：`rc=1` + `同名 label 命中 2 个 pane（w1:p2,w1:p3）⇒ 不猜`（无候选 cwd 列表 ⇒ 判据红）
- **c2 旧版亦绿**（tmux/herdr 均在回收前按 pane 真实 cwd 校正 `@`）⇒ 属新增行为断言（可接受，非缺陷）；旧版 4 条负控定位串不存在（①/②/③/⑤）⇒ 4 项 `[FAIL] 变异未应用` + ⑤ 判据未命中（预期）

## 三、RD 判据偏差裁定

### ① (d) 改「本仓带 scope + 他仓 legacy 裸名、名册他仓在前」——**判别力等价，理由成立**

- 实证（纯同名两裸名，自建夹具 = 两仓 pane + 名册两同名条目，HEAD）：
  - tmux：本仓先建 ⇒ 回收**他仓** pane（`%2`，`@fx37-b`）；**反转创建顺序** ⇒ 回收**本仓**（`%4`）⇒ 句柄层按枚举顺序选 pane，锚/仓不参与
  - herdr：两顺序均 `rc=1` + `同名 label 命中 2 个 pane ⇒ 不猜`，两 pane 存活 ⇒ 纯同名形态**跨后端不可断言**
- ⇒ 「无法断言本仓消失/他仓存活」成立（且比文档更强）。替代形态仍咬住缺陷：旧版 (d) 红 / 新版绿（本仓 pane 消失、他仓存活、`@`=本仓物理路径）
- **订正**：`tests/README.md` 用例 37 段「反转 pane 创建顺序即回收他仓那条」方向与实测相反（实测：本仓先建→他仓被回收；反转→本仓被回收）⇒ 建议改「顺序决定被回收对象（实测两向各回收其一）」

### ② `cases/06` 文件数 35→36 —— **只此一行**

- `git diff d1b3524..HEAD -- tests/t4/cases/06-contract-guards.sh` → **1 hunk / 1 行值 + 同行注释**；无其它断言语义变化

## 四、补充项（PM 最高优先）：card 目标锚 —— **PM 读码结论不成立（已实证）**

- 代码：`is_resident=0` 分支 `fallback_repo="${card_path%/.agents/prompts/*}"`（`:4237`），**不是** `ROLE_WS`（那是 `:4233` 的 resident 分支）；`card_path` 来自 `card_role_set`（root ∈ `repo_anchor_roots`，物理）⇒ 剥后缀 = **卡所在仓根**；锚取 `anchor="$(nao_phys_path "$fallback_repo")"`（`:4255`）
- 实证（git 仓 + `.agents/prompts/fxcard.md` + **子目录 `sub`** 调 `close --task T37 fxcard`；roster cwd = 仓根）：
  - tmux：`rc=0` · `已回收 fxcard-T4C37c…（tmux pane %1）@ <仓根>` · pane 消失
  - herdr：`rc=0` · `已回收 …（herdr pane w1:p2）@ <仓根>` · pane 消失（herdr 的 liveness/回收按仓过滤，`@` 直接反映锚/采用值）
- 旁证：即便锚退化，单候选场景仍被 §二「该名唯一 cwd ⇒ 采用」兜回仓根 ⇒ 无「静默未运行」路径
- **但**：case 37 对 card 路径 **0 覆盖**（`grep -nE 'card|resident|is_resident' tests/t4/cases/37-close-bare-repo.sh` = 0）⇒ **P3 覆盖缺口**（arch §二 有明文、用例未断言）
  - 修法（≤15 行）：case 37 增一态「card 目标 + 子目录调用」（夹具加 `.agents/prompts/fxcard.md`，`close --task <T> fxcard` 的 cwd = 仓子目录），断言 `rc=0` / `@`=仓根 / pane 消失 / 无「未运行」
- **结论：无需退回 RD 改代码**；是否补该 P3 断言由 PM 定（成本极低，建议本批补）

## 五、数据通道（派单三段①「禁全局变量隐式传递」）

- `roster_ok` 为 `cmd_close` 内**局部**变量（`:4143`）且只取一次（命缓存）⇒ 符合判据；无新增全局
- `_close_adopt_repo`（`:2205`）经 **bash 动态作用域回写调用方 `repo`** ⇒ 隐式 out-param：3 处调用点均在 `cmd_close`（`:4287`/`:4299`/`:4314`，`repo` 为 `:4141` 的 `local`）⇒ **当前正确**；未来若在未声明 `local repo` 的调用点复用 ⇒ **静默创建全局 `repo`**
- 最小反例：`_set(){ repo=x; }; _h(){ _set; echo "${repo:-unset}"; }` ⇒ `_h` 打出 `x`，且 `repo` 成为全局
- **P3（非本批必修）**：加 1 行 fail-loud 守卫（`declare -p repo >/dev/null 2>&1 || die "内部错误：_close_adopt_repo 须在声明 local repo 的调用点内"`）或改显式 `printf -v`；对应判据 = 派单①之**精神**（现状无隐式全局，仅潜在）

## 六、禁改区（逐字证）

- 全名分支 old `4197-4202` = new `4241-4246`，md5 `8b32340b…` **SAME**
- 函数体 md5 全 **SAME**：`intercom_cwd_for` · `running_verdict` · `term_liveness` · `term_reclaim` · `_term_herdr_busy` · `self_pane_refuse` · `pane_cwd_snapshot` · `repo_anchor_roots` · `nao_phys_path` · `repo_contains_path` · `find_pane_by_title` · `intercom_pane_for` · `_term_tmux_reclaim` · `_term_herdr_reclaim`
- `:2624` 所在函数 `running_verdict` 整函数 md5 **SAME**；其 `intercom_cwd_for "$n"` 调用点 old `:2642` → new `:2684`（随 +42 行平移，无内容变化）
- `tests/t4/lib-backend.sh` 不在 `git diff --name-status`；既有用例仅 `cases/06` 1 行；其余 = 新文件 37 + `run.sh`/`herdr.txt` 登记 + `tests/README.md` 文档 · 成本实测（PATH 计数 shim）：裸名 close 共 **2** 次 git（`card_role_set` 既有 1 + 新锚 1）⇒ **锚增量 = +1**，符合 R4

## 七、五向变异负控 + 探针非空转

- 自跑 `--case 37`（双后端）每向均「已应用 + 必红」：① `RED:rc=0（并列未拒）` ② `RED:rc=1` ③ `RED:rc=0（并列未拒）` ④ herdr `RED:无「close 目标歧义」` / tmux `RED:rc=0（并列未拒）` ⑤ `RED:rc=1`
- 探针 ≤1 非空转：副本「`_INTERCOM_PROBED=0` + 再调」⇒ `a/b 机械旁证 期望=1 实际=2` 双红；**订正 PM 措辞**：仅多调 `intercom_list_json`（命中缓存）**不新增探针进程 ⇒ 仍绿**——判据语义 = 「真实探针进程 ≤1」（arch §四原文），不是「wrapper 调用次数」

## 八、风险覆盖 / 夹具卫生

- **R2**（名册缺 cwd 不可见）· **R6**（herdr 名册缺 cwd 仍可能「未运行」rc=0）：**本批均未被用例覆盖**（case37 无缺 cwd 态）。为什么现在堵不了：R2 只能靠 pane cwd 兜底，而 arch 否定条件明禁「pane cwd 充当名册唯一判据」（第二事实源）；R6 只能把 0 命中改 die ⇒ 破 D1/⑤ 兼容面（旧会话不可回收）⇒ 接受为既有边界，建议随 R5 进 release note 一句
- 夹具：会话名 `qa-T4C37$$`/`rd-be-T4C37$$`（**无宿主真名**）· 名册 **pretty-print**（`JSON.stringify(...,null,2)`）· 夹具根不在任何 git 仓内（前置硬断言 PASS）· pane 全经 `be_*`（无裸 tmux/herdr，仅注释命中）· 探针计数路径烘进源码 · 零网络 / 零敏感值 · 收尾：自建缓存 **11** 个已删（保留他人 8 个）· `pgrep nao-t4` = 0 · 无 lab herdr 残留 · `git status` 空

## 九、结论

- **GO**：门禁双后端 rc=0（36 例 · 2254/2027 断言）· 先红后绿成立 · 禁改区逐字未动 · 五向负控真做且非空转 · 偏差 ①② 均成立 · PM 的 card 锚疑点**证伪**
- 非阻塞（P3）：① case37 补「card + 子目录」一态（arch §二 覆盖）② `_close_adopt_repo` 加 `declare -p repo` 守卫（派单①）③ `tests/README.md` d 形态方向句订正（§五）
- 不改代码、不合并；RD 无需返工；合并/发布归 PM/RD

## 十、增量点检（返工 HEAD `1d8170f` · 2026-11-18）

- 范围：`git diff 1ea8d35..HEAD --name-only` = **4 文件**（`nao-fleet.sh` / `tests/README.md` / `cases/37` / `run.sh`）· `+99 −18`；生产 delta = **+3 行（仅守卫）**；`docs/**` 与 `lib-backend.sh` **0 改动**
- 禁改区仍逐字：15 个函数体（含 `running_verdict`/`repo_anchor_roots`/`_close_anchor`）与全名分支 md5 **全 SAME**（`8b32340b…`）
- 增量门禁（自跑）：`check` rc=0（roles=7 · files=52）· `--case 37` herdr **rc=0 / 28 断言** · tmux **rc=0 / 28 断言** · 双后端 `SKIP=0 · DEGRADE=0 · NOTE=0`
- **P3-1 = 真修（非空转）**：自跑仓库级变异（卡分支锚 → `$PWD`，双后端）⇒ 对外 4 条（rc=0 / `@`=仓根 / pane 消失 / 无「未运行」）仍绿，仅 ③ `close 命中同仓 legacy 裸名` 由 1→0 ⇒ f 必红。**判**：可判定，但**单点且绑实现层日志**（未来 cmd_close 重构换文案 ⇒ 假红）；**新增 P3 加强**：f 再加「他仓同 core 会话」夹具 ⇒ 变异在**结果层**落为「目标歧义 die / 他仓 pane 存活」，可摆脱对 ③ 文案的依赖（≈15 行）
- **P3-2 = 真修（保护面有限）**：实测（抽真脚本 `_close_adopt_repo`+`die`）A 无 repo 变量 ⇒ die rc=1；B 已有**全局** repo ⇒ 守卫放行且**静默改写全局**（`repo=/tmp/one-cwd`）；C 调用方 local ⇒ 只写 local、全局不动。`local -p` **不可用作加强**（bash 5.3.20 实测：调用方 local 与全局都判 `not-local`）。**判：接受并记录**；若要闭合，最小路径 = case 侧静态 lint（每个调用点所在函数须声明 `local … repo`），不建议改运行时通道
- **新增发现（P3）**：P3-2 自证 ② 的「正常回写」一条**空转** —— `repo=` 对空值同样匹配（实测输出 `intercom_cwds_for: command not found` + `repo=`）；建议 stub 一个 cwd 并断言 `repo=/x`（1 行）
- **P3-3 = 一致**：README 方向句与实测逐字一致（本仓先建⇒他仓被回收，反转⇒本仓被回收）；「六向」与 case ①–⑥、`run.sh` 标题一致
- **结论：GO（返工合格）**；新增 2 条 P3（f 结果层加强 · 自证②空转），均非阻塞
