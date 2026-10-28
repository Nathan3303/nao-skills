# M20261028-codegraph 环境动作 + 前置实测台账

- 编号：`M20261028-codegraph` · 类型：维护型（环境动作 + 前置实测）· 批次：T532 · 分支：`feat/53-codegraph-plugin`
- 触发：PRD `docs/prds/2026-10-28-codegraph-plugin.md`（v3）§三-6 前置；arch 裁决 `docs/reports/2026-10-28-T532-arch-review.md` §三（T1–T5）+ A6 资源门；QA 接缝 `docs/reports/2026-10-28-T532-qa-recon.md`
- 授权：用户 2026-10-28 批准全部环境动作（全局 CLI + 用户级插件 + 本仓索引），均可回退
- 环境快照：`codegraph 1.6.2`（npm 全局）· `pi 1.4.0` · `@sean_pedersen/pi-codegraph 0.1.0` · node `24.22.1`
- 边界：**不改机制文件**（检测/卡片/技能属后续实现）；本单只做环境 + 实测 + 台账

## 一、产物（实际落盘/安装物）

- **CLI**：`npm install -g @colbymchenry/codegraph` → `added 2 packages in 47s`，`codegraph --version` = `1.6.2`；前缀 `$(npm config get prefix)` = mise node `24.22.1` ⇒ **全程无 sudo**。包结构 = 主包 + 平台包 `@colbymchenry/codegraph-linux-x64`（bundle 自带运行时，平台包 6 个覆盖 linux/darwin/win32 × x64/arm64）。
- **插件**：`pi install npm:@sean_pedersen/pi-codegraph` → rc=0（6.3s），`pi list` 5 包（`pi-intercom@0.18.1` · `pi-ask-me@0.1.1` · `pi-subagents@0.83.0` · `pi-web-access@0.45.0` · `@sean_pedersen/pi-codegraph@0.1.0`），写入 `~/.pi/agent/settings.json` 的 `packages`。
- **遥测**：`codegraph telemetry off` → 落点 `~/.codegraph/telemetry.json`（150 B，`{"enabled":false,"machine_id":null,"consent_source":"cli",…}`）；`~/.codegraph/` 权限 `700`。**该文件在仓库外，不入库**。
- **索引**：本仓 `codegraph init`（**命令不带 `-i`**）→ 耗时 **real 1.086 s**（工具自报 `118 nodes, 297 edges in 331ms`）· 索引 **4 files** · `.codegraph/` 体积 **504 K**（`codegraph.db` 500 K）。`git status --short` **空**（`.codegraph/` 已被既有 ignore 覆盖，无需改 `.gitignore`）。

## 二、验证（逐条给原文/数字）

### T1 `codegraph status` 三态原文（**最高优先，结论：现存匹配串全部命中，无缺陷**）

冻结版本戳：`codegraph 1.6.2`。逐字（`cat -A` 校验，行尾 `$`，无隐藏字符）：

1. **up to date**：`✓ Index is up to date`（`✓`=U+2713 后接单空格）；rc=**0**
2. **有改动（未 sync）**：段标题 `Pending Changes:`（大写 P/C、复数、**带冒号**）+ 明细行 `  Modified:  1 files` + 提示 `ℹ Run "codegraph sync" to update the index`；rc=**0**
3. **无索引（`/tmp` 空目录）**：`` ℹ Project: <path> `` / `⚠ Not initialized` / `ℹ Run "codegraph init" to initialize`；rc=**0**

**对现有实现的判定**：
- `check_codegraph`（`nao-fleet.sh:287-295`）匹配 `Index is up to date` / `Pending Changes` / `Not initialized` ⇒ **三条全中**，无需改串。
- `cmd_check`（`:1200-1215`）匹配 `up to date` / `Pending Changes` ⇒ 也全中；**唯一要改的是该分支里的 `rc=1`**（arch A1：降 warn），不是文案。
- **arch 的怀疑（`Pending sync:` 上游 README 导致恒不命中）经实测否定**：本机 1.6.2 打的是 `Pending Changes:`。上游 README 仍是**外部文档与实现不一致**，故 BR4「以实测为准」成立（见 F1）。
- **`status` 三态 rc 恒 0** ⇒ rc 不能作状态信号，检测必须读文本（或 `--json`）。
- **建议给 arch 的增补**（本单只报不裁决）：`codegraph status --json` 存在且稳定可解析 —— `{"pendingChanges":{"added":0,"modified":1,"removed":0},…,"index":{…,"state":"complete","reindexRecommended":false}}`。文本契约对大小写/文案微调敏感，JSON 契约对该风险免疫；若采纳，`codegraph_state` 可优先 `--json` + 文本兜底（代价：多一次 fork，需与 NFR「≤0.2s」权衡）。

### T2 `init` 的 flag 结论

`codegraph init --help`（1.6.2）原文：`-i, --index  Deprecated: indexing now runs by default; flag accepted for backward compatibility`。
⇒ **`-i` 被接受但已废弃**；机制文案**一律写 `codegraph init`**（不带 `-i`，与 arch T2 一致）。可用 flag：`-f/--force`（家目录/根目录守卫）、`-v/--verbose`、`-y/--yes`（非交互）。其它已冻结命令：`codegraph sync` · `codegraph status [--json]` · `codegraph serve --mcp [-p <path>] [--no-watch]` · `codegraph telemetry [status|on|off]`。

### T5 遥测 env 生效性（**已验证**，三重证据）

1. **优先级由 CLI 自己报**：`CODEGRAPH_TELEMETRY=0 codegraph telemetry` → `Telemetry: disabled (CODEGRAPH_TELEMETRY environment variable)`；config=`enabled` 时不改 `CODEGRAPH_TELEMETRY=1` 反向测试 → `enabled (CODEGRAPH_TELEMETRY environment variable)`；`DO_NOT_TRACK=1` → `disabled (DO_NOT_TRACK environment variable)`。⇒ env **覆盖**已存配置。
2. **上游类型契约**（`dist/telemetry/index.d.ts`）：`DO_NOT_TRACK=1 > CODEGRAPH_TELEMETRY=0|1 > stored config > default on`；`decidedBy: 'DO_NOT_TRACK' | 'CODEGRAPH_TELEMETRY' | 'config' | 'default'`；端点常量 `TELEMETRY_ENDPOINT = https://telemetry.getcodegraph.com/v1/events`；不变式「off is off：disabled 时不记录、不发送、**不打开 socket**」。
3. **strace 对照**（`connect` 系统调用，config 保持 enabled，`codegraph init -y` 新临时项目）：
   - 无 env：`connect(…) sin_port=htons(443) … = -1 EINPROGRESS` ×**1**（另有 2 次 `htons(0)` 本地 socket）。
   - `CODEGRAPH_TELEMETRY=0`：`:443` 连接 **0** 次（strace 行数 26 → 18）。
   ⇒ 舰队 `spawn_one` 注入 `export CODEGRAPH_TELEMETRY=0` **有效**（arch A3 可落地）；同时证明**不开 telemetry 就有出网副作用**，注入是必要的而非保险。

### T3 资源门（arch A6）—— **判定：接受（≤600MB 档）**

测法：6 个真实 `codegraph serve --mcp` 进程（不是 6 个空进程），每个完成 **MCP `initialize` + `notifications/initialized` + `tools/list` + `tools/call codegraph_explore`**，随后测 RSS；期间改一个已索引文件并起 6 个并发 `codegraph status`。

- **6 进程全部握手成功**，`tools/list` = **`["codegraph_explore"]`**（唯一工具，与 PRD S1 一致），每次 `explore` 返回 12061 B。
- **RSS 求和 = 310252 KB = 303.1 MB**（单进程 50.5–50.6 MB，pid 各不相同、`alive=True`）；并发测试后再测仍 **303.1 MB**（无爬升）。
- **锁测试**：6 次并发 `codegraph status` **rc 全 0**，`database is locked` / `sqlite_busy` 命中 **0 次**；其中 1 次读到 `Pending Changes`、其余 `up to date`（watcher 已自动同步），3 秒后复查 `✓ Index is up to date` ⇒ 单库 6 读 + 6 watcher 并发**未观察到锁冲突**。
- **门判定**：303.1 MB ≤ 600 MB ⇒ **接受，不需要 README 加「资源」一行**（该项仅为 600MB–1.2GB 档要求；实际值比 QA 估算 100–250MB/**实例** 低一个档，6 会话约 0.30 GB）。
- 测完进程已杀净：`pgrep -af 'codegraph serve'` 无残留，`alive_after_kill=0`。

### T4 下游隐性依赖 —— **结论：本仓 + 下游三仓均无命中**

- **下游三仓**（`~/Projects/nao-todo` · `~/Projects/nao-todo-server` · `~/Projects/nue-ui`）：
  - `nao-fleet.sh check` 的 rc 消费面：**0** —— 三仓 `package.json` scripts、`.github/workflows/*`（`nao-todo/ci.yml`+`release.yaml` · `nao-todo-server/ci.yml` · `nue-ui/test-and-deploy.yml`）对 `nao-fleet` / `codegraph` / `.agents` **均 0 命中**；`.agents/scripts/nao-fleet.sh` 本身是 shim（只转发，不解析输出）。
  - 解析 CodeGraph 段的脚本：**0** —— `Pending Changes` / `Index is up to date` / `Not initialized` 三串在三仓**代码与 CI 中零命中**（仅 `nao-todo/CHANGELOG.md:404` 有历史文字记录）。
- **反向证据（支持 arch A1）**：`nao-todo` 历史已自行做过同一放松 —— `CHANGELOG.md:404`「**CodeGraph 索引警告不再计入 `vp check` 退出码**（TASK-16，`02626f23`）：`Pending Changes` 警告原被记为 `rc=1`……会造成误停」；PRD `2026-09-21-calendar-day-view.md:199` 同记「T57 治理：CodeGraph 索引警告不再计入 `check` 退出码」。⇒ 本批 rc=1 → warn **与下游既有口径同向**，不构成隐性依赖破坏。
- **本仓**：`tests/` 无 `Pending Changes` / `codegraph rc` 断言（`check` 段 rc=1 无测试覆盖）。

### 副产物现场实测（A4/A7 的额外证据，非本单必做项）

- 索引建成后，**非会话型 `pi` 调用同样留下副产物**：`pi install npm:@sean_pedersen/pi-codegraph` 与本仓 `pi list` 执行后，仓库根出现 `.pi/APPEND_SYSTEM.md`（**2109 B**，首行 `## CodeGraph`），`git status --short` 变脏（`?? .pi/`）。⇒ QA S3 的成因比「仅 `pi --help -e`」更宽：**任何加载扩展的非会话 `pi` 调用**都会触发工厂写入、且不触发 `session_shutdown` 清理。这加强（而非推翻）A4「单文件 ignore」的必要性；按 A7/BR6，本单**未写入/未删除**该文件（机制侧不代跑 cleanup），留给用户手工 `rm -f .pi/APPEND_SYSTEM.md`，由 T532 的 `.gitignore` 兜住污染。
- 时序澄清：`codegraph init` 完成后的 `git status --short` 当时**为空**（索引/ignore 正确）；脏化发生在随后的 `pi` CLI 调用之后，与本单的 `.codegraph/` 及其 ignore 无关。

### 全范围门禁（本仓口径）

- `bash .agents/scripts/nao-fleet.sh check` → **rc=0**，`check: OK · roles=6 · files=50 · layout=main-row2`；`check -v` CodeGraph 段实际输出 `✓ 当前目录索引 up to date`（真实 CLI 驱动，非 stub）。
- `npm test` → **rc=0**，`RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）`。

## 三、遗留项与出口

> 字段固定顺序：编号 / 来源 / 严重度 / 出口 / 到期（@.agents/skills/task-completion.md §三）。

- `F1`｜来源 = 上游 README 与本机 CLI 文案/命令不一致（README 写 `### Pending sync:` 与 `init -i`；实测为 `Pending Changes:` 与 `-i` **已废弃**）｜严重度 = 低（会误导文案冻结）｜出口 = **关闭**（已实测冻结并记入本台账 §二 T1/T2；BR4「以实测为准」成立，机制不抄 README）｜到期 = —（已关闭 2026-10-28）。
- `F2`｜来源 = `~/Projects/nao-todo-server` **入库** `.codegraph/.gitignore`（`git ls-files` 可见）⇒ 目录存在但无索引（`codegraph status` = `⚠ Not initialized`）；插件激活条件是 **cwd 存在 `.codegraph/`**（`extensions/codegraph.ts:132` `existsSync`），故该仓每个舰队会话都会起一个 ~50 MB sidecar 且无可用索引｜严重度 = 低（内存 50 MB/会话 + 静默不可用）｜出口 = **接受**（本批范围外、不改下游；T532 的「已就绪但当前仓无索引」检测文案正好覆盖该态，届时可见）｜到期 = **2026-11-28**（重评触发：T532 检测落地 / 该仓建索引 / 插件改激活条件）。
- `F3`｜来源 = 6 会话 sidecar 本机常态内存 303.1 MB（本机 15 GB / 可用 8 GB）｜严重度 = 低（门内）｜出口 = **接受**（实测入台账；扩容 = 给更多仓建索引时按 50.5 MB/会话线性估算）｜到期 = **2027-01-28**（重评触发：新增仓库建索引 / 上游 serve 内存变化）。
- `F4`｜来源 = `pi install` 报 `removed 206 packages`（用户级 npm 根剪枝）｜严重度 = —｜出口 = **关闭**（复核 5 个包版本完好：`pi-intercom@0.18.1`/`pi-ask-me@0.1.1`/`pi-subagents@0.83.0`/`pi-web-access@0.45.0`/`@sean_pedersen/pi-codegraph@0.1.0`；`pi --version` = 1.4.0 正常）｜到期 = —（已关闭 2026-10-28）。
- `F5`｜来源 = 插件 `0.1.0` 与 CLI `1.6.2` 的版本耦合无声明（插件 `spawn("codegraph", ["serve","--mcp"])`，依赖 CLI 的 `serve --mcp`/`tools/list` 契约）｜严重度 = 低｜出口 = **接受**（watch 上游；本单已实测该组合可用）｜到期 = **2026-12-28**（重评触发：任一组件升级）。

## 四、回滚

- 插件：`pi uninstall npm:@sean_pedersen/pi-codegraph`（或从 `~/.pi/agent/settings.json` 的 `packages` 移除后 `pi install`/重载）。
- 索引：`rm -rf .codegraph`（纯本地可重建物，幂等；已 ignore，不影响 git）；或 `codegraph uninit`。
- CLI：`npm uninstall -g @colbymchenry/codegraph`。
- 遥测：`codegraph telemetry on`（若确需恢复；本项目口径为保持 off + 舰队注入 `CODEGRAPH_TELEMETRY=0`）。

## 五、交接（给 T532 实作）

1. **文案冻结可直接引用 §二 T1 的三行原文**（版本戳 `codegraph 1.6.2`）；机制内匹配串**无需改**，本批只需删 `cmd_check` 的 `rc=1` + 落 arch A2 的六态契约。
2. **`init` 命令写 `codegraph init`**（不带 `-i`）；`-i` 虽被接受但已废弃（F1）。
3. **遥测注入已验证有效**（T5 三重证据），`spawn_one` 的 `export CODEGRAPH_TELEMETRY=0` 按 A3 落。
4. **资源门已过（303.1 MB）** ⇒ AC5 的 A6 门可直接引用本台账数字，README 不需加「资源」一行。
5. **T4 无下游耦合** ⇒ BR1 的豁免条款不必点名下游代码影响，可只引用 nao-todo 两条历史同向记录（§二 T4）。
6. **`status --json` 是更稳的契约候选**（§二 T1 建议），若 arch 采纳需在 NFR 里补一次 fork 的耗时预算。
7. **副产物触发面比 QA 结论更宽**（§二「副产物现场实测」）：`pi install` / `pi list` 也会留 `.pi/APPEND_SYSTEM.md`；A4 的 ignore 单文件是必需项而非可选项，且 `check` 不该断言该文件存在性（A7 口径不变）。
