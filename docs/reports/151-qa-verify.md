# T552 / Issue #151 · QA 完整复核（fix 轻通道）

- 复核对象：分支 `fix/151-close-fleet-name` · HEAD `966c85a` · 基线 `4b3019e`（含台账「本批 T552」）
- 判据单源：`docs/reports/151-lite-spec.md`（v2 · D6/D7）· Issue #151 · `docs/reports/146-arch-lite.md` §七 R1
- 方法：**不采信 RD 自述，全部自跑**。只读仓内文件；变异只用临时副本 + md5 还原。收尾：`git status --porcelain` 空、脚本 md5 `20e97e15…` = HEAD blob、无残留夹具缓存 / 无孤儿 pane / 无孤儿 herdr server
- **结论：CONDITIONAL** —— 核心修复与判据质量（先红真实性 / D6+D7 / 禁改区 / 五向负控 / 探针非空转）我复核通过；合前**必修 P1 一处**（快档门禁被打断），另 P2 一处（同名同仓重复态的文案与披露）

## 一、门禁（自跑，逐条命令 + 数字）
- `bash .agents/scripts/nao-fleet.sh check` **rc=0** · `roles=7 · files=52`（与 PM 对照一致）
- 用例数（`tests/README.md` 口径 `run.sh --list | tail -n +2 | wc -l`）= **37**
- `--case 38`：herdr **20 PASS** / 0 FAIL / `NOTE=1`（`38:backend-gate`）rc=0；tmux **21 PASS** / 0 FAIL / `NOTE=2` rc=0
- `npm test` 双后端：herdr **rc=0**（PASS 2289 · FAIL 0 · SKIP=0 · DEGRADE=0 · NOTE 10/白名单 10）· tmux **rc=0**（PASS 2063 · FAIL 0 · SKIP=0 · DEGRADE=0 · NOTE 12/白名单 12）
- 禁改区回归 `--case 06/09/13/37` × 双后端 = **8/8 rc=0 PASS**（NOTE：06 两侧各 2 条 · herdr 09 1 条，全在白名单内）

## 二、先红真实性（旧脚本 `2477b70`，md5 实测 `2075c86f59bfead01d28c12bd70e2dfb`）
- `T38_FLEET_SCRIPT=<旧脚本> --case 38`：tmux **FAIL=2**（c/d，红点原文 `RED:rc=0（并列未拒）`）· herdr **FAIL=2**（c/d，红点原文 `RED:无「close 目标歧义」`）
- 独立探针（复刻夹具、直接读 rc/stdout/pane 存活）补出红点背后的行为：
  - tmux c：旧 rc=0 **并回收了并列中的 1 条**（1/2 存活，`已回收 …@ PRC`）
  - tmux d：旧 rc=0 **按首命中回收了「他仓」pane**（本仓 pane 存活，他仓 pane 被杀，`@ PRB`）⇒ #151 形态复现：不是「没拒」，是**静默改指并回收**
  - herdr c/d：旧 rc=1，但理由来自 **pane 层**「同名 label 命中 2 个 pane ⇒ 不猜」，**不是** h>1 判据
- a/b/b3/a2/e/f 在旧脚本上**确为绿**（双后端实测）⇒ 不作先红证据，与判据一致
- 纠正（成立但不完备）：「herdr 的 pane 层本就挫 ⇒ rc 已非 0」—— 实测**并列里只剩 1 个存活 pane 时，旧脚本 herdr 会 rc=0 静默回收他仓 pane**（我造的 h 态：old rc=0/0-1 存活，new rc=1/1 存活）。故 herdr 的 c/d 红点是「label 重复」另一机制的红，不能当 h>1 检测的独立证据（P3）

## 三、D6/D7 是否到位（读码核对 + 运行佐证）
- §一 四层口径与代码逐条对上：① liveness **两后端按 repo**（tmux `intercom_online name repo` + `find_pane_for name repo`；herdr `repo_contains_path` 过滤快照行）· ② 忙闲 herdr **按仓**（`_term_herdr_busy` → `intercom_status_for name repo`，`:687/:739` 才命中 `cc==a`）· ③ 文案层 tmux `warn "…（cwd=${repo}）"`（herdr 同分支确无 cwd 字段）· ④ 句柄定位/回收**不按 repo**（tmux `find_pane_for_any_repo` 无 repo 参；herdr reclaim 按 `$1==n` 取行）
- **D6 的关键订正正确**：旧版把 ④ 与 liveness 混谈才是错的，代码层面 ④ 确实与 repo 无关
- b3/a2 确按「**不退化**」写：b3 = 结果层 rc≠0 +「拒绝回收」+ `名册状态=working` + pane 存活（桩 pi idle ⇒ 拒绝理由确指第二名册信号，实测文案即「…第二信号」）；a2 = **结果层主**（rc≠0 且不报「未运行」，与 e 态 rc=0 对照成立）+ **辅助条**（tmux `cwd=$PRA`，herdr NOTE 后端无该信号）⇒ D7 到位

## 四、RD 自报偏差 ②（`repo="${fallback_repo}"` 花括号）
- 事实：`cases/37` 负控⑤ 用字面量 `'    repo="$fallback_repo"'` + `head -1` 变异；花括号使该字面量在脚本内唯一（`grep -cF` = 1；去括号则 2 处且会命中在前的全名分支）
- **实测「有人去掉花括号」**：`--case 37` **红**（FAIL=2：`负控⑤ 变异未应用（实现写法已变…）`＋`负控⑤ … 负控未命中：期望 RED，实际 GREEN`）⇒ **不是静默假绿，能自曝**
- 判：① 属「为让测试的变异锚保持唯一而改产品写法」的**规避形态**（行为等价、未削弱任何断言，不是作弊级）；② 更正修法 = 把 37 负控⑤ 的锚换成语义唯一锚（如裸名分支 `mapfile -t name_cwds < <(intercom_cwds_for "$base_name" "$anchor")` → 替换成 die 行，语义与现状完全相同），产品行即可恢复与相邻行一致的 `repo="$fallback_repo"`；另建议变异 harness 把「锚未命中」与「**锚不唯一**」分成两种文案（现在统称「变异未应用」，误导排查方向）；③ **不建议**加「字面量必须在脚本内唯一」的静态断言 —— 那会把格式选择冻成契约
- P 级：**P3**（本批登记即可，下一批顺手做）

## 五、禁改区逐字证（`git diff` 白名单 + 函数体 md5，不采信自述）
- 脚本 diff 仅 **3 个 hunk**：`:4147` 局部声明（去 `r2`、加 `scoped_cwds`）· `:4245` 注释 3 行 · `:4249+` 全名分支 4 行换 12 行 —— 无其它 hunk
- 13 个函数体 md5 **新旧逐一相同**：`intercom_cwd_for` `intercom_cwds_for` `_close_anchor` `_close_adopt_repo` `term_liveness` `term_reclaim` `_term_herdr_busy` `self_pane_refuse` `pane_cwd_snapshot` `repo_anchor_roots` `find_pane_for` `find_pane_for_any_repo` `intercom_status_for`
- 裸名 `else` 整段在 hunk 边界之外（零改动）· `cases/09` `13` `37` · `lib-backend.sh` 均未出现在 diff 名单 · `r2` 无残留引用
- 计划外改动 1 处：`cases/06` 扫描面计数 `36→37`（新增用例文件的**必要联动**，提交信息已披露；spec §四/§五 未列 ⇒ 文档小缺口 P3）

## 六、五向变异负控 + 探针非空转（自跑）
- 五向锚在脚本内**各唯一**（`grep -cF` 全 = 1，且都含 `scoped_cwds` ⇒ 锁定新分支）；用例红点：①`RED:rc=0（并列未拒）` ②同 ③`RED:rc=0（忙闲信号没读到）` ④`rc=1` ⑤`RED:rc=1` —— 五向真做，非声明
- 「探针每命令 = 1」非空转：副本强制全名分支做第二次**真实**探针（清 `_INTERCOM_PROBED`/`_INTERCOM_JSON` 后再调）⇒ 状态 a 实测 `probes=2`（未变异 `=1`）⇒ 该断言会红

## 七、风险判定
- R1 非对称：**如实披露且可接受**。NOTE `38:backend-gate` 的理由经代码佐证属「后端无该信号」（tmux 忙闲 `intercom_status_for "$name"` 无 repo 参；herdr「无法回收」warning 无 cwd 字段），不是「证不出来」；tmux 侧 repo 正确性除 a/b/e 外确只剩文案可观测，与后端结构一致
- R4：显式全名 + 场上只有 legacy 裸名 ⇒ 新旧脚本 **rc=0 且 stdout 逐字相同**（双后端实测），一致
- **新发现（P2）**：同名同仓重复（名册两条同 name **同 cwd**）从旧「rc=0 回收其中 1 条」变为新「rc=1 die」。方向安全（不再静默误杀），但 ① 未在 R5/release note 披露（R5 只写「多仓并存」）② 用例 38 无该态 ③ 文案把同一路径列两次，且指路「同名同 fleet 多仓没有别的写法可区分」在本场景是错的（同一仓可直接关掉多余会话）。修法：die 前对候选 cwd 去重 + 同 cwd 多条改文案「同名同仓 N 条：先 intercom list 关掉多余会话」；用例补 1 态（或登记 R6 并在 release note 覆盖）

## 八、夹具卫生
- 会话名 `qa-T4C38$$` 唯一派生，**无宿主真名**（`pm` 仅出现在注释）· 名册 pretty-print（`JSON.stringify(…,null,2)`，判据前提）· 夹具根在 `/tmp/nao-t4.*`，用例首条断言「不在任何 git 仓内」双后端 PASS · 全程 `be_*` 门面（无裸 `tmux`/`herdr` 命令）· 零网络（无 curl/npm）、零敏感值（仅 spec 里 Issue URL，属仓内既有惯例）
- 缓存：成功路径 `t4_cache_cleanup`（日志「已清理」）；失败路径按 BR7 保留（我先红跑产生的 12 个 `/tmp/nao-t4.*` 已由我清理）

## 九、P 级与结论
- **P1（必修，一行）**：`cases/38` 未登记进 `run.sh` 的 `FAST_SKIP_*` ⇒ 实测 `bash tests/t4/run.sh --fast` **rc=1**「参数错误: 快档分类缺失用例 38」，即 `npm run test:fast`（AGENTS.md「日常迭代用快档」）被打断；基线 `4b3019e` 快档是绿的（37 已登记）⇒ **本批引入的回归**。修法：`FAST_SKIP_DOUBLE` 追加 `38`（依据一句：假名册 + 三仓 pane + 五向变异副本，单价超预算），`docs/reports/143-profile.md`「未覆盖」补 38
- **P2（建议本批）**：同名同仓重复态（§七）—— 文案去重 + 同仓措辞 + 用例补态（或登记 R6 且 release note 覆盖）
- **P3（登记）**：① 花括号格式耦合（§四）· ② b3 断言行在 tmux 写「忙闲按**他仓**命中」，而 tmux 实为按名（NOTE 已披露，但 PASS 行措辞误导）· ③ herdr 侧 c/d 红点属另一机制（§二，建议用例注释补「并列只剩 1 个存活 pane 时旧脚本会静默回收」）· ④ `cases/06` 计数联动未列入 spec
- **结论**：CONDITIONAL —— P1 修完（+ P2 文案/披露）即可 GO；功能行为、双键三态语义、禁改区与判据可追溯性我复核通过

## §追加 · 返工点检（HEAD `aa95463` · 6 文件 +96 −37 · 只核三项 + 回归）

- 方法同首轮：只读 + 临时副本变异；收尾 `git status --porcelain` 仅本报告、13 个禁改区函数体 md5 全部 SAME、裸名 `else` 整段 md5 与 `966c85a` 相同

### 判定一 · P1 真修：**GO**
- `run.sh --list | tail -n +2 | wc -l` = **37** · `run.sh --fast` **rc=0**（"白名单已跑 14 例 · 跳过 23 例"，跳过清单含 `37 38`，未覆盖声明含「替身重档 … 37 38」）；`38` 已进 `FAST_SKIP_DOUBLE`、`143-profile.md` 未覆盖段已补 38（含 herdr 22.6s / tmux 8.3s 依据）⇒ 三类并集 + `FAST_CASES` == `CASE_IDS` 自检通过（起跑期即该自检，rc=0 即证）

### 判定二 · P2 真修：**GO**
- g1（同 name 同 cwd ×2 · 1 pane）：`--case 38` 双后端 PASS ⇒ 实测 rc=0、pane 消失、`@`=本仓、无「歧义」= 去重后采用（PM 期望语义）
- 真多仓仍 die 且列**去重后**候选：c/d 双后端 PASS；我另跑混合态（PRB,PRB,PRC）双后端一致：`rc=1` · `对应 2 个仓的会话：PRB PRC（名册共 3 条记录，含同名同仓重复条目）… 同仓重复条目不必区分仓，不要当成多仓歧义` · 2/2 pane 存活
- **我自跑 g 态变异（去掉去重守卫行）**：`--case 38` tmux **FAIL=4**（`g1 … RED:rc=1` + g2 三条全红）⇒ 去重判据不空转
- 两条文案分工 **不误导**：纯重复 ⇒ 静默采用（不出歧义文案）；无重复多仓 ⇒ 旧「N 个 cwd … 多仓」；重复+多仓 ⇒ 新「N 个仓 …（名册共 M 条记录）」且显式说「不要当成多仓歧义」

### 判定三 · P3-a 真修：**GO**
- 反向变异（裸名分支产品行改成等价 `repo="${fallback_repo}"`）：`--case 37` **PASS**，负控⑤ **仍咬住**（`负控命中：RED:rc=1`）⇒ 新锚与产品行写法**已解耦**
- 「锚未命中」自检：把锚行改成等价 `${roster_ok}` ⇒ **FAIL=3**，文案点名 `负控⑤ 锚未命中（实现写法已变：裸名分支的名册可用性闸门行）` ⇒ 红而不再假绿
- 「锚不唯一」自检：在文件尾加一处同形行（`grep -cF`=2）⇒ **FAIL=2**，文案点名 `锚不唯一（2 处命中：该行不再是裸名分支独有）⇒ 改用语叉唯一的锚` ⇒ 两种写法漂移都能自曝且指路，不再出现「统称变异未应用」的误导
- 复核：37 的 8 个变异锚、38 的 5 个变异锚在新脚本内 `grep -cF` **全 = 1**

### 判定四 · 回归：**GO**
- `--case 06/09/13/37/38` × 双后端 = **10/10 rc=0 PASS**（`NOTE` 全在白名单：38 herdr 2 / tmux 2 · 06 两侧各 2 · herdr 09 1）
- 我另跑全量 `npm test`（herdr）：**rc=0**，PASS **2291** / FAIL 0 / SKIP=0 / DEGRADE=0 / NOTE 11 全白名单（基线 2289 → +2 = g1 一条 + g2 herdr 一条；与 tmux 侧 2063→2067 的 +4 口径自洽）
- 断言数核对（`[PASS]` 计数）：`--case 37` = **33** · `--case 38` = **22** —— 与 PM 自证一致

### 新发现（均 P3，不阻塞；据上一轮 P1 教训建议登记 follow-up）
- ① **裸名分支未同步去重**：同 name 同 cwd ×2 走 `close --task` 仍 die，且把同一路径列两次（我实测 rc=1、候选同一路径出现两遍）⇒ 与全名分支新语义不一致；跨 #146 出界，建议登记（或在 PM 裁定下同批补 dedupe）
- ② 混合态（重复 + 真多仓）的**专用文案分支无用例覆盖**（我手工跑 m 态证其正确）⇒ 建议 case 38 补一态，或把 m 并入 g
- ③ g2-herdr 复用 `v_busy_refuse`（名为忙闲、实为 label 不猜），且未绑理由文本「同名 label 命中 2 个 pane」⇒ 任何拒绝都吃绿（弱断言）；建议断该理由串
- ④ 去重单位是「物理 cwd」而 die 文案说的是「N 个仓」；同仓不同子目录各 1 条 + 重复条目时会说「2 个仓」（措辞略松）
- ⑤ 38 标题仍为「五向变异负控」，去重未纳入负控（我手动验证必红）；若守「每条新判据均有负控」纪律，建议加 ⑥

**返工复核结论：GO**（P1 / P2 / P3-a 三项均真修且我有独立反证；回归 10/10 + 全量 herdr 全绿；遗留仅 5 条 P3 建议）

## §追加二 · 终检（HEAD `12f92d8` · 5 文件 +134 −33）—— **GO**
- 裸名分支**只改文案**：三态行（`==1` 采用 / `>1` die / 0 保留锚）、`roster_ok=0` + `intercom_list_json … && roster_ok=1`、`mapfile … intercom_cwds_for "$base_name" "$anchor"` 在 `aa95463`→`12f92d8` 两树各 1 处**逐字相同**；`cases/37` 零改动（diff 名单无它）且 33/33 双后端 PASS；14 个禁改区函数体 md5 全 SAME（新 helper `_close_dedupe_cwds` 为新增，未触碰既有函数）
- **B 裁定语义安全（实测）**：裸名 + 同 name 同 cwd ×2 + **2 个存活 pane** ⇒ 双后端 rc=1、两 pane 均存活（零回收）、文案「1 个路径 …（名册共 2 条记录）… 同仓同名多 pane 时本命令不猜哪一个是目标」⇒ die 条件仍按**原始条数**，去重只入文案 ✓（与 `cases/37 d2` 同口径）
- ②③⑤⑦ 均咬住（我自跑反证，非采信自述）：m 态在正式脚本双后端正确；**独立变异 A**（删 helper 去重守卫）⇒ case 38 **FAIL=6**（g1 `RED:rc=1`、g2 三条、m「名册共 3 条记录」）；**独立变异 B**（改 herdr 拒绝理由、判定不变）⇒ herdr case 38 **g2 FAIL**，红点原文 `拒绝理由未绑定（缺「同名 label 命中 2 个 pane」）`，且 ⑦ 锚自检点名 `锚未命中`
- 回归：`--fast` rc=0 · `check` rc=0（roles=7/files=52）· `--list`=37 · `--case 06/09/13/37/38` × 双后端 **10/10 PASS**；断言数自数 `--case 37`=**33**（双后端）· `--case 38`=**27**（herdr）/ **29**（tmux）—— 与 PM 自证逐项一致
- 新发现：无阻塞项。仅 2 条 P3 nit：① m 的「不说「N 个仓」」断言是**全输出子串扫描**，将来若有别的路径打印「个仓」会假红；② 负控⑦ 的锚落在句柄层 `_term_herdr_reclaim` 文案上 ⇒ 该文案日后合法改写会让 38 红（自检点名「锚未命中」，非假绿，且已在用例注释/spec 披露，无需动作）
