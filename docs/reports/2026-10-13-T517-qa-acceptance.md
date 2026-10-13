# T517 QA2 独立验收：派生会话 tmux 落点修正

- 结论：**GO** · 日期：2026-10-13 · Owner：qa（不采信 rd-infra 自证，全部独立跑批）
- 验收对象：分支 `feat/33-derived-pane-window` @ `a4b05a2`（实施 `27b49ac` + AC8 `bb324b6` + 用例 `a4b05a2`）· Draft PR #34
- 判据来源（唯一）：`docs/prds/2026-10-13-t517-derived-pane-window.md` §七 AC1–AC9
- 边界：`.agents/scripts/nao-fleet.sh` 只读；实验一律 `-S <隔离socket>` + `env -u TMUX`，收尾 `cleanup -S`；未动用户 tmux server。

## 一、逐 AC 结果（修复前 T517_FLEET=4037737 冻结脚本 vs 修复后 a4b05a2）

| AC | 断言要点（独立实现） | 修复前 | 修复后 |
| :-- | :-- | :-- | :-- |
| AC1 零回归 | 单窗口三布局几何逐值 = T513-AC7 golden + pane 无外溢 | 6P/0F | 6P/0F |
| AC2 缺陷（无 client，核心） | current W2/调用者 W1 ⇒ 落 W1；W2 pane 数与 `window_layout` 不变 | 1P/3F | 4P/0F |
| AC3 缺陷（有 client） | pty client 视图 W2 ⇒ 仍落 W1；W2 不变 | 1P/2F | 3P/0F |
| AC4 布局/选项不外溢 | main-col 几何 + `main-pane-width`=35% 落 W1；W2 选项/layout 零变化 | 0P/4F | 4P/0F |
| AC5a 宿主窗已关 | `NAO_TMUX_HOST_WINDOW=@99` ⇒ rc 不劣化、可观测诊断、W2 不被回退污染 | 1P/2F | 3P/0F |
| AC5b TMUX_PANE 空 | 明确降级（诊断指名原因，不静默）、rc=0 | 1P/1F | 2P/0F |
| AC5c 跨 session | 落调用者 session A（golden）、client 视图 B 不变 | 2P/0F | 2P/0F |
| AC5d 宿主窗极窄 | W1=80 ⇒ 窄列守卫按宿主宽生效（几何=80 列 golden + warn）、宽 W2 不被污染 | 0P/3F | 3P/0F |
| AC6 幂等 | 2 次 ensure 第 2 次命中 running 跳过（pane 不变 + 2 处「已在运行」）；`--force` +1 且收敛 golden | 5P/0F | 5P/0F |
| AC7 同源 | `--task` 派生在 AC2/AC4 场景与常驻 ensure 逐值一致（落 W1 + golden，W2 零变化） | 0P/4F | 4P/0F |
| **合计** | — | **17P/19F** | **36P/0F** |

- 修复前红色 = 缺陷确定性复现（AC2 现场：W2 pane 1→4、layout `babe`→`52a6,…`，W1 保持 1 pane——与 PRD §一根因一致）。
- AC6 为幂等/判重语义，行为与宿主寻址无关（修复前亦绿，属预期）；AC5c 为本机 tmux 上的 D4 语义守卫（见风险）。

## 二、AC9 全范围门禁（不采信自证，本机独立跑批）

| 门禁 | 命令 | 结果 |
| :-- | :-- | :-- |
| 机制体检 | `bash .agents/scripts/nao-fleet.sh check` | exit 0 · roles=6 · files=42 · layout=main-row2 |
| 包门禁 | `npm test` | exit 0（check + `tsc -p tsconfig.agents.json`） |
| T4 全量 | `T4_ALLOW_MISSING=0 bash tests/t4/run.sh` | exit 0 · **12/12 PASS · 263 断言 / 0 红 / 0 SKIP** |
| 本批用例 12 | `env -u TMUX bash tests/t4/run.sh --case 12` | exit 0 · **36/36 PASS / 0 红** |

## 三、AC7 同源核对（代码链 + 行为命中）

- **代码链（只读）**：`cmd_ensure` 入口对 `$TMUX` 分支一次性调用 `resolve_host_window`（L1 覆盖 → L2 TMUX_PANE→window_id → L3 名册限本 session 唯一 → L4 skip），与角色/任务无关；`--task` 仅改 `disp=<角色>-<任务>`（intercom 身份/running 键），不触碰宿主解析。`spawn_tmux` 与全部布局调用共用全局 `HOST_WINDOW`（`-t` 贯穿 `split-window` / `select-layout` / `set-window-option main-pane-width`）——**常驻与派生同一条落点逻辑，无人工分叉分支**。
- **行为命中**：AC7 ①(AC2 场景)/②(AC4 场景) 下 `ensure --force --task T77` 与常驻结果的几何/负向逐值一致（4/4 PASS，修复前 4/4 红）。

## 四、T513 冻结脚本适配（验收轮连带，非实现缺陷）

实施后 AC9 首次全量暴露 case 11（`2026-10-12-T513-verify.sh`）10 项 FAIL，根因排查：**T517 新契约使旧夹具的「TMUX 已设但 TMUX_PANE 空」状态不再合法**——真实 tmux 调用者必有 TMUX_PANE；旧夹具未设 ⇒ 现按 AC5b 既定降级走 warn+skip（禁无 `-t` 续建，即缺陷根因）。判定为测试侧连带失效，非实现缺陷（若实现为兼容旧夹具而恢复无 `-t` 续建，恰会回退缺陷）。适配（断言意图不变）：

1. AC7/AC10 真 tmux 夹具补 `TMUX_PANE`（= 会话原始 pane，宿主窗口解析源）；
2. 桩 `tmux display-message` 增补 `#{window_id}`/`#{session_id}` 应答（L2/L3 探测）；
3. AC12 F2边界② 的 split-window argv 断言**再基线**为显式契约 `split-window -h -t @0 bash -lc …`（F2 不变量「不注入 `env -u TMUX`」保持）。

适配后 case 11：**85/85 PASS**（修复前此 10 项本就为旧契约下的冻结口径；不变式：单窗口几何逐值 golden、判重跳过、未认领 pane 启发式、argv 无 env 注入均保留）。

## 五、遗留风险 / 局限

- AC3/AC5c 依赖 `python3` pty 创建假 client；无 pty 能力的环境该两组自动 SKIP（不误报 PASS）。本机已验证。
- AC5c：tmux 3.7c 实测旧实现经 `$TMUX` 第三段也能落调用者 session，故该用例为 D4 语义**守卫**而非本机缺陷探针；跨窗口缺陷本体由 AC2/AC3（修复前红）覆盖。
- L3 名册推断仅发生在 TMUX_PANE 缺失/失效的退化场景（AC5b），按 PRD 为 warn+skip（AC5a/b 已验证不拆用户窗口）；真实环境极少触发。
- 验收未触达：AC8 文档同步（`intercom-protocol.md` 措辞 `bb324b6` 已合并入分支，本批未专项断言）、发布/回滚（PM 环节）。
- 无阻塞项，未产生缺陷单（`docs/reports/2026-10-13-T517-defects.md` 未创建）。