# ADR：fleet 门面契约中性化 + 命名契约 v3

- 状态：已接受（待落地；Step 1 先合，Step 2 以 T569 合并后的 main 为基）
- 更新：2026-11-25
- Owner：arch-designer
- 指针：Issue [#197](https://github.com/Nathan3303/nao-skills/issues/197) · 用户 2026-11-25 拍板（先 ADR，不拆进程）· 关联 ADR `2026-11-24-herdr-app-backend.md` · 缺陷证据 `docs/reports/568-impl-rd-infra.md`

## 背景

- 门面把 herdr 的数据形状当跨后端契约；同日三条真机缺陷（app 空 tab name 致字段左移、app 终端 `name=null` 判未运行、`hc run --name` 拒 `role(task)` 括号）都是形状假设，不是实现错误。
- 第 3 条另一半是命名：`role(task)` 把派单信息编进身份，既撞后端合法名，又让复用/回收依赖字符串反解。
- 约束：不拆进程、不加第三后端、不复制业务层；herdr 行为除缺陷修复外逐字不变；`--task` 派单语义不变。
- 实测：`term.sh` 204 行 / 18 函数（公开 17 + 私有 1）；`term-herdr.sh` 1227 / 45；`term-app.sh` 763 / 33；`functions.txt` 头部 total 174。T569 caller-space 仍在 `feat/569-app-use-caller-space`（未合）；**Step 2 以「T569 合并后的 main」为基**，并重跑 T569 放置用例。
- 订正派单表格：`term_session_name` 实测返回后端**上下文句柄**（`HERDR_SESSION` / `HC_SCOPE`），并不从 label 推名；真正推名的是快照第 1 列。故该函数按现语义写死（不动），第 4 个形状面改为 `term_liveness` 的证据列。

## 决策

### 决策一：命名契约 v3（Step 1，先合）

- 会话名 = `<role>[<N>]`（N 为单字符 2..9，缺省 = 槽位 1）；`<role>(<task>)` 不再写入，task 不进身份。构造器删 task 参数，多传即 fail loud（不静默忽略）；解析签名不变，对只读旧形仍返回 task。
- `--task <id>` 仍必传，只落**元数据**：app 写 `nao.task=<id>` + `nao.name=<原始名>` 两个 label；herdr **无键值 label**，写本地 sidecar（`${NAO_FLEET_META_DIR:-$HOME/.local/state}/nao-fleet/session-meta/<workspace_ref>/<handle>`，临时文件 + mv 原子写）。**孤儿清理**：任何读快照的入口（status / orch tick / ensure）拿到 handle 集合后，删除 sidecar 中「不在当前集合」的条目（幂等；失败只 warn，不改 rc）；close/cleanup 另按 handle 即时删。两臂经同一读取面进入快照；读写失败降级为 `task=-`（元数据缺失不得阻断启动）。
- `ensure --task`：同 (role,task) 元数据命中 ⇒ 复用该名，否则取空闲槽位（`role` → `role2`…，与现行为一致）。**槽位号不得承载语义**（禁从 `role2` 反推任务，task 只认元数据）。`close --task <id> <role>`：按元数据匹配；0 命中 = 未运行，>1 命中 = 不猜（die）。`status --json` 增 `task` 字段；文本 status 列不变，只在派生节尾注 `task=<id>`。
- 只读兼容（永不复活为写入面）：`<role>(<task>)`（v2 在跑会话）、`<role>-<task>`、`<role>-<task>@<scope>`；三者 close/status 均可用（task 仍从名字解析）。
- 名称映射（总函数）：nao 名 → 后端合法名 = 小写化 + 非 `[a-z0-9-_.]` 替换 `-` + 首字符补齐 + 截 32 位（保留槽位后缀）；同 scope 冲突追加 `-<4hex>`。app 的 `hc run --name` 限 `[a-z0-9-_.]{1,32}`，用映射名、原始名存 `nao.name`；herdr pane label 用原始名（无该限制，**零改动**）。v3 正常名（角色 `[a-z0-9-]` + 数字）在两后端本就合法，映射只兜卡名/旧 `--as` 边界。
- 身份还原（修缺陷 2）：`labels.nao.name` → 后端 `name` → argv `--name`（仅当进程是 pi 且名字可被 `fleet_name_parse` 识别），首个非空即身份；app 的 `name=null` 不再跳过整行，旧终端无需迁移即可被识别。

### 决策二：门面契约中性化（Step 2，后合）

公共面只暴露中性投影；后端事实行（现 12 列及以后任何列）降为后端私有，业务层不可见。

- **`term_snapshot`**：无入参。每行 5 列 TAB：`<name>\t<status>\t<cwd>\t<handle>\t<task>`。
  - `name` = 身份还原结果；无身份的终端**整行省略**（不输出空字段）。
  - `status` ∈ `alive|working|idle|unknown`：`working` = agent 忙（herdr working/blocked；app working/blocked）；`idle` = 可信空闲（herdr agent_session 非空 + 钩子权威 + idle；app live + `reported:true` + idle）；`alive` = 终端/进程在但 agent 状态不可信（ghost、前台非 pi、集成缺失、app finished 残留）；`unknown` = 有身份但生命周期证据缺失。空值一律 `-`。
  - `cwd` = **归属 cwd**（herdr pane.cwd；app 终端 cwd，缺则 foreground_cwd），不取前台 cwd（前台只作诊断）。`handle` = 不透明白柄（pane_id / 终端地址），业务层禁解析。`task` = 元数据或旧名解析值，否则 `-`。
  - 失败：rc=0 + 零行 = 合法（无舰队会话）；rc=1 + stderr 恰一段（不可用/错误载荷/解析失败）+ stdout 不给半份。缓存仍每命令一份，属实现细节。
  - 映射：herdr 用 pane list / agent list / process-info；app 用 `hc ls` / `hc get` / labels；各自按上述语义归一，不共享列序。
- **`term_ws_label_rows`**：无入参；出参 `<space_ref>\t<label>`（`space_ref` 不透明，仅分组/显示；`label` = 放置键/仓基键）。空 label 行省略；后端不可用 ⇒ rc=0 + 零行（诊断面，环境错误由 snapshot 先报）。herdr = `workspace_id` + workspace label；app = doc 的 space id + folder 推的仓基键（含 2..9 号）。
- **放置面**（替换 `term_place_prime` / `term_place_reset`；业务层不再见任何 `_TERM_PLACE_*`）：`term_place_begin`（无参；rc=0 已建 / 1 不可用 + stderr）、`term_place_end`（无参，幂等 rc=0）、`term_place_rows`（每行 `<space_ref>\t<label>\t<name>\t<handle>\t<cwd>`，空值 `-`，rc=0）、`term_place_ws_for_label <label>`（stdout space_ref；未 begin ⇒ rc=1 + stderr；未命中 ⇒ 空输出 + rc=0，由调用方决定新建）。仅命令内有效、跨命令不缓存。herdr = workspace/pane list；app = doc.get + hc ls（caller-space 复用属后端私有）。
- **`term_session_name`**：无入参；恰一行 = 后端上下文句柄（herdr `HERDR_SESSION` / app `HC_SCOPE`），可空；rc 恒 0；只作诊断，**永不**作身份/放置判据（现状即此，写死）。
- **`term_liveness`**：签名与 4 字段输出不变；字段 1/2（verdict/state）是业务唯一可读面，字段 3/4 降为**后端不透明证据**（herdr seq/hook；app `-`/hook），业务禁读语义。实现改读后端私有事实行，不再从公共 `term_snapshot` 反推。
- 其余动作零改动，唯一例外：`term_spawn` 增第 7 个可选参数 `<task>`（只写元数据）；`term_deliver` / `term_argv` / `term_reclaim` / `term_cleanup` 等签名与 rc 不变。函数数公开面 17 → 19（−prime/reset，+begin/end/rows/ws_for_label 净 +2），`fleet/functions.txt` 与 cases/06 三向计数同 PR 更新。

## 理由

1. 业务匹配：三条缺陷都在「跨后端共享形状」处；形状收进后端、业务只依赖语义，同类 bug 结构上不可再发。
2. 成熟度：名/状态/目录/句柄是各终端后端的最小公倍数；无需协议或进程边界。
3. 团队能力：两后端仍在同一 shell 层与 source 拓扑；改动集中在 4 个面与 10 余个调用点。
4. 成本：Step 1 小面止血（命名 + 元数据），Step 2 治本；两步可独立 revert。

## 对照过的备选模式

1. **维持现状（基线）** —— 适用：单后端或形状稳定；代价：三次真机缺陷已证伪；不采纳。
2. **两套完整 fleet（两后端各一份业务层）** —— 适用：语义彻底不同；代价：复制约 3000 行业务，T551/T552 已示范双实现漂移；不采纳。
3. **拆进程/子进程反代（JSON 协议）** —— 适用：跨语言或第三方写后端；代价：序列化 + 版本协商 + 调试面，当前无需求；不采纳。
4. **保留 `role(task)`，只给 app 转义名字** —— 适用：task 必须出现在 UI 名里；代价：身份仍编派单信息、close/status 继续反解字符串、双轨名；不采纳。
5. **本方案（v3 + 中性契约）** —— 适用：双后端 + 单业务层；代价：一次性契约迁移 + 用例重写；采纳。

## 后果与风险

- 正面：`--task` 在 app 100% 可起；空 name / 空 tab name / 非法字符三类缺陷被契约堵死；业务层不再能看见后端字段。
- 负面：Step 1 触及 12 个用例文件与 37 个文档/角色卡（契约变更，`cases/28` 须**整组重写**，不是改断言）；建议 RD 拆 3–4 个 wip 提交（契约/解析面 → 调用点 → 用例 → 文档）。Step 2 改门面函数数与 cases/06 计数；herdr 新增 sidecar 持久面（原子写、按 handle 清理 + 孤儿扫描，失败降级为 task 不可知）。
- 连带同步（改既有条款，Owner 明确）：`.agents/common/intercom-protocol.md`（PM）· `README.md` / `docs/INSTALL.md`（PM）· `nao-fleet` skill（PM）· 37 个文档/角色卡（各角色 owner）。
- 风险：v3 后同 role 多任务只靠槽位号区分，靠元数据 + status 显示缓解（已拍板：够，且槽位号不承载语义）。
- 回滚：两个 PR 各自 `git revert`；只读兼容保证回滚后 v2 名仍可 close/status。
- 测试策略：同一套契约断言跑两个适配器 —— 桩后端（确定性，可注入空名/空 tab/异常形状）+ 真后端面（私有 herdr core / 私有 app core，有则跑）；业务层加静态闸（禁 `_TERM_PLACE_*` / `pane_id` / `workspace_id` / `agent_status` / `argv_name` / `hook` 等后端词）并做双向负控。四条回归：空 tab name 不左移、app `name=null` 仍在线、`ensure --task` 在 app 成功、sidecar 孤儿清理（造 3 个条目、快照只剩 1 handle ⇒ 另 2 个被清且 rc 不受影响）。
- 顺序：Step 1 可先合；Step 2 以 T569 合并后的 main 为基，并重跑 T569 放置用例。

## 限制与已知边界

- 非范围：拆进程 / 第三后端 / tmux 回归 / 业务层复制；不改 intercom 名册协议；不迁移已在跑的会话名。
- app 的 UI 收养效果仍不可自动化（沿用 2026-11-24 ADR 的人工验收边界）；sidecar 只存 task id，无敏感值。
- 只读旧形永久保留解析面，但写入面只有 `<role>[N]`。

## 拍板结论（3 条已裁定）

1. 同 role 多任务并行：仅槽位号 ⇒ **够**；task 在元数据、status 可见，`close --task` 唯一匹配；**槽位号不得承载语义**。
2. 文本 `status` **不新增 task 列**（保 AC 逐字）；`status --json` 增 `task` 字段 + 派生节尾注。
3. legacy 只读面：**永久只读 + 每两个 MINOR 重评**，**已转办台账**（台账含 `grep -c` 旧形出现面 + 到期日期，可机械判定）。

## 相关指针

- Issue #197 · ADR `2026-11-24-herdr-app-backend.md` · 缺陷证据 `docs/reports/568-impl-rd-infra.md` · PRD 骨架规范 `.agents/checklists/deliverable-docs.md`

## 参考来源

- [herdr pane CLI（本机 `herdr pane rename --help`：单 `LABEL`；`report-metadata` 为 display-only）](https://herdr.dev/agent-guide.md) · 访问 2026-11-25 · pane 只有一个 label，metadata 不能承载键值元数据。
- [herdr desktop app 契约调研](../research/2026-11-22-herdr-desktop-app.md) · 访问 2026-11-25 · app 终端支持 `--label k=v`，`name` 可空，收养异步。
- [herdr releases](https://github.com/herdrdev/herdr/releases) · 访问 2026-11-25 · 本机锚点 `hc 0.1.22` / `herdr-app 0.1.16`；无公开键值 label 契约。
