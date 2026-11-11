# #96 二期 B4 —— D 类 10 例迁移 + 登记集终态 + 台账清零

> 分支 `feat/96p2-b4-dclass`（base main `2967c9e`）· 范围 = PRD `docs/prds/2026-11-10-herdr-base.md` 附二 B4
> 交付口径：`herdr.txt` 终态（5 shared / 3 own / 2 tmux 专有 / `case28` own）· `PENDING = 0` · 台账 3 → 0 · `check` 双模式对照 · 三处 BR1 md5

## 一、做了什么（按 PM 六项）

1. **D 类 10 例按 AC2.7 分流**：19/20/21/23/24 → shared；09/15/22 → own（到期 2027-06-30，逐条理由见 `tests/t4/backends/herdr.txt`）；
   12/25 → **tmux 专有**（注释区 `# tmux-only: 12 25` + 运行期 `[TMUX-ONLY]` 单列计数，三期重判）。
2. **新增 herdr 专有 3 例**：`29` 就绪门反假阳性 · `30` 幽灵 pane · `31` 集成缺失 fail loud（均登记 own）。
3. **`check` 的「生效后端」节**：B1 已落地（herdr 模式加一行 / tmux 模式零新增）；本批只把该行文案里的台账数
   由「3 条」改为「0 条」，并重测**逐字对照**（见 §六）。
4. **台账 3 → 0**（`tests/t4/fixtures/term-legacy-allowlist.txt`）：`apply_main_col` / `apply_tmux_layout` 整段进
   `# >>> term-impl-tmux (布局 / 窄列回退)` 标记区（布局是**后端专有证据层**，三期整体替换）；
   `cmd_check` 唯一的裸调用 `tmux display-message -p '#S'` 换成门面 `term_session_name`
   （tmux 实现 `_term_tmux_current_session` 在既有 tmux 标记区内；herdr 实现直接回 `HERDR_SESSION`）。
   零行为改动：tmux 侧输出逐字不变（§六 md5 + §七 C2 golden md5）。
5. **`case28` 登记**（B1 就记下的账）：own，理由 = golden 对照以 tmux 为对照载体（基线 fixture = tmux 时代整脚本 +
   `bash -lc` 落地段 md5），herdr 侧零回归由同用例「双拼写 md5 + B3 段」承担。
6. **PENDING 归零**：本批后 herdr 侧 `PENDING 0`（无遗留；12/25 走 tmux-only 声明，不占 PENDING）。

## 二、关键实现决策（含理由）

- **herdr 侧用确定性替身而不是真 herdr + 真 pi**（`tests/t4/fixtures/herdr-double/`）。
  理由（实测，非推断）：① herdr 的就绪/在线判据要求 pi 生命周期钩子权威（`agent_session` + `screen_detection_skipped`），
  而 pi 的 herdr 集成装在**用户 `$HOME` 的 pi 配置**里 ⇒ 真跑必须写用户 `~/.pi/agent/sessions`（脏用户态）；
  ② 把 `HOME` 换到夹具后集成不加载，就绪门**永不通过**（实测 `agent_session` 空 + `skip=false`）；
  ③ herdr 0.9.x 是 pre-1.0，真后端的时序/字段可能漂移。替身把结构化事实做成**可编排**夹具，
  于是 shared 用例的断言面仍只落在「我们自己的输出 / argv / 文件内容」（AC2.7 的 shared 定义），
  与 B1/B2/B3 用 PATH 桩测 herdr 分支同口径。替身**只**在测试侧出现，生产脚本零依赖。
- **`be_*` 扩到「用例侧夹具 API」**（`lib-backend.sh`）：`be_ensure_scene` / `be_caller_pane` / `be_set_name` /
  `be_fixture_session` / `be_pane_label` / `be_pane_cwd` / `be_pane_cmdline` / `be_pane_argv` / `be_pane_by_name` /
  `be_kill_pane` / `be_scene_signature` / `be_fleet_handles` / `be_run_fleet`（+ `BE_FLEET_SCRIPT`、`BE_FLEET_NO_HANDLES`）。
  后端差异**单点**收在这一层，用例正文只写断言。
- **`be_fixture_session` 的 tmux 实现用 OSC 0 + `exec sleep`**（不是 `select-pane -T`）：#90 定性的根因是
  `select-pane -T` 会被 pane 内 shell 的 PS1 随后重写（负载相关假红）。`be_set_name` 仍保留 `select-pane -T`
  作为「只改标题」的原语（PM 指定形态），稳定夹具走前者。
- **后端门控一律显式**（新增 NOTE tag `backend-gate`，已登记白名单 + `tests/README.md`）：
  每处都写「为什么本后端不可达」，避免静默跳过；herdr 模式 NOTE 共 9 条（`backend-gate` 7：09×1 / 15×3 / 19×1 / 20×1 / 23×1；另有 `static-contract` 2：06）。
  与 `t4_skip` 的区别：其余断言照跑、用例仍 PASS 计分。
- **`run.sh` 新增 tmux-only 机器可读声明**：`# tmux-only: 12 25` → `[TMUX-ONLY]` 点名 + 单列计数（不算 PENDING/SKIP），
  汇总行改为 `共享 N / 本后端专有 M / tmux 专有 K / PENDING P`，并追加「对账：N+M+K+P = `--list` 计数」。

## 三、逐例 delta（运行时 `[PASS]` 行；tmux = `npm test`，herdr = `NAO_TEST_TERMINAL=herdr`）

| 用例 | tmux | herdr | 变化 | 说明 |
| :-- | --: | --: | --: | :-- |
| 09 | 47 | 35 | −12 | AC3 撞号/跨 server 见证/自 pane 双驱动（tmux 专有）→ herdr 等价组（(session,pane) 语义：跨仓真回收 + `HERDR_PANE_ID` 不可判定档拒）＋`backend-gate` 点名 |
| 12 | 0（**不计 `[PASS]` 行**） | 0（`TMUX-ONLY`） | 0 | tmux 专有声明（三期布局）；tmux 侧**真跑 36 条子断言**（断言实体是 QA 冻结的外部脚本，自有输出但不产 `[PASS]` 行）⇒ 不是「未跑」；不再计 PENDING |
| 15 | 47 | 41 | −6 | T8 孤儿 pi pane（tmux 未归属启发式）→ `backend-gate`；T1/T9 的 roster 口径 → label 夹具等价组（+4 条 herdr 专属断言） |
| 19 | 67 | 60 | −7 | ③ 不可判定归属（tmux detached 夹具）+ AC5① 基线逐字对照 → `backend-gate`；其余（①②④⑧ + M 双向变异 + AC5② 键口径变异）两后端同跑 |
| 20 | 106 | 106 | 0 | 仅 AC1①「与调用者同窗口」换等价判据（herdr：同场 pane + cwd 正确）＋1 条 NOTE |
| 21 | 102 | 102 | 0 | 「零副作用」签名改后端无关（tmux=pane+session / herdr=pane+workspace），断言数不变 |
| 22 | 34 | 34 | 0 | 三态/摘要两后端同形（1/1/1 守恒）；差异只在注入点（split-window vs pane run）与「失败保留 pane」增量判据 |
| 23 | 52 | 48 | −4 | argv 级断言（桩 pi 落盘）→ `backend-gate`；herdr 以「交给后端的原始命令串」**字节级**对照等价覆盖（含 `%q(消息)` 全文）+ 3 条结构性计数 |
| 24 | 78 | 78 | 0 | 同 23 的捕获口径，无 argv 级断言 ⇒ 零门控 |
| 25 | 29 | 0（`TMUX-ONLY`） | 0 | tmux 宽度算式 + 活体 pane 数（tmux 侧 29 条 `[PASS]` 真跑）；三期重判 |
| 27 | 44 | 64 | +20 | herdr 侧多跑后端专属断言（既有设计，非本批改动） |
| 28 | 367 | 367 | 0 | 命名契约 + B3 段；herdr 模式复用同一 golden 载体 |
| 29/30/31 | 0（门控） | 18/19/16 | 新增 | 三条新 herdr 专有例；tmux 后端按 `backend-gate` 点名退出（0 断言，非 SKIP） |

合计：tmux **1550** → herdr **1565**（`[PASS]` 行）；用例数 27 → **30**（`--list`）。

## 四、新增 3 例的红/绿证据

- **29 就绪反假阳性**（`cases/29-herdr-ready-gate.sh`）：
  红态 = 替身旋钮 `pi_seq=0`（pane 已 idle、agent_session/钩子齐备，但**从未观测到状态迁移**）⇒
  `ensure` 输出「就绪门超时」+ 逐条点名「state_change_seq ≥ 1」+ 零假成功行 + 摘要「成功 0 / 跳过 0 / 失败 1」+ **rc 仍 0**（D3）；
  绿态 = 同一夹具只把 `pi_seq` 抬到 1 ⇒ 「[herdr] 已拉起」恰 1 行 + 摘要 1/0/0（证明不是恒定红）；
  静态 = 代码行里 0 处 `agent wait`（注释里的禁令不算），七条就绪条件逐条可点名。
- **30 幽灵 pane**：label 在、前台 shell（agent 条目缺）⇒ `status` 显式「幽灵 pane」+ 不可投递 + **不**打 `✓ rd-fe`；
  `ensure` 点明「幽灵 pane / stale」+「不判「已在运行」」并**复用重跑**（摘要成功 1，且**不**走「已在运行 ⇒ 跳过」分支）；
  反向对照 = 同一 label 换成 pi ⇒ `✓ rd-fe 在线` + `ensure` 判「已在运行」。
- **31 集成缺失**：旋钮 `pi_session=false` ∧ `pi_skip=false` ⇒ `status` 点名「集成缺失」+「不可投递」+ 根因（agent_session/钩子权威）
  + 指路（核对 pi-intercom/herdr 集成），不打在线；`ensure` 零假成功行 + 摘要失败 1；
  反向对照 = 补齐证据 ⇒ 在线 + 「已在运行」；静态 = `term_deliverable` 只放行 `idle|done`（`unknown` 不在可投递分支）。

## 五、台账清零与「只减不增」仍咬

- 终态：`baseline: 0` 且**条目数 0**（`grep -vcE '^[[:space:]]*(#|$)'` = 0，用例 06 断言）。
- 负控（自造第 1 条）实测三连红：
  `台账不得收录渲染层/门面函数: cmd_status` · `台账 stale（该函数已无裸后端调用，应删条目）` · `台账行数 1 超过 baseline 0（只允许下降）`。

## 六、`check` 双模式对照（BR1）

同一环境、同一份 `NAO_SKILLS`，改动前后脚本对跑：

- tmux（未设 `NAO_TERMINAL`）摘要：prev `31b5978e95e7f5b4dc7a9fd861548065` / new 同值，`diff` 空；
- tmux `check -v`：prev `ab4529d913e381513de7d771cf4091fc` / new 同值，`diff` 空；
- herdr 模式：与 tmux 摘要 **只差一行** `  · 生效后端 NAO_TERMINAL=herdr（…台账 0 条）`（`diff` 只有 `2a3` 一条新增）；
- `check` 连跑 2 次：rc=0 ×2，md5 `31b5978e…` 相同（同输出）。

## 七、BR1 三处 md5（用例 28）

- C2① `status` 全文：`144f3447c9ff406d6aed828d9c9720e5`（两场相等，行数 15；双拼写「未设 / `=tmux`」与之相等）；
- C2② `ensure` 已拉起 blob：`c2de6533a1826dbf470dcc401cb29063`（9 条已拉起 + 9 个 `--name` 值）；
- B3① tmux 落地段：句柄层 `9549f513b7a66fbced68bc1a1fa1dc10` · cleanup 体 `d8937134bb3ed4ceca29fb581d4acf2c` ·
  生产默认 socket 候选表 `e4950f3897670a97d7baaea8f54727c3`（均与 B3 之前逐字相等；另有「多一个空格 ⇒ 必红」变异自证）。

## 八、门禁

- `bash .agents/scripts/nao-fleet.sh check` rc=0 ×2（同输出，md5 `31b5978e…`）。
- `npm test` rc=0：`SKIP=0 · DEGRADE=0 · NOTE=6`（运行时 `[PASS]` 行 **1550**）。
  注：同批早前一轮曾出现 `SKIP=1`（用例 07「npm registry 不可达」），复跑即 8 条断言通过 ⇒ 环境/网络波动，非本批引入。
- `NAO_TEST_TERMINAL=herdr bash tests/t4/run.sh` rc=0：`共享 20 / 本后端专有 8 / tmux 专有 2 / PENDING 0`，
  对账 `20+8+2+0 = 30`（`--list` 计数 30），`SKIP=0 · DEGRADE=0 · NOTE=9`（＝ `backend-gate` **7** 条 + 06 的
  **2** 条 `static-contract`）；运行时 `[PASS]` 行 **1565**。
- 例数唯一出处：`bash tests/t4/run.sh --list | tail -n +2 | wc -l` = **30**（01–10 + 12–31，无 11）。

## 九、边界与未验（不隐瞒）

- 替身**不验证**真 herdr 的 CLI 行为（时序/退出码/字段漂移）；真后端的行为面由 B1/B2/B3 的实现与 `cases/27`
  的自检 + 生产侧 `_term_herdr_*` 覆盖。三期转默认时应补一次**真 herdr** 的整轮对照（已记入 27/28 的到期复核理由）。
- `backend-gate` 有两层数字，别混：**代码站点 11 处** = herdr 侧触发 **7**（09×1 / 15×3 / 19 AC5① / 20×1 / 23×1：
  同一断言在另一后端结构上不可达）＋ tmux 侧触发 **4**（19③ 与 29/30/31 在 tmux 后端按门控早退，0 断言，非 SKIP）；
  **herdr 模式 NOTE 9 条** = 上述 7 条 `backend-gate` ＋ 06 的 2 条 `static-contract`（tmux 侧那 4 个触发点在 herdr
  模式**跑满**、不产 NOTE，故 11 ≠ 9）。逐处理由写在用例内；三期（布局/多仓形态）落地后 20/19 的两处门控应重新评估。
- **就绪门超时的常见真因不是「集成缺失」**：本机 pi **1.5.2** 而 `~/.pi/agent/settings.json` 的
  `lastChangelogVersion=1.5.1` ⇒ 新起 pi 停在 **What's New 遮罩**、会话钩子不触发 ⇒ 就绪门超时。fail loud 的方向对，
  但旧文案只指「集成缺失」会把人引偏：已在就绪门超时诊断与 `status` 集成缺失文案各补一句
  「若 pi 首次启动停在 What's New / 信任提示，先手工关闭再重试」。
- 22 的 herdr 失败分支**保留 pane**（先建后注入，不自动 kill）⇒ pane 增量判据按后端分叉（已断言，不是漏洞）。
- 真机未验：herdr 0.9.x 后续版本的字段变更；`blocked` 态真机触发（PRD 附二「未验」项不变）。
