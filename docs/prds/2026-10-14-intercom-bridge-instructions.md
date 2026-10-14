# PRD：子代理会话内协作口径（nao 版 `intercomBridge.instructionFile` + 协议条款）

- 状态：**已交付并发布（v0.18.4 · npm 已重发并核验）** · Owner：PM · 更新：2026-10-14
- **验收记录** = 2026-10-14 PM 验收**通过（AC2–AC7 全过）**：PR [#44](https://github.com/Nathan3303/nao-skills/pull/44) squash **`2a10e23`**（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 独立复跑 **GO**（`check` rc=0 ×2（roles=6 · files 48）· `npm test` rc=0 · 100s · **16/16 PASS · 断言 360→404** · SKIP=0/DEGRADE=0/NOTE=2 · 空载 `test:t4:full` rc=0）+ 契约四查 + 负控四态（含 QA 自建 M-D）+ 能力门实测 · 验收评论见 PR #44
- **发布记录** = 2026-10-14 **v0.18.4（PATCH）已发布**：发布提交 `463f507`（pin 升 0.18.4）· **tag `v0.18.4` + Release 已发**（**AC9 自证：`gh release view` name = `v0.18.4`**）· 发布前置 `test:t4:full` rc=0（空载重跑 1m34s · SKIP=0/DEGRADE=0）· **npm 重发已核验**（用户执行 `npm publish`；`dist-tags.latest` = `0.18.4` + `dist.integrity` 与本地 tarball **逐字节一致**（`sha512-rzP9tuEu…` · 134,484 B））。
- 开工确认卡（2026-10-14 · ask-me 用户拍板 5 项）：D1 范围 = **按 PRD**（模板 + 同目录安装说明 + 协议小节 + `cases/16` 探针 + 文档；**安装器留 ⑨**）· D2 占位符 = **不用 `{orchestratorTarget}`**（走 `contact_supervisor`）· D3 安装说明落点 = **模板同目录 `README.md`**（协议小节给指针）· D4 版本/npm = **v0.18.4（PATCH）+ 发布时重发**（用户执行 `npm publish`）· D5 立项 = **降级 `nao/intercom-bridge`**（无 Issue）· **arch 评审 = 跳过**（Q1 选按 PRD ⇒ 无安装器 ⇒ 无机制语义变更，QA 判定不需要）
- 指针：上游 = 用户 2026-10-14「**继续未完成的任务**」⇒ 台账 **⑦（= T512-②）** · 来源证据 `docs/reports/2026-10-12-pi-subagents-compat-review.md` §4.1（协议/角色卡补「会话内子代理」条款）+ §4.2（nao 版 `intercomBridge.instructionFile` 模板）· 成熟度判定 = 命中 `pm-to-spec.md` §一.4 · **QA 接缝复核** = 2026-10-14 `done(full)`：**T512「自动桥整条死」的前提在 pi-subagents 0.78.0 已过期**（默认 `bridge: active`）⇒ 本批收敛为「**补 nao 语义差距（G1–G3）+ 落模板 + 补协议条款 + 机械探针**」，采 **C1**
- 优先级：中（协作口径固化 · 低成本 · 零运行时代码）· 战略筛子：命中「机制完整性 / 协作语义」→ 做 · MoSCoW：Should · Kano：期望型 · RICE ≈7.2（附录）

## TL;DR（≤5 行）

- **做什么**：① 落 nao 版子代理桥指令模板（补「结果不替代父 done」/「不得以舰队角色发 done」/「证据格式」三条语义）② 协议新增小节「会话内子代理（授权与回执归属）」③ 新增 `tests/t4/cases/16` 只读探针（机械核模板与配置契约）。
- **给谁**：舰队全部角色（父角色与子代理的协作口径）、交付批次 QA、下游三仓维护者（照抄口径）。
- **成功标准**：模板与协议条款齐备且被探针钉住；模板**不含** `{orchestratorTarget}` 占位符；`check` rc=0；断言只增不减（基线 **360**）。
- **不做什么**：不装配置安装器（属 **⑨**）· 不改 6 张角色卡 · 不做真跑子代理的 CI 门禁（LLM 成本/不确定性）· 不含 ⑧ 角色→agent 薄壳 · 不含 `resultDelivery` 外部监听 · 不调整 `control.notifyChannels`。

## 一、问题证据

- **前情（T512 调研 · 2026-10-12 · 只读）**：结论「可组合、非同层替代」；两份建议立项 = 协议条款（§4.1）+ nao 版 `instructionFile` 模板（§4.2）。当时判定「**自动 intercom 桥在当前装机整条死**（pi-subagents **0.77.0** 五个 env 一个都没写）」⇒ 台账 ⑦ 记为「仅显式路径可用」。
- **0.78.0 复现（QA 本轮 · 只读）——前提过期**：`subagent({action:"doctor"})` ⇒ **`bridge: active` · `mode: always` · `orchestrator target: qa-T526`**；`~/.pi/agent/extensions/subagent/config.json` **不存在**（零配置）⇒「父会话 id 自动传递」成立。子代理收到的注入指令与包内 `DEFAULT_INTERCOM_BRIDGE_TEMPLATE` **逐字一致**（marker `Intercom orchestration channel:`）。`{orchestratorTarget}` 取**父会话名**（`pm` / `qa-T526`；无名父会话回落 `subagent-chat-<id18>`）。`subagent_supervisor`（父侧）与 `contact_supervisor`（子侧）**均不依赖 pi-intercom**（native channel 走文件通道）。⚠️ doctor 的 `supervisor channel: available` 是**硬编码常量**，不作证据。
- **nao 语义差距（默认模板缺什么 · 逐条）**：
  - **G1 回执归属沉默**：默认模板只说「返回聚焦结果 / 不把完成交给 supervisor」，**未**规定「子结果 = 证据、**父角色**仍须自行发 `[编号] done`」⇒ T512 §2.1「子代结果被当回执」的风险未被堵。
  - **G2 无舰队身份禁令**：模板零处提舰队身份/命名；子代理若自带外部 `intercom` 工具，可发出**形似 done** 的消息给 PM（T525 那一行只约束 `status`/`close` 的身份判定，不覆盖回执文本）。
  - **G3 无证据契约**：nao 回执要精确数字（命令 + exit + 例数/文件数），模板只要「focused task result」。
- **5 Whys**：口径缺口 ← 桥默认行为与 nao 收口语义无对齐 ← T512 只「列不改」（调研单零代码）← 当时判断「自动桥整条死 ⇒ 显式路径另议」← 该判断随 pi-subagents 升级失效（0.78.0 默认 active），而**回执归属从未有任何文档或机械承载**。
- 证据留痕：T512 报告 · QA 本轮只读复现（intercom `done(full)` 2026-10-14）· `docs/tasks-state.md` 台账 ⑦ · 包内 `docs/configuration.md` §intercomBridge + `src/intercom/intercom-bridge.js`。

## 二、目标指标

- **北极星**：「**子代理结果不替代父角色 `done`**」+「子代理不得以舰队身份回执」成为**常驻口径 + 可机械核对的模板契约**。
- **预期**：① 模板文件落盘且含 G1/G2/G3 三条语义 ② 模板**不含** `{orchestratorTarget}` 占位符 ③ 协议新增小节 4 条（与 T525 现有边界行**不重复**）④ `tests/t4/cases/16` 探针在册且 PASS（pi-subagents 缺失 ⇒ skip 不 FAIL）⑤ `check` rc=0 · 断言只增不减（基线 **360**）。
- **观测**：`npm test` rc + 用例 16 逐条 + `check` rc + 探针负控（改坏模板 ⇒ FAIL）。

## 三、范围 / 非范围

- **范围**
  1. **模板**（新增）`.agents/templates/pi-subagents/intercom-bridge.md`：nao 版子代理桥指令 —— 含 G1（子结果=证据、父角色自行发 done）· G2（不得以舰队角色/`done` 形态回执、不得直发 PM；需决策走 `contact_supervisor`）· G3（证据须含命令 + exit + 例数/文件数 + 路径）· **走 `contact_supervisor`（session-independent）**、**不使用 `{orchestratorTarget}` 占位符**。
  2. **安装说明**（同目录 `README.md`）：`cp` 模板到 `~/.pi/agent/extensions/subagent/nao-intercom-bridge.md` + 用户级 `config.json` 示例（**相对** `"instructionFile": "nao-intercom-bridge.md"` + `"resultDelivery": false`）+ 为何不用占位符（digest 绑父会话 / preflight `host_required`）+ 排障入口 `/subagents-doctor`。
  3. **协议条款**（`.agents/common/intercom-protocol.md` 新增小节「会话内子代理（授权与回执归属）」）：①授权（角色可在自身 turn 内起会话内子代理；默认只读；写须 worktree + 单写集成者；子代理**不属**舰队身份模型 → **指针** T525 那行）②**回执归属（硬性）**：子代理结果 = 证据，**父角色**须自行核对后经 intercom 发 `[编号] done`；PM 只认父角色 done ③**子代理禁令**：不得以舰队角色/`done` 形态回执、不得直发 PM；需决策走 `contact_supervisor` ④证据格式：产物须含命令 + exit + 文件/例数 + 路径。
  4. **机械探针**（新增）`tests/t4/cases/16-intercom-bridge.sh`：只读 Node 探针（import pi-subagents 的 `resolveIntercomBridge`/`validateIntercomBridgeConfig` 语义 + 桩配置）—— 断言**nao 自身契约**：模板存在且可读 · 含 G1/G2/G3 关键条款 · 配置 schema 接受合法/拒绝非法 · **模板不含 `{orchestratorTarget}`**；**不断言 pi-subagents 自身文案**（防版本脆断）；`pi-subagents` 缺失 ⇒ `t4_skip`（不 FAIL）。注册：`run.sh` `CASE_IDS`/`CASE_TITLES` 增 `"16"` + usage `<01-15>` → `<01-16>`。
  5. **文档同步**：`tests/README.md` 用例 16 行（能力依赖 `pi-subagents`，缺则 SKIP）· `docs/releases/v0.18.4.md`（PATCH）。
  6. **台账**：⑦ 收口（`docs/tasks-state.md`）。
- **非范围**（各带理由）
  - **不做配置安装器**（写 `~/.pi/agent/extensions/subagent/config.json` 的幂等安装脚本）：理由 属**机制改动**（需 arch + `check` 幂等守卫），QA 建议留 **⑨**；本批只给「文档 + 一行 `cp`」。
  - **不改 6 张角色卡**：理由 避免复制漂移 + 卡缓存失效；协议是角色侧常驻口径，已足够；后续如需可发现性再单独加一行指针。
  - **不含 ⑧ 角色→agent 薄壳** / **不含 ⑨ 流程 A/B**：理由 各自独立课题（⑨ 还含 worktree→需求分支集成、双源/恢复语义、model 白名单缺口）。
  - **不做真跑子代理的 CI 门禁**：理由 QA 实测真 delegate 有 **LLM 成本 + 不确定性 + run 态副作用**（`/tmp/pi-subagents-*`、`~/.pi/agent/missions/*`），不可作门禁；已在接缝确认阶段做过 1 次一次性证据。
  - **不调整 `control.notifyChannels`（0.78 默认含 `"intercom"`）**：理由 长跑子代理会经 pi-intercom relay 向父会话**本地注入**一条 subagent-control 消息（非 broker、不入 `intercom list`，占上下文）；属低危优化项，本批只写进安装说明「已知行为」。
  - **不含 `resultDelivery` 外部监听**：理由 需外部消费者 ack，非 nao 场景，保持默认 `false`。

## 四、用户场景

- 画像 A（父角色 RD）：起一个只读 scout 子代理 → 子代理回「结果 + 证据」，**父角色**自行核对后发 `[编号] done`（含精确数字）；PM 不会被形似 done 的子代消息误导。
- 画像 B（PM）：只认父角色 `done`；看到 `subagent-*` 会话只当计数（T525），不会被其消息带偏。
- 画像 C（使用者/下游维护者）：按安装说明一行 `cp` + 一段相对路径配置即可让子代理继承 nao 口径，无需写绝对家目录路径。
- 画像 D（维护者）：改坏模板（删 G1 或加回占位符）⇒ 用例 16 当场 FAIL。
- 状态清单（口径语义）：**子代理完成** = 证据，不等于回执；**父角色** = 唯一回执方；**子代理消息** = 只能走 `contact_supervisor` 回父；**零配置** = 桥 active 但用默认模板（nao 口径缺失）⇒ 安装说明可解；**pi-subagents 缺失** = 用例 16 SKIP（不 FAIL）。

## 五、业务规则

- **BR1 回执归属硬性**：子代理 run 结果**只能是证据**；`[编号] done` 只能由**父角色**经 intercom 发出（PM 只认父角色 done）。
- **BR2 身份禁令**：子代理不得以舰队角色名义回执、不得发 `done` 形态消息、不得直发 PM；需决策/阻塞走 `contact_supervisor`（native channel，无需 pi-intercom）。
- **BR3 证据契约**：子代理产物须含命令 + exit code + 例数/文件数 + 路径，供父角色写入回执「测试」栏。
- **BR4 session-independent**：nao 模板**不使用** `{orchestratorTarget}` 占位符（避免 `launchContractDigest` 绑父会话 + preflight `host_required`）；改用 `contact_supervisor` 自解析目标。
- **BR5 落点合规**：模板源在**本仓** `.agents/templates/pi-subagents/`（随包分发、**零绝对家目录路径**）；用户级安装由说明文档给 `cp` + **相对** `instructionFile` 路径；本批**不改**任何用户配置文件。
- **BR6 探针边界**：用例 16 只断言 **nao 自身契约**（模板存在/可解析/含 G1–G3/不含占位符 + 配置 schema 接受-拒绝），**不断言** pi-subagents 的具体文案；`pi-subagents` 缺失 ⇒ `t4_skip`。
- **BR7 零成本**：门禁内**不得**真跑子代理（无 LLM 调用、无网络）；探针必须确定性。
- **BR8 与 T525 不冲突**：协议小节只**指针**引用 T525 的「子代理不属舰队身份模型」行，不重复其内容；⑧⑨ 不混入。

## 六、NFRs

- **时长**：用例 16 为纯本地只读探针（毫秒级），全量门禁仍 ≈2min 量级。
- **可移植性**：`pi-subagents` 缺失 ⇒ SKIP；不依赖 `pi-intercom`、不依赖 tmux、不联网。
- **安全/隐私**：模板与文档**零敏感值、零绝对家目录路径**；本批不写用户配置；探针只在临时目录操作。
- **可诊断**：探针失败须指名缺哪条条款/哪个占位符；安装说明含排障入口（`/subagents-doctor`）。
- **可维护**：模板与协议条款的「唯一事实」分工明确 —— 语义在协议，注入文本在模板，安装步骤在说明。

## 七、AC

- **验证接缝（QA 已确认 2026-10-14）**：新增 `tests/t4/cases/16-intercom-bridge.sh`（只读 Node 探针，import pi-subagents 的桥解析 + 桩配置）+ 复用 `npm test` 门禁（不新增第二接缝）。QA 改定：采 **C1**；**C2 否**（真跑子代理有 LLM 成本/不确定性，不可作门禁）；**C3 否**（纯文档无机械核，pi-subagents 升版可静默改语义）。
- **AC1（主路径 · 接缝复核）**：Given 本批需求，When QA 复核候选，Then 确认/改定并记录日期 —— **已完成 2026-10-14**（QA `done(full)`：C1 + 0.78.0 复现 + G1–G3）。
- **AC2（主路径 · 模板契约）**：Given 模板文件，When 探针解析，Then 文件存在且可读、含 G1（父角色发 done）· G2（身份/直发禁令 + `contact_supervisor`）· G3（证据格式）三条语义，且**不含** `{orchestratorTarget}` 占位符（BR1–BR4）。
- **AC3（业务规则 · 协议条款）**：Given `.agents/common/intercom-protocol.md`，When 读新增小节，Then 四条齐备（授权 / 回执归属硬性 / 子代理禁令 / 证据格式），且**只指针**、不复制 T525 行内容（BR8）。
- **AC4（边界 · 配置 schema）**：Given 合法与非法 `intercomBridge` 配置样例，When 探针走 pi-subagents 的校验路径，Then 合法（`mode`∈{off,always,fork-only} · `instructionFile` 字符串 · `resultDelivery` 布尔）被接受、非法被拒（BR4/BR6）。
- **AC5（异常 · 能力门）**：Given `pi-subagents` 缺失环境，When 跑用例 16，Then `t4_skip`（不 FAIL、不计 DEGRADE）；Given 正常环境，Then 用例在册且 PASS（BR6/BR7）。
- **AC6（负向闭环 · 非空转）**：Given 模板被改坏（删 G1 条款 / 加回 `{orchestratorTarget}` / 删证据格式段），When 跑用例 16，Then 对应用例 FAIL 且指名缺项；还原后全绿（附 md5 证据）。
- **AC7（设计一致性 · 文档与门禁）**：Given 交付终态，When 跑全范围门禁，Then `check` rc=0（roles=6 · **files=48**；46→48 = +2 模板文件，**验收期已订正**）· `npm test` rc=0 · `16` 在册 · 断言只增不减（基线 **360**）· `tests/README.md` 有用例 16 行与能力说明 · `docs/releases/v0.18.4.md` 已落盘 · `docs/tasks-state.md` ⑦ 收口。

## 八、上线闭环

- **版本**：**v0.18.4（PATCH）** —— 改动含 `.agents/`（模板 + 协议，**在 npm tarball 内**）⇒ 是否重发 npm 见开工确认卡（先例：涉及包内文件 ⇒ 重发）。
- **灰度**：不适用（本仓机制/文档）。
- **回滚**：revert 模板/协议/用例/注册并发下一 PATCH；已 push tag 不删。
- **发布前置**：`npm run test:t4:full` **rc=0**（**空载**跑，O-1）。
- **监控**：不适用；指标 = `npm test` rc + 用例 16 逐条 + 断言数 + `check` rc。

## 九、变更治理

- **流程**：降级批次分支 `nao/intercom-bridge`（无 Issue，与 T518–T525 一致）→ PR → QA 独立复核 + 负控（模板改坏三态）→ PM 验收 → RD `--squash` 合并（显式 `--subject` + `--match-head-commit`；**推送用显式 sha 源**）→ PM 发 tag/Release（按 §八 决定 npm）→ PRD 归档。
- **实现分工（同分支顺序写，禁并发）**：① **rd-infra** 落模板 + 安装说明 + 协议小节 + `cases/16` + `run.sh` 注册 + `tests/README.md` + `docs/releases/v0.18.4.md` → 回执；② **qa** 独立复核（探针 + 模板改坏三态负控 + 配置 schema 接受/拒绝 + 能力门）+ 报告 `docs/reports/2026-10-14-T526-qa-verify.md` → `done(full)`。
- **架构评审闸门**：**跳过**（QA 判定：纯模板/协议/文档 + t4 探针，无机制脚本语义变更；**唯一例外** = 若采纳「配置安装器」则须 arch —— 本批已把它列入非范围/留给 ⑨）。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-intercom-bridge-instructions.md`（本文件；归档时登记 `docs/prds/README.md`）；运行时状态记 `docs/tasks-state.md`（⑦ 收口）。
- **交付记录**：PR [#44](https://github.com/Nathan3303/nao-skills/pull/44) squash **`2a10e23`**（main 恰 1 条 · 无 `wip()` · 分支删净）· RD 1 条 + QA 1 条 `wip(T526)` 提交（7 文件 / +283 −2）· 模板 + 安装说明 + 协议小节 + `cases/16`（44 断言）+ `run.sh` 注册 + `tests/README.md` + release notes · QA 报告 `docs/reports/2026-10-14-T526-qa-verify.md`（70 行）· 无 ADR（arch 跳过）· 未 bump 版本（发布节点 PM 执行）。
- **本批残差（已记录）**：**R1** `cases/16` 与 pi-subagents **内部路径 + 3 个导出名**硬耦合 ⇒ 升版漂移时 fail-loud（FAIL 而非 SKIP；不违 BR6 字面）· **R2** `cases/16` 的 F 断言依赖上游默认 `mode=always` 语义 · **O-2** 发布前置闸门首跑出现 case 11（T513 冻结实体）AC12 F1- 两条偶发 FAIL，同环境单跑 `--case 11` 与空载重跑全量均 rc=0（定性为非回归；发布口径 = 遇 FAIL 先复现单例再重跑全量）。
- **待裁量项**：本批关闭 ⑦；维持 ⑧⑨（T512 余项）· ⑫后半 · ①–⑤ 更早遗留 · O-1。

## 附：RICE 与依据

- Reach 2（舰队全角色 + 交付批次 QA）· Impact 2（把「子代理≠回执」从口头口径变常驻条款 + 机械可核）· Confidence 0.9（QA 已在 0.78.0 复现并给出全部差距与探针设计）· Effort 0.5（1 模板 + 1 说明 + 1 协议小节 + 1 用例 + 文档）⇒ **RICE ≈7.2**。
- 战略筛子：命中「机制完整性 + 协作语义固化」→ 本批做；「配置安装器（⑨）· 角色卡改动 · agent 薄壳（⑧）· 流程 A/B（⑨）· notifyChannels 调整」被筛除（各自另批）。
