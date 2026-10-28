# codegraph 插件引入舰队机制：四态检测 + 原生入口口径 + 本仓自建索引

- 状态：**草稿 v3（QA 接缝 + arch 完整评审已过；7 处按裁决修订 —— 待 Issue 与开工确认卡）** · Owner：PM · 更新：2026-10-28
- 指针：候选批次 T532 · 接缝报告 `docs/reports/2026-10-28-T532-qa-recon.md` · **arch 评审 `docs/reports/2026-10-28-T532-arch-review.md`（裁决 A1–A7）** · **ADR `docs/adr/2026-10-28-codegraph-plugin-adoption.md`** · 现行资产 `.agents/skills/codegraph.md`（52 行 CLI 口径）· `bin/nao-skill.js:101`（`PI_PLUGINS.codegraph`）· `.agents/scripts/nao-fleet.sh:279`（`check_codegraph`，仅探 CLI）· `:1200-1215`（CodeGraph 段，`Pending Changes ⇒ rc=1`）
- 用户拍板 6 项（2026-10-28）：warn 门禁 / 只检测 + 文档指引 / 原生优先 + CLI 回退 / 本仓起索引 / v0.20.0 MINOR + npm 重发 / arch 完整评审

## TL;DR

- **做什么**：把 `@sean_pedersen/pi-codegraph` 从「插件清单里的一行」升为舰队机制一等公民 —— ① `check` 增 **codegraph 四态检测**（判定顺序短路 · 文本作契约前缀 · **含把现存 `Pending ⇒ rc=1` 降为 warn 的显式豁免**，arch A1）② 技能与 6 张角色卡改口径：**`codegraph_explore` 为唯一硬编码原生入口 → CLI → `grep -rn` + 行段** ③ 本仓 `nao-skills` 自建索引（受资源/并发实测门约束）并订正 `AGENTS.md` ④ `.gitignore` 单文件 ignore 插件副产物 ⑤ `ensure` 在 `spawn_one` 内注入 `CODEGRAPH_TELEMETRY=0`。
- **给谁**：6 个角色（RD 定位 / QA 找受影响测试 / arch 影响面 / PM 验收读码）。
- **成功标准**：`check -v` 在四态各给一行可断言提示且 `check` rc 不受 codegraph 影响；6 卡 + 3 清单 + `pm-operations.md` + `templates/AGENTS.md.example` 无纯 CLI 单口径残留；本仓 `codegraph status` 报 up to date 且 `git status` 干净。
- **不做什么**：不自动安装插件、不自动建索引、不改插件上游、不引入新 npm 依赖、不把插件缺失变成派发门禁。

## 一、问题证据

- **机制口径过时**：codegraph 全按 CLI 写 —— 技能 `.agents/skills/codegraph.md` · 6 张角色卡 **13 行 / 16 次**（实测 `grep -rn codegraph .agents/prompts/*.md | wc -l` = 13，含单行双次）· 清单 **4 处 / 3 文件**（`architecture-designer` / `qa` ×2 / `rd-fe`）· 另漏两处纯 CLI 口径：`.agents/skills/pm-operations.md:25`、`.agents/templates/AGENTS.md.example:18,31`。插件提供的原生工具在机制内**零提及**。
- **检测面缺失**：`cmd_check` 的「pi 插件」段（`nao-fleet.sh:1217`）只检 `pi-web-access`；插件装没装机制不知道。`check_codegraph`（`:279`）只判 `command -v codegraph` + `.codegraph/`。
- **实测本机现状（2026-10-28）**：CLI 不在 PATH · `pi list` 4 包（无 pi-codegraph）· 本仓无 `.codegraph/` · `check` rc=0（`roles=6 · files=50`）。
- **插件行为（源码 v0.1.0 + QA 实测）**：仅当 cwd 有 `.codegraph/` 才激活 → spawn `codegraph serve --mcp` → `tools/list` → `pi.registerTool`（**原始名，无 `mcp__` 前缀**）→ 报错路径**静默 return**。
- **工具集合是版本相关（QA S1）**：上游当前**默认只暴露 `codegraph_explore`**，其余 8 个需 `CODEGRAPH_MCP_TOOLS`；9 个是旧/显式配置态的数目 ⇒ 「9 个工具」不可作为机制事实。
- **system prompt 注入在舰队内不生效（QA S3，推翻 v1 假设）**：舰队恒带 `--append-system-prompt`，pi 1.4.0 下**该开关整体抑制 `.pi/APPEND_SYSTEM.md` 读取**；且插件 fallback（`return { systemPrompt }`）在 1.4.0 是**死代码**（只认 `systemPromptOptions.sections`）⇒ 舰队 6 会话**零注入**，既无重复也无顺序问题。指引只能由 nao 技能/卡片承载。
- **副产物残留（QA S3 实测）**：插件在项目根创建 `.pi/APPEND_SYSTEM.md`（不存在时）并在 `session_shutdown` 删除；但 `pi --help -e` 类非会话调用也执行工厂且不触发 shutdown ⇒ **永久残留**，使 `git status` 变脏，且该文件是 trust 门控资源。
- **既有代码与「warn 门禁」冲突**：`nao-fleet.sh:1207` 在 `Pending Changes` 时置 `rc=1`（QA 指出，PM 已复核）⇒ 与拍板的 warn-only、与「不放松既有断言」二选一，需 arch 裁定。
- **外部性**：插件零网络；**codegraph CLI 有匿名遥测**（`CODEGRAPH_TELEMETRY=0` / `DO_NOT_TRACK=1` 可关），`PI_OFFLINE` 对两者无效。
- **资源量级（QA 估算，需实测）**：本仓 50 文件 → init 秒级、`.codegraph/` MB 内；`serve --mcp` **100–250MB/实例**、6 会话 **0.6–1.5GB**。

## 二、目标指标

- **检测覆盖**：`check -v` 四态各一行可断言文本（**契约化范围 = 固定前缀 + 命令子串**，不断言整行）；`check` 总耗时增量 ≤ 0.2s（只读两份 settings.json；**禁用 `pi list` 作检测源**，实测 0.92s 且项目级不显示）。
- **口径统一**：6 卡 + 3 清单 + `pm-operations.md` + `templates/AGENTS.md.example` 中 `codegraph` 提及**全部**为三段式或单句指针；唯一硬编码工具名 = `codegraph_explore`（卡内其余 8 个工具名零命中）。
- **单源可验**：包名在 `nao-fleet.sh` 常量 `CODEGRAPH_PKG` 与 `bin/nao-skill.js` `PI_PLUGINS` 各一处，由用例**等值断言**兜住（漂移即 `npm test` 硬失败）；**禁止运行时跨语言抽取**（取空即静默假阴性）。
- **不误伤**：plugin/索引缺失时 `check` rc 不受影响（Pending 项按 arch 裁定）、`ensure` 正常拉起、`npm test` 全绿。
- **本仓自用可证**：`codegraph status` up to date；会话退出后 `.pi/APPEND_SYSTEM.md` 不存在，`git status --short` 干净。

## 三、范围 / 非范围

范围内：

1. **`check` 四态检测**（`.agents/scripts/nao-fleet.sh`）：判定源 = 两份 `settings.json` 的 `packages`（`${PI_AGENT_DIR}` + `<cwd>/.pi/settings.json`，**顺带修 `:1219` 硬编码 `$HOME/.pi/agent` 的既存缺陷**），包名取 fleet 常量 `CODEGRAPH_PKG`（**运行时不 sed 抽 `bin/*.js`**，arch A2/BR5）。**判定严格短路**：① 声明 ② `command -v codegraph` ③ `<repo>/.codegraph` ④ `codegraph status` 文本；单实现 `codegraph_state <repo>`，`cmd_check`（对 `$PWD`）与 `ensure`（对各 repo）共用，**删除 `:1200-1215` 重复 awk 段**；文本常量集中 `CG_MSG_*`。6 行契约：`· 插件未声明` / `! 已声明但 CLI 不在 PATH` / `! 已就绪但无索引` / `✓ 齐备` / `! 索引 pending` / `! status 输出不可解析`。**全部 warn，`--strict` 亦不升级**（A1）。
2. **`ensure` 提示 + 遥测**：复用 `codegraph_state`（不阻塞拉起）；在 **`spawn_one` 的 `inner` 命令**注入 `export CODEGRAPH_TELEMETRY=0`（tmux pane 继承 server 环境，ensure 侧 export 传不过去，arch A3）；**不加 `DO_NOT_TRACK=1`**（过宽）。
3. **技能改写**（`.agents/skills/codegraph.md`）：三段阶梯 —— ① 原生入口（`codegraph_explore`；其余工具**不写死**，注明随 CLI 版本 / `CODEGRAPH_MCP_TOOLS` 变化）② CLI（保留为回退，命令须真实：`codegraph init` **无 `-i`**）③ `grep -rn` + 行段。保留 Token 纪律与「禁 cat 全文」；新增两处一句话：**「有插件无索引/无 CLI ⇒ 不生效」** 与 **「插件不供 system prompt 指引（截至 pi 1.4.0 / pi-codegraph 0.1.0），口径由本技能承载」**；副产物小节（`.pi/APPEND_SYSTEM.md` 会被创建/残留 + 用户手工清理 `rm -f`，机制不代跑）。
4. **6 张角色卡 + 3 清单 + `pm-operations.md`**：逐字口径「代码定位：原生入口 `codegraph_explore`（需插件 + CLI + 索引齐备）→ CLI → `grep -rn` + 行段；详情见 `@.agents/skills/codegraph.md`」；每卡 `version` +1、`updated` 更新；「插件不供指引」**不进卡片**（只技能一处，arch A5）。
5. **`templates/AGENTS.md.example`**：把 `codegraph sync` 单口径改为三段式指针 + 副产物一句（下游无 gitignore 管理机制，只给指针）。
6. **本仓环境自用**（维护型 `M20261028-codegraph`）：**前置 = 先跑 arch §三 T1/T2 冻结真实命令与 `status` 文案**（文案一落地即错的风险，arch §五-6），再装 CLI → `pi install` 插件 → `codegraph init` → `codegraph status` 验 + **资源/并发门（A6）**；遥测关闭可验证。
7. **`AGENTS.md` 订正**：「本仓无 CodeGraph 索引」→「已有索引 + 原生入口优先」，指针式不复制正文。
8. **`.gitignore`**：加 `.pi/APPEND_SYSTEM.md` **单文件**（不 ignore 整个 `.pi/`；arch A4）。
9. **回归护栏**（`tests/t4/cases/18`）：四态静态断言（夹具 `HOME` + PATH stub + 夹具 `.codegraph/` + 必跑 `check -v`）+ **第五组「齐备 + pending ⇒ rc=0」** + 文本变异负控（改提示文本 ⇒ 断言失败，`check` rc 不变）+ `spawn_one` 遥测字面量断言 + 包名**等值断言** + `run.sh` 注册 + `tests/README.md` 用例行；真装类断言（`tools/list` 真实集合、`pi --help` 残留、遥测生效性、6 并发锁）走 `t4_skip` 门。
10. **README**：插件清单段补 codegraph 前置（CLI + 索引 + 遥测开关）与收益一句。
11. **发布**：v0.20.0（MINOR）+ npm 重发（用户执行，判据 = latest + integrity 逐字节一致）。

非范围（每条带理由）：

- **自动安装插件 / 自动建索引**：用户拍板「只检测 + 文档指引」；插件无 CLI 时静默失败，机制代跑会把失败藏起来。
- **把缺失变 fail**：用户拍板 warn only —— 下游三仓当前无索引，fail 立刻拉红派发链。
- **改插件上游 / fork / 自建 fallback extension**：上游 v0.1.0；本批只在文档与检测层兜住静默（替代方案另议）。
- **修复插件 fallback 死代码 / 让舰队注入其英文段**：不属 nao 资产；且舰队口径由角色卡承载更可控（arch 确认后可能记为「已知限制」）。
- **下游三仓 pin 升级**：另批处理。
- **CI 接入 / 新增 npm 依赖**：本仓零外部依赖原则不变。
- **为 9 个工具全量建文档**：工具集合版本相关，写死即腐化（BR7）。

## 四、用户场景

- **场景 A（RD 开发前）**：插件+CLI+索引齐备 ⇒ `codegraph_explore` 一次拿源码 + 影响面；缺任一 ⇒ 走 CLI（若可用）或 grep + 行段，`check -v` 已提示缺什么、怎么补。
- **场景 B（PM 验收读码）**：验收读变更文件用 `codegraph_node`（若该版本暴露）或 CLI 行段读取；不 `cat` 全文。
- **场景 C（新人接项目）**：`check -v` 看到「未声明 / CLI 缺失 / 无索引」三行提示 + 真实命令，按需补；不补也能干活。
- **场景 D（本仓维护）**：`M20261028-codegraph` 建完索引后 `check -v` 报「齐备」；会话退出与 `pi --help` 后 `git status` 仍干净。

## 五、业务规则

- **BR1 warn 门禁（含 rc 豁免 · arch A1）**：codegraph 相关提示**永不进 rc 通道** —— 现存 `Pending Changes ⇒ rc=1`（`nao-fleet.sh:1207`）**降为 warn**（删该 `rc=1`），`--strict` 亦不升级；函数头注释写明「codegraph 永不计入 rc」。**显式豁免登记**：本批构成一次「既有断言放松」（索引 pending 由红变可观测 warn），理由 = 六会话并发下 pending 是稳态，长期红会侵蚀真失败信号；下游若有脚本依赖此红 ✅ 显式读出并在台账点名（T4 待实测）。
- **BR2 四态判定（arch A2 · 文本作契约前缀）**：严格短路 ① 声明 → ② CLI → ③ 索引 → ④ `status` 文本；6 行契约见 §三-1；组合落位：未声明压倒一切（1）· 已声明+无 CLI+有索引 → 2 · 齐备+有改动 → 5。用例断言**固定前缀 + 命令子串**，不断言整行。
- **BR3 三段阶梯（单一口径）**：原生入口 → CLI → `grep -rn` + `sed` 行段；任一步降级不需审批，**「禁 cat 全文」永久有效**。
- **BR4 机制零代办 + 命令以实测为准**：不执行 `pi install` / `codegraph init` / `codegraph sync`；只提示**真实存在**的命令（`codegraph init`，无 `-i`）；**上游 README 与本机 CLI 冲突时以实测为准**，机制不抄上游 README 命令（arch §五-7）。
- **BR5 单源（arch A2 修正）**：包名在 `nao-fleet.sh` 常量 `CODEGRAPH_PKG` 与 `bin/nao-skill.js` `PI_PLUGINS` 各一处，由用例**等值断言**兵；**禁止运行时跨语言抽取**（sed 取空 ⇒ 静默假「未声明」，且 shim-only 安装可能无 `bin/`）；状态文本单实现 `codegraph_state` + `CG_MSG_*` 常量。
- **BR6 副产物纪律（arch A4/A7）**：nao 侧**不得**写入/修改 `.pi/APPEND_SYSTEM.md`（含 cleanup 代删 —— 无法区分用户自建，且与 reload 有竞态）；本仓 `.gitignore` 加**单文件** → 提交零命中；`pi --help -e` 残留登记为**已知限制**（ADR 限制节 + 技能一行 + 用户手工 `rm -f`），`check` **不加**该文件任何断言。
- **BR7 工具名纪律**：唯一硬编码 = `codegraph_explore`（上游默认暴露入口）；其余工具名不得写死，只能写「若该版本的 MCP 暴露」。
- **BR8 版本纪律**：改角色卡必 bump `version` + `updated`；合并后广播 `card <role> v<N+1>`（下游唤醒时补发）。
- **BR9 不静默**：插件失败是静默的（上游行为）；机制文案不得把「装了」写成「生效了」——「已声明（未验证生效）」是既定措辞。
- **BR10 遥测/离线**：CLI 遥测默认可能开启；nao 机制本批是否注入 `CODEGRAPH_TELEMETRY=0` 由 arch 裁定；机制自身仍零网络。

## 六、NFRs

- **性能**：`check` 增量 ≤ 0.2s（两份 json，~5ms 实测原理）；禁止用 `pi list`（0.92s）。
- **幂等**：新用例连跑 2 次一致、无残留；`M` 任务重跑 `codegraph init` 无破坏性。
- **资源门（原 A6 口径已证有缺陷 · 待 arch B1 复议）**：原命令 `ps -o rss= -p $(pgrep -f 'codegraph serve')` **漏采** daemon/worker/watchdog（cmdline 为 `codegraph.js serve …`）且 RSS 求和重复计共享页 ⇒ 实测三个数并存（launcher-only 303.1MB · 全集 RSS 1439.0MB · 全集 PSS 675.7MB）。重定义方向 = **进程树全集 + PSS**；阈值沿用 ≤600 / 600–1200（README 一行）/ >1200 回退。另：**孤儿 daemon 泄漏**（非会话 `pi` 调用 → ppid=systemd --user 常驻 ~150MB）入风险登记，处置（文档一行 vs 机制兜底）待 B2。
- **无网络**：机制零网络；插件零网络；舰队会话由 `spawn_one` 注入 `CODEGRAPH_TELEMETRY=0`（A3），用户手工终端由文档一行提示。
- **兼容**：未装插件时行为与今天完全一致；不改 `roles.yaml`、不新增角色。
- **可维护**：四态文本集中定义（用例与 `check` 共用），新增态只改一处。

## 七、验收标准

- **AC1（主路径 · 四态 + pending）**：Given 五组夹具（无插件条目 / 有插件但 PATH 无 CLI / 有插件+CLI stub+无 `.codegraph` / 齐备 / 齐备 + pending），When 跑 `check -v`（默认 `check` 只打单行摘要，不作断言层），Then 五组各自命中对应**契约前缀**且 `check` rc 恒 0（第五组 = A1 降级后的正式回归位）。
- **AC2（门禁强度）**：Given 未声明插件，When 跑 `check` / `check --strict` / `ensure <角色>`，Then 皆 rc=0 且会话正常拉起，提示含可复制命令；Given 索引 pending，When 跑 `check --strict`，Then 亦 rc=0（不升级）。
- **AC3（技能口径可测性 · arch A5 降级）**：Given 改写后的技能，When 读 + 跑静态断言，Then ① 含 `codegraph_explore` 且文档清单与用例断言**同源**（声明式清单）② 其余 8 个工具名**零硬编码**（只允许「若该版本 MCP 暴露」措辞）③ CLI 段保留为回退且命令真实（`codegraph init`，不带 `-i`）④ `grep` + 行段兜底 ⑤ 两句必备：「有插件无索引/无 CLI ⇒ 不生效」、「插件不供 system prompt 指引（截至 pi 1.4.0 / pi-codegraph 0.1.0）」⑥ 「禁 cat 全文」在位。**不断言**工具集合为 9 个。
- **AC4（口径统一 · 完整范围）**：Given 6 卡 + 3 清单 + `skills/pm-operations.md` + `templates/AGENTS.md.example`，When `grep -rn codegraph`，Then 每处为三段式或单句指针、无纯 CLI 指令、卡内 `codegraph_(search|callers|callees|impact|node|context|files|status)` **零命中**（`explore` 除外）、「插件不供指引」只出现在技能一处；6 卡 `version` 各 +1 且 `updated` 已改；`check` 卡片校验仍绿。
- **AC5（本仓自用 · 维护型闭环 + 资源门）**：Given `M20261028-codegraph`（已完成：CLI 1.6.2 · 插件 0.1.0 · 索引 4 files / 118 nodes / 500K · init 1.086s · `git status` 干净），When 验收，Then ① 文案以实测原件为契约（T1 三态原文）② **A6 门按 arch B1 重定义后的口径判定**（原口径已证漏采 daemon/worker/watchdog 且 RSS 求和重复计共享页）③ `check -v` 落「齐备」态 ④ daemon 与 `.pi/APPEND_SYSTEM.md` 的处置结论已入 README/技能（B2/B4）⑤ 台账 F1–F6 逐条三出口（F6 必须在本批合并前关闭）。
- **AC6（AGENTS.md 订正）**：Given `AGENTS.md`，When 读项目属性/命令段，Then 「本仓无 CodeGraph 索引」已替换为「已有索引 + 原生入口优先」+ 指针，不复制技能正文。
- **AC7（回归护栏 + 负控）**：Given `tests/t4/cases/18`，When 跑 `npm test`，Then 全绿且新断言 ≥ 8；两条文本变异（摘插件条目 / 摘 `.codegraph`）各自使**对应断言失败**（不是 `check` 失败），还原后 md5 一致。
- **AC8（副产物纪律 · arch A4/A7）**：Given 已建索引仓内一次真实 pi 会话退出，Then `.pi/APPEND_SYSTEM.md` 不存在；Given `pi --help -e` 类非会话调用，Then 该文件被 `.gitignore` 覆盖、**任何提交零命中**（不断言文件必不存在）；Given cleanup/close，Then 机制未删除/未写入该文件（行为断言 + 代码零命中）。
- **AC9（门禁全绿 · 放松已登记）**：Given 变更集，When 跑 `check` + `npm test` + `npm run test:t4:full:dual`，Then 均 rc=0；**唯一允许的既有断言放松 = `Pending ⇒ rc=1` 改为 warn**，已在 BR1 与台账显式登记（下游影响点名）；无其它断言放松、无新依赖、`files` 计数变化有解释。
- **AC10（发布闭环）**：Given main 合并后，When 发 v0.20.0，Then tag + Release（标题裸 `v0.20.0`）+ `docs/releases/v0.20.0.md` + npm 重发（`latest` = 0.20.0 且 `dist.integrity` 与本地 tarball 逐字节一致）+ 下游升级入口可读。

## 八、上线闭环

- **版本**：v0.20.0（MINOR）· npm 重发（用户执行）。
- **发布前置**：`check` rc=0 · `npm test` rc=0 · `npm run test:t4:full:dual` rc=0。
- **回滚**：`git revert` 单提交；本仓索引属本地环境（删 `.codegraph/` 即回旧态）；资源门未过时**回退优先于延期**（删索引即可，幂等无数据损失）。
- **监控信号**：后续 3 批若出现「插件齐备但角色仍 grep」，说明三段阶梯措辞不足 → 升为卡片硬性项。
- **风险登记**：6 会话 sidecar 内存（口径已修正，见 §六）· **孤儿 daemon 泄漏**（非会话 `pi` 调用后常驻 150MB，仅交互式 `codegraph daemons` 可停）· 同索引并发 sync/watch（锁测试已过）· `.pi/APPEND_SYSTEM.md` 残留（`pi install`/`pi list` 也触发）· 上游 v0.1.0 工具集合漂移 · CLI 遥测（已关且 strace 证实）· 插件英文段在舰队内不生效（口径由 nao 承载）。

## 九、变更治理与优先级

- **战略筛子**：命中「角色执行效率 + token 成本」——6 角色每天定位代码，一次原生调用替代多轮 grep + cat。
- **MoSCoW**：Must = AC1–AC4、AC6、AC9；Should = AC5、AC7、AC8；Won't = 自动安装、fail 门禁、9 工具全量文档、下游 pin。
- **RICE**：Reach = 20 · Impact = 2 · Confidence = 0.8 · Effort = 1.5 人日 ⇒ **RICE ≈ 21**。
- **Kano**：期望型（开发体验基础设施）。
- **拍板记录**：2026-10-28 用户 ask-me 6 项（见头部）；同日 QA 接缝回执后本 PRD 订正 v1→v2（工具数、注入前提、计数、`init -i`、rc 冲突、AC 可测性）。
- **遗留预判**：上游 v0.1.0 漂移（观察，无到期）· 下游三仓 pin（另批）· 6 会话 sidecar 资源（arch 若判超标 ⇒ 转「按需启用」策略）。

## 十、接缝回执结论（QA `done(full)`，2026-10-28）

- **S1 工具**：进列表 ✓ · 原始名无 `mcp__` ✓ · 受 `--tools` 剔除 ✓ · trust 不影响 ✓ · **默认只暴露 `codegraph_explore`**（余 8 需 `CODEGRAPH_MCP_TOOLS`）。
- **S2 检测源**：两份 `settings.json` 的 `packages` 最省最可靠（~5ms）；`pi list` 0.92s 且项目级不显示 ⇒ 不用；「装过但禁用」任何来源都误报 ⇒ 文案写「已声明（未验证生效）」。
- **S3 注入**：`--append-system-prompt` 抑制 `.pi/APPEND_SYSTEM.md`；插件 fallback 死代码 ⇒ 舰队零注入、无重复/顺序问题；`pi --help` 类调用**永久残留**文件。
- **S4 规模/资源**：init 秒级、产物 MB 内；`serve --mcp` 100–250MB/实例、6 会话 0.6–1.5GB（估算，需实测）；6 并发 sync 未验证。
- **S5 网络**：插件零网络；CLI 有匿名遥测（可关）；`PI_OFFLINE` 对两者无效。
- **S6 可测性**：四态**可纯静态断言**（夹具 HOME + PATH stub + 夹具 `.codegraph` + 必跑 `check -v`）；真装类断言走 `t4_skip` 门。
- **需 arch 裁定（5 项 + 2 项补充）**：① `Pending ⇒ rc=1` 与 BR1/AC9 二选一 ② 3 态 → 4 态 ③ 是否 `ensure` 注入 `CODEGRAPH_TELEMETRY=0` ④ `.pi/APPEND_SYSTEM.md` 是否 ignore ⑤ 卡片是否只写 `codegraph_explore` + 是否明写「插件不提供 system prompt 指引」⑥ 6 会话 sidecar 内存是否需改策略 ⑦ `pi --help` 残留是否需机制侧兜底。

## 十一、arch 评审回执（`done(full)`，2026-10-28 · 有条件可行）

- **裁决**：A1 **降为 warn**（唯一选项，不许「保留+豁免」；`--strict` 不升级）· A2 **采纳四态 + 文本作契约前缀**（含 BR5 改为 fleet 常量 + 用例等值断言、顺修 `PI_AGENT_DIR` 硬编码）· A3 **注入 `CODEGRAPH_TELEMETRY=0`**（位置 = `spawn_one` inner 命令；不加 `DO_NOT_TRACK`）· A4 **ignore 单文件**（不 ignore 整个 `.pi/`）· A5 **只写 `codegraph_explore`**（「不供指引」只写技能一处 + 版本戳）· A6 **有条件可接受**（RSS 门 ≤600MB / 600–1.2GB 带 README 一行 / >1.2GB 或锁错 ⇒ 回退删索引；结构事实：无 per-session 开关，杠杆只有「哪仓建索引」）· A7 **已知限制 + ignore + 文档**，不代跑 cleanup。
- **条件（必须同步，已入 PRD）**：① rc 放松在 PRD 显式豁免（已入 BR1/AC9）② 状态文本匹配串须**先实测校准**（见下 T1）③ A6 资源门先跑 ④ BR5 单源兑现 ⑤ AC3/AC8 改写（已完成）。
- **待实测（阻塞文案冻结 · M 前置）**：T1 `codegraph status` 真实文案 · T2 `init` 是否收 `-i` · T3 6 并发 RSS/锁（= A6 门）· T4 下游是否隐性依赖 `Pending ⇒ rc=1` · T5 `CODEGRAPH_TELEMETRY=0` 是否真被 CLI 读取。
- **风险 Top 3**：① 6 并发 sidecar/watcher 对单 SQLite（未验证，可能推翻「本仓起索引」；回退 = 删索引）② rc 放松的隐性依赖（AC9 最易在此破）③ 四态「单源」被实现成跨语言抽取（静默假阴性）。

## 十二、M20261028-codegraph 实测回执（2026-10-28 · T1–T5 全结）

- **T1 status 文案（已证伪「恒不命中」担心）**：① `✓ Index is up to date`（rc=0）② 段标题 `Pending Changes:` + `  Modified:  1 files` + `ℹ Run "codegraph sync" to update the index`（rc=0）③ 空目录 `⚠ Not initialized` + `ℹ Run "codegraph init" to initialize`（rc=0）。现实现 `check_codegraph:287-295` 与 `cmd_check:1200-1215` 的三条匹配串**全中** ⇒ 本批只需删 `:1207` 的 `rc=1`，**文案不改**。三态 rc 恒 0 ⇒ rc 不可作状态信号（支持 A1）。
- **T2 命令冻结**：`codegraph init --help` 原文 `-i, --index  Deprecated: indexing now runs by default` ⇒ `-i` **被接受但已废弃**，机制文案一律 `codegraph init`。其他已冻结：`sync` / `status [--json]` / `serve --mcp [-p] [--no-watch]` / `telemetry [status|on|off]`；关遥测真实命令 `codegraph telemetry off`。
- **T3 资源（口径缺陷 ⇒ 待 arch B1 复议）**：A6 原命令只命中 launcher ⇒ **303.1MB**；全集 20 进程 RSS **1439.0MB** / PSS **675.7MB**（含 1 仓共享 daemon 288.1MB）；单会话 5 进程 RSS 468.1 / PSS 319.7 ⇒ 边际 **+194.2MB RSS**。并发锁：6 次 `status` rc 全 0，`database is locked`/`sqlite_busy` **0 命中**。
- **T4 下游**：本仓 + 三仓 scripts/CI **0 命中**；nao-todo 曾做过同一放松（CHANGELOG `TASK-16`：索引警告不计退出码）⇒ 支持 A1。
- **T5 遥测**：`telemetry off` 落 `~/.codegraph/telemetry.json`；`strace` 对照——无 env 时 `connect(:443)` 1 次，`CODEGRAPH_TELEMETRY=0` 时 **0 次** ⇒ A3 注入有效且不注入确有出网副作用。
- **新发现（F6 同类风险 · 待 arch B2/B4）**：在本仓跑**非会话** `pi list` 会留下**孤儿 daemon** — 实测 pid 118097 **ppid=884（systemd --user）**、etimes 88s 仍活、**RSS 149012KB / PSS 127269KB**；`codegraph daemons` 只能交互式停止（无 `--stop`）。同理 `.pi/APPEND_SYSTEM.md`（2109 B）已被 `pi install` / `pi list` 触发 ⇒ **A7 触发面比「`pi --help -e`」宽**（任何加载扩展的非会话调用）。
- **遗留（台账 `docs/reports/M20261028-codegraph-followups.md`）**：F1 关闭 · F2 接受至 2026-11-28（nao-todo-server 有 `.codegraph/.gitignore` ⇒ 目录在无索引，205.7MB/会话）· F3 随 F6 · F4 关闭 · F5 接受至 2026-12-28（插件 0.1.0 × CLI 1.6.2 版本耦合）· **F6 转办（本批合并前必须裁定）**。

- 修订：2026-10-28 v1 首稿（用户 6 项拍板后）· 同日 v2（QA 接缝回执订正）· 同日 v3（arch 裁决 A1–A7 落地）· 同日 v4（M 任务实测回执：T1–T5 全结 · F6 门口径缺陷 + daemon 泄漏登记 §十二 · AC5 待 arch B1 复议后定稿）
