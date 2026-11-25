# ADR：编排器阶段 2 落点 + `nao-fleet.sh` 拆分边界

- 状态：已接受（待落地 · 需 PM 开工确认卡）
- 更新：2026-11-24
- Owner：arch-designer
- 指针：Issue [#182](https://github.com/Nathan3303/nao-skills/issues/182) · PRD `docs/prds/2026-11-24-orchestrator.md`（§五 接口 · §六 失败模式 · §七 AC5–AC9 · §十 已拍板）· 阶段 1 实现 `bin/nao-queue`（b6bb4cb）· 前置 ADR `2026-11-22-herdr-only.md`

## 背景

- 阶段 1 已有 `queue.jsonl` 单源 + 校验/渲染器，但调度仍靠 PM 会话手工 `ensure` + 派单；阶段 2 = 定时 tick 让「PM 离线 30 分钟内无阻塞任务推进到 `qa_pass`」成立。
- 同批 C 组 `nao-fleet.sh` 实测 **5431 行 / 174 函数**（最长 `cmd_status` 318 · `cmd_close` 303 · `cmd_check` 270），而 orch 唯一需要的跨进程接口（`status --json`）与 5 个静态闸都长在这一个文件上 ⇒ 两件事共享同一架构面，分两次做必然二次搬迁。
- 硬约束：AC1「`status`/`check` 文本输出逐字不变」；`scripts/nao-fleet.sh` 路径被 215 个文件 / 196 处用例引用（下游仓 shim 也转发到这里）＝既成公共接口；阶段 2 默认不启用。
- 决定 orch 形态的关键实测：`term_require` 要求 `HERDR_ENV=1` + 合法 `HERDR_SESSION` + `HERDR_SOCKET_PATH` 落在 `$XDG_CONFIG_HOME/herdr/sessions/<s>/` 下 + `herdr api schema` protocol=22 —— **systemd 单元里一个都不满足**。

## 决策

一件 ADR 覆盖两件事（耦合点 = `status --json` 契约 + 静态闸的文件集迁移）：D1/D2/D4/D5 为 orch 面，D3 为拆分面，D6/D7 两面共用。

- **D1 落点 = `bin/nao-orch`**（Node ≥18 零依赖，与 `bin/nao-queue` 同构）：`tick|board|dispatch|reap|doctor|install-systemd|uninstall-systemd`；队列解析/校验/状态机从 `nao-queue` 抽成共享模块 `bin/lib/queue.mjs`（纯函数，两处同引），**禁复制状态表**（复制 = 状态机双源）。
- **D1 瞬时态只有两样，全部在 `docs/queue/.orch/`**（该目录自带两行 `.gitignore` = `*` + `!.gitignore`：目录随库存在、内容全忽略；**只写 `*` 会把 `.gitignore` 自身也忽略** ⇒ clone 后目录不存在、`文件不存在` 与 `被忽略` 两种状态混淆。不动根 `.gitignore` 以免与 `chore/566-followups` 撞；`wal.jsonl`/`lock` 已被 `*` 覆盖）：`wal.jsonl` = 派单账（append-only，逐条 fsync：`<id>#attempt=<n>#at=<ISO>` + 目标会话 id/cwd + 写时 row sha），`lock` = 整 tick 独占锁（D4）。**不新增 `dispatch_at` 字段**（`updated` 会被手改重置 15m 计时），**不建 last-tick 文件**（上次 tick 从 journald 读，board 现算）。
- **D1 防双源（硬判据）与反选**：状态事实只在 `queue.jsonl`；WAL 只回答「这次派单的意图/时刻/目标」，**从它不得推断任何 row 的 `state`**；WAL 有 intent 而 row 仍 `queued` ⇒ 不重派、标 `blocked(dispatch_desync)` 交人。反选 shell：JSONL 校验与状态表已在 Node（阶段 1），bash 版 = 双实现双源 + 15m/90m 计时不可单测。
- **D2 与 fleet 的边界 = 子进程**（不同进程、不同语言）：唯一接口 `nao-fleet.sh status --json`（阶段 2 新增，`schema:1`）+ `ensure <role>[@<repo>] [--task <id>]` + `close <name>` + `session-start --session <名>`，一律 `execFile` + argv 数组 + 子命令白名单。理由：身份/放置键/槽位逻辑必须留 fleet 单点（三次裸名误投的成因），orch 只消费 JSON；进程边界可用 PATH 桩单测。**失败面**：① fleet 解析不到（PATH/包内路径）⇒ tick rc=1 **零队列写入**；② 前提不满足（fleet rc=3：pane/socket/protocol）⇒ 环境级失败，**不写 `blocked`**（`blocked` 是任务级判断），只 journald + 下 tick 重试；③ herdr 挂起 ⇒ 单次调用硬超时 30s / 整 tick 120s，杀子进程 + 零写入。`boot`/`doctor` 用同一判据自建终端上下文（`HERDR_ENV=1`、显式 `--session`、socket 由 `session-start` 后实测发现，**禁猜会话名**）。
- **D3 切法 = 层 × 后端**（不按动词：放置/回收共用快照与私有解析，按动词切只会把单体耦合换成文件耦合）。目标模块（括号 = 现函数体实测行数）：入口 `nao-fleet.sh` **永久保留**（197 行前导，含 `usage()` 用 awk 读 `$0` 的头部块 —— **不可搬走**）+ CLI 解析 ≈330 · `fleet/lib/core.sh` 250（路径锚/`die`/版本/codegraph 文案）· `term.sh` 140（门面 18 函数 + `NAO_TERMINAL` 唯一赋值点）· `term-herdr.sh` 1250（44 函数）· `term-app.sh` 680（31）· `manifest.sh` 660（19：roles.yaml/fleet.yaml/命名契约/卡）· `session.sh` 660（22：名册/cwd/身份/派生名）· `check.sh` 740（14 + `cmd_check`：审计面）· `status.sh` 320 · `close.sh` 440 · `cleanup.sh` 130（`cmd_cleanup`+`session-start`）· `ensure.sh` 600。
- **D3 依赖单向无环**：`core` ← `term` ← {`term-herdr`,`term-app`}；`core` ← `manifest` ← `session`；{`term`,`manifest`,`session`} ← `check`；{`term`,`session`,`manifest`} ← {`status`,`close`,`cleanup`,`ensure`}；入口最后按拓扑序 source。**命令层不得互调**（`cmd_*` 只被入口调用；要共用就上移一层）。
- **D3 兼容**：`scripts/nao-fleet.sh` 路径**无 sunset**（下游仓 shim 由 `nao-skill init/migrate` 生成并转发到此，196 处用例引用）；`usage()` 头块、子命令、退出码 0/1/2/3/4、文本输出逐字不变（AC1）；`bin/shim` 零改动。
- **D3 174 函数锚怎么迁**：落 `fleet/functions.txt`（`<模块>\t<名>`，可机械重排），用例断言 ①各模块顶层函数并集 = 清单（无漏登记/无重名/无孤儿）②总数恒 **174**（纯搬迁 ⇒ 数量守恒，新增函数须同行加一行）③ 所属模块与清单一致。同时把按「单文件 + `# >>> term-facade-herdr` 行区间」写的 5 个静态闸（`t4_scan_term_bare_calls` / `term_herdr_forbidden` / `app_bare_hc` / `tmux_residue` / `place_pane_rows`）改为**文件集扫描 + 每模块期望**；`NAO_TERMINAL=` 唯一赋值点 lint 由「单文件 `grep -c`=1」改为「跨模块总和=1」，`SELF_SH` 指 `term.sh`。**这批 lint 迁移是拆分的真实成本（≈6 个用例文件）**，必须与拆分同一 PR。
- **D4 形态 = 一次性 tick + systemd timer**（非常驻 loop）：崩溃退化为「本次 tick 失败」，本来就没有内存态，「daemon 半死」整类消失；补跑由 `Persistent=` 负责（仅对 `OnCalendar=` 生效 ⇒ 选日历式，见 D6），重叠触发由「同 unit 不并发 + flock 兜底」双保险。**flock 粒度 = 每仓一把、整 tick 持有**（`flock -n`，内核随进程退出释锁 ⇒ 无 stale 锁）：第二实例 rc=1 + 点名持锁 pid/起始时刻；不给每次派单加锁（tick 内单进程串行），也不做每任务锁（只增死锁面）——「每仓」即「全局」：一个 orch 绑一个仓（`queue.jsonl` 是仓内文件），跨仓各仓各自 timer。
- **D4 崩溃窗口 = WAL 三段式**：写 intent（fsync）→ 副作用（ensure+intercom）→ 提交 row。幂等键 `key = <id>#attempt=<n>#at=<ISO秒>`（不含 attempt 则 AC7 后的重派必撞，不含 at 则同 attempt 两次尝试不可分）。恢复 = 拿 intent 的 `session_id`+`cwd`（**禁裸名**）去 `status --json` 探：命中 ⇒ 补提交 `dispatched`；未命中 ⇒ 标 `blocked(dispatch_unknown)` + 通知 PM，**绝不自动重派**（PRD §六）。
- **D4 状态表补记（批次 B 实施）**：`queued → blocked` 是合法边（`bin/lib/queue.mjs` 单点）。理由：恢复期「WAL 有 intent 而 row 仍 queued、探不到目标会话」必须能落成 `blocked(dispatch_unknown)` —— 否则只剩「自动重派」（违反「绝不双派」）或「留一个无人知的 queued」。既有边与其它 AC3 判据不变。
- **D4 写盘 = CAS**：写前记 `queue.jsonl` sha，落盘前重读比对，变了（人工改/另一进程）⇒ 本次 tick rc=1 零写入，不覆盖人的编辑。
- **D5 AC9 两层闸**：① 结构层 —— orch 的执行面 = `bin/lib/orch/fleet.mjs`，唯一出口 `fleetExec(sub, argv)`（`execFile` + 白名单 `status/ensure/close/session-start`）。**orch 执行面（`bin/nao-orch` + `bin/lib/orch/**`）内 `child_process` 仅 `fleet.mjs` 一处**，零 `shell:true`、零 `exec`、零模板拼命令 ⇒ 队列里的字符串**不可能**变成命令；`bin/lib/queue.mjs`（阶段 1 继承）另有一处 `execFileSync('git', …)` 只读用法（argv 数组、零 shell、只跑 `git ls-remote`，不在派单路径上），为免读者误读为「全局唯一」故在此显式点明；② 静态闸 —— `t4_scan_orch_forbidden`（进 `tests/t4/lib.sh`，与既有 5 个 `t4_scan_*` 同族，复用「注释行豁免 + 命令位前缀集」口径）扫 `bin/nao-orch` + `bin/lib/orch/**`：`gh pr merge` · `gh release create` · `git push …(main|master|--tags)` · `git tag` · `git merge` · `npm publish` · `execSync|spawn(…{shell:true})` 命中即红。
- **D5 双向用例落新例 `tests/t4/cases/47-orch-static-gate.sh`**（注册进 `run.sh` 的 `CASE_IDS`/`CASE_TITLES`）：正控 = 真件 0 命中 + 闸体自证（对注入件必命中，防「删掉判据 = 空转绿」）；负控 = 副本各注入一行 `gh pr merge 1 --squash` / `npm publish` / `cp.execSync('git push origin main')` ⇒ 三条都必须红。
- **D6 安装/卸载 = orch 自带** `install-systemd [--interval 2m] [--session <名>] [--linger]` / `uninstall-systemd`（fleet 不加子命令：拆分面已很大，且单元文件是 orch 的部署资产，模板 `.agents/systemd/nao-orch.{service,timer}.in` 随 `files` 分发）。**单元形态**：`Type=oneshot` service（`ExecStart=<node> <bin/nao-orch> tick`，`WorkingDirectory=<git toplevel>`，安装时解析，非 git 仓直接拒）+ `TimeoutStartSec=120`；timer `OnCalendar=*:0/<interval 分钟>` + `Persistent=true` + `RandomizedDelaySec=15s`，`WantedBy=timers.target`；user unit，跨注销靠显式 `--linger`（不默认改系统设置）。安装时把**当时的** `PATH`、node/herdr/pi/git 绝对路径写进 `Environment=`（user unit 默认 PATH 不含它们），并先跑 `doctor`（二进制可达 · protocol=22 · `session-start` 可起 · 队列可校验）：任一项失败 ⇒ 不 enable，exit 3。
- **D6 幂等判据**：渲染到 `~/.config/systemd/user/`（`XDG_CONFIG_HOME` 可覆盖）；内容 sha256 相同 ⇒ 不写盘、不 `daemon-reload`；验收 = 连装两次 `diff -r` 安装目录为空 + `is-enabled` 不变 + rc=0；用例用私有 `XDG_CONFIG_HOME` + PATH 桩 `systemctl`（既有夹具惯例）。最短 interval = 1 分钟（timer 粒度）。
- **D6 日志**：单行 `orch tick=<ISO> repo=<基名> scanned= dispatched= blocked= skipped= rc=`（`journalctl -u nao-orch -o cat | grep '^orch tick='` 可断言）；自定义 journal 字段需 `sd_journal_send` ⇒ 零依赖下不引入，程序读面用 `nao-orch board --json`。
- **D7 失败模式**：daemon 半死 → 不存在（oneshot；挂住的 tick 由 `TimeoutStartSec` 收尸、内核释锁、下 tick 重入）· 远端不可达 → tick 不触网（不跑 `git ls-remote`/不调 `gh`），只有 intercom 通知可能失败 ⇒ journald + `queue.jsonl` 留证（PRD §十.3 两者都做），状态照常推进 · `queue.jsonl` 被手改或非法 → tick 开头跑 `nao-queue validate --no-push-check`，任一错误 ⇒ rc=1 零写入（不尽力而为、不渲染）· tick 撞人工派单 → 仲裁者 = `state` 字段（人工先写 `dispatched` ⇒ orch 不派），同文件写冲突由 sha CAS 兜住（后写者退出，不覆盖）。
- **D7 回滚**：`git revert` **单个 PR**（不是 `git checkout --` 撒回文件）：删 `bin/nao-orch` + `uninstall-systemd` ⇒ 队列文件保留可人读、旧调用零影响（PRD §九）；拆分回滚 = revert 同一 PR（入口路径与行为不变）。

## 理由

1. 业务匹配：AC5–AC9 都是「并发/恢复/闸门」类，判据必须机械可判，故全部落在可被用例驱动的进程边界上。
2. 成熟度：一次性 tick + timer 与 flock 内核释锁都是十几年不变的原语；流水线状态机复用阶段 1 已合并实现，不新造。
3. 团队能力：Node 与 `nao-queue` 同构，rd-infra 维护面不增语言；拆分后单模块 ≤1250 行，`check`/`status` 可独立改。
4. 成本：不迁依赖、不改 AC1 文案面；代价 = 用例侧 5 个静态闸改文件集 + `status --json` 成为长期契约。

## 对照过的备选模式

1. **维持现状（人记得派单 + 5431 行单体，基线）** —— 适用：无人值守无需求；代价：成功判据不满足，单体让 lint 迁移成本继续涨；不采纳。
2. **两份 ADR（orch / 拆分各一份）** —— 适用：两件事互不共享接口；代价：`status --json` 契约与静态闸文件集迁移要在两侧重复写；**不采纳**（共享面是同一个，一份 ADR 两个决策块更省读者成本）。
3. **常驻 daemon（`Restart=always`）** —— 适用：需要秒级反应或长连接；代价：引入「半死/僵尸/重启抖动」与新的状态持久化需求；不采纳：tick 全量重算已够，timer 天然带补跑。
4. **orch = bash（fleet 内新子命令）** —— 适用：只有 bash 可用；代价：JSONL 解析 + 状态机双实现、15m/90m 计时不可单测；不采纳（同 3 一类：拿不到进程边界）。
5. **orch 直连 herdr/intercom（绕过 fleet）** —— 适用：fleet 无可用接口；代价：重建放置键/槽位/身份判定，AC10 跨仓隔离必破；不采纳（`status --json` 只增输出，受 AC1 保护）。
6. **拆分按动词（放置面/回收面各一文件）或入口退役** —— 适用：动词间无共享私有函数 / 路径未外泄；代价：跨模块私有调用、破坏下游 shim 与 196 处用例；不采纳。
7. **锁改「pid 文件 + 心跳」** —— 适用：需要跨非 Linux 平台；代价：自己实现 stale 判定与 pid 复用防护；不采纳：systemd 已把阶段 2 绑在 Linux（PRD §十.2），不为 macOS 付这套代码。

## 后果与风险

- 正面：AC5–AC9 各有单一落点；`fleet` 从 5431 行降到单模块 ≤1250；`status --json` 成为唯一跨进程契约；AC9 有结构 + 静态双闸。负面：拆分真实成本在**用例侧**（5 个单文件静态闸改文件集 + `NAO_TERMINAL` 唯一性 lint，≈6 文件）；orch 新增 `bin/lib/queue.mjs` 共享模块的维护面。
- 风险：systemd 下的 PATH/herdr socket 是最脆一环（`doctor` 挡在 enable 之前，失败即不启用）；阶段 2 默认不启用，下游仓不会被动调度。
- 风险：WAL 与队列矛盾时选「冻结 + 交人」，牺牲自愈率换「绝不双派」——与 PRD §六「不自动重派，先让人看原因」同向。

## 限制与已知边界

- 非范围：自动合并/发版（AC9 永远禁）· 自然语言拆解 · 会话内容理解 · `blocked` 的自动出口（只到「留证 + 通知」，重新排队是人）。
- 定时精度 = timer interval（默认 2 分钟）：AC7 的 15m/90m 判据按 tick 采样，误差 ≤1 interval；不做 inotify/事件驱动（多一条守护面，换不来必要精度）。
- 拆分不重命名函数、不改行为（纯搬迁 + 依赖倒置）；`174` 是拆分时刻基线，之后新增函数须同步 `fleet/functions.txt`（一处 diff）—— 且此保护是**用例断言**而非文档约定（`cases/06` 或新例：总数不符/漏登记即红，新增函数必须同行改 `functions.txt`）。
- **实施分两批且顺序 = 先拆分（批次 A）后 orch（批次 B）**：A = 11 模块纯搬迁 + `fleet/functions.txt` + 5 个静态闸改文件集 + `NAO_TERMINAL` 唯一性 lint 跨模块总和=1，判据 = `status`/`check`/`--help` 拆分前后**逐字 diff 为空** + 174 并集守恒 + `check` rc=0 ×2 + 全量 `npm test` 绿；B = `bin/nao-orch` + `bin/lib/queue.mjs` + `fleet/status.sh` 的 `--json` + WAL/flock/CAS + AC9 双闸 + `cases/47` + systemd 单元。理由：先拆把「文件集静态闸 + 模块边界」一次到位，orch 的 AC9 lint 直接落在新结构上、不做二次迁移；且 `status --json` 落在 `fleet/status.sh` 比落在单体再搬更省。
- 批次 A/B 各自一个 PR、各自可 `git revert` 回滚（A 回滚后入口路径与行为不变）。
- AC1 口径订正（批次 A 实测）：`status`/`check`/`--help` 输出拆分前后逐字相同，**唯一例外 = `check` 汇总行的 `files=` 计数**（53 → 65，新增 11 模块 + `functions.txt` ⇒ 文件集真实变化，如实报）；不允许为了字面相等而让体检跳过新文件。
- 本文不含实施闸门 / 用例全文 / 接线清单（属 rd-infra 的实施报告）。

## 相关指针

- PRD `docs/prds/2026-11-24-orchestrator.md`（§四 数据契约 · §七 AC5–AC9）· 阶段 1 实施报告 `docs/reports/566-impl-rd-infra.md` · 文档规范 `.agents/checklists/deliverable-docs.md` §四 · 索引 `docs/adr/README.md`

## 参考来源

- [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) · 访问 2026-11-24 · `Type=oneshot` service + timer 是合法形态；`Persistent=` **仅对 `OnCalendar=` 生效**（据此选日历式，`OnUnitActiveSec` 拿不到补跑）。
- [flock(1)](https://man7.org/linux/man-pages/man1/flock.1.html) · 访问 2026-11-24 · 锁附着于 fd，进程退出即由内核释放 ⇒ 无 stale 锁文件问题（D4 选它而非 pid 心跳的理由）。
- [systemd.journal-fields](https://www.freedesktop.org/software/systemd/man/latest/systemd.journal-fields.html) · 访问 2026-11-24 · 自定义 journal 字段走 journal 原生协议（`sd_journal_send`），零依赖进程只能用 `SYSLOG_IDENTIFIER` + 单行 key=value。
