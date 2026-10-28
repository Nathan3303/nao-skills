# T4 用例集 —— nao-skills 单 SKILL 化 + pi 原生分发（PRD #18）

独立验证 PRD `docs/prds/2026-10-08-nao-skills-pi-package.md` 的 AC1/AC3/AC4/AC6 与
NFR2/NFR3，契约来源另含 §11 D3/D5/D6/D7、§12 闸门 A–D，以及
`docs/reports/2026-10-08-T1-pi-package-verify.md`（pi 1.1.0 实测）。

## 运行

```bash
bash tests/t4/run.sh --list                    # 列用例
bash tests/t4/run.sh --preflight               # 前置探测（不执行用例）
bash tests/t4/run.sh                           # 跑全部（默认严格：T2 产物缺失=FAIL）
bash tests/t4/run.sh --case 03                 # 单跑
T4_ALLOW_MISSING=1 bash tests/t4/run.sh        # 宽松：缺产物=BLOCKED（仅显式 1）
T4_REQUIRE_FULL=1 bash tests/t4/run.sh         # 发布前置：SKIP/DEGRADE>0 或非白名单 NOTE 即 FAIL
npm test                                       # 唯一机械门禁 = test:agents + test:t4
npm run test:t4:full                           # 发布前置双轴（= 上面两个环境变量 · 单环境）
npm run test:t4:full:dual                      # 发布前置**双环境** gate（两组串跑，任一红即红）
```

- **默认严格**：`T4_ALLOW_MISSING` 默认 `0` —— 依赖的 T2 产物缺失即 FAIL；宽松模式**只有显式 `T4_ALLOW_MISSING=1`** 才启用（缺产物记 BLOCKED）。
- **`T4_REQUIRE_FULL=1`**（与上者正交，只管 SKIP/DEGRADE/NOTE 三轴）：汇总层 **SKIP 计数 + DEGRADE 计数必须均为 `0`，且非白名单 NOTE 计数必须为 `0`** —— SKIP 含从用例输出解析的**行首** `[SKIP]` / `SKIP:` 行；DEGRADE 为能力降级标记；NOTE 按 tag 白名单判定（见下节）。发布用 `npm run test:t4:full:dual`（单环境退用 `npm run test:t4:full`）。
- **双环境 gate**：`npm run test:t4:full:dual`（`tests/t4/run-dual.sh`）= 同参数两组串跑 —— 组1 保留 `$TMUX_PANE`（撞号态）/ 组2 `env -u TMUX_PANE`（未设态）；**任一非 0 ⇒ 整体非 0**，输出标明组别与失败组。约 2× 单轮耗时；`npm test` 默认路径**不含** dual（不变慢）。
- **`test:t4:full` 能力要求**：`pi` CLI · tmux · bwrap · strace · npm registry 可达。缺任一即产生 DEGRADE/SKIP ⇒ **full rc≠0**（这正是 full 的意义：要求能力齐备）；默认 `npm test` 不因能力缺失变红。
- **用例 13 的额外能力依赖**：⑥（tmux 内名册可用且为空 ⇒ 「未运行（无需回收）」rc=0）与 ⑦（`--force` 不改末段判定）需要 `tsx`（跑名册探针夹具）；缺失时这两组记 `[DEGRADE]`（默认豁免、`test:t4:full` 计分），其余断言照跑。①–⑤（非 tmux ⇒ exit 3 三条 + `无法确认在线`/宿主阶梯删除面两条静态 grep）只依赖 bash + 本仓脚本，无额外能力。
- **用例 15 的能力与夹具纪律**：T2–T6/T8 需真 `tmux`（缺则整例 `SKIP`）；T1/T7/T9 需 `tsx`（假名册探针；缺则 T1–T9 记 `[DEGRADE]`），T10（`check` 守卫）纯 bash 照跑。夹具 = 真 tmux **隔离 socket**（≠ 生产默认候选；`TMUX_TMPDIR` 指向夹具目录，`env -u TMUX -u TMUX_PANE`）+ 假名册逐字段一行 pretty-print + 桩 `pi` 用**复制**的二进制（保 `comm=pi`）；收尾走机制 `cleanup -S <隔离 socket>`（不裸 `kill-server`）。
- **用例 16 的能力与边界**：只读 **Node 探针**（动态 import pi-subagents 的 `validateIntercomBridgeConfig` / `resolveIntercomBridge` + 桩配置）；`pi-subagents` 缺失（或 `node` 缺失）⇒ 整例 `SKIP`（不 FAIL、不计 DEGRADE）。只断言 **nao 自身契约**（模板存在/含 G1–G3/不含目标占位符 · 安装说明 · 协议小节四条 · 配置 schema 接受与拒绝），**不断言 pi-subagents 自身文案**（防版本脆断）；零 LLM/零网络、不依赖 `pi-intercom`/`tmux`。
- **用例 17 的能力与边界**：只读 **Node 探针**（动态 import pi-subagents 的 `registerRuntimeAgentEventListener` / `listRuntimeAgentConfigs`，桩 `pi.events` 假总线）；`pi-subagents` 缺失（或 `node` 缺失）⇒ 整例 `SKIP`（不 FAIL、不计 DEGRADE）。断言 **nao 自身契约**（6 条定义字节比对 / 锚点 cross-assert / 命名双向 / schema 与幂等 / 逃生阀 / 三态负控），**不断言 pi-subagents 内部文案**（仅判 ok/throw 与 `unknown fields` 形态，防版本脆断）；零 LLM/零网络、不真跑子代理、不依赖 `pi-intercom`/`tmux`。负控在 `$T4_CACHE_DIR` 夹具副本上做（不触碰仓库工作区）。
- **「子代理不属舰队会话」口径**：由 pi-subagents 拉起的 `subagent-*` 会话（`subagent-<agent>-<id>` / `subagent-chat-<id>`）**不属**舰队会话身份模型 —— `status` 只对其汇总计数（不列名、不参与在线/判重），`close subagent-*` 显式拒绝（生命周期归 pi-subagents 的 stop/retention）。`subagentfoo` / `mysubagent-x` / 裸 `subagent` 不入此面；`qa-subagent-x` 仍是合法派生名。
- **DEGRADE 语义**：环境缺能力但**其余断言继续跑**（不同于 `t4_skip` 会终止用例）；默认模式豁免、`T4_REQUIRE_FULL=1` 时计分。
- **计数可见**：汇总尾部打印 `SKIP=n · DEGRADE=m · NOTE=k` + **NOTE 白名单命中明细**（`用例号:tag` 列表，逐条可解释）；「绿 + N SKIP/DEGRADE」不得表述为「全量通过」。
- **安装包内不适用**：`tests/` 不入 npm tarball，在消费者机器上 `npm test` 因缺 `tests/t4` 而 rc≠0，属预期（见 `docs/releases/v0.18.0.md`）。

退出码：`0` 全 PASS/SKIP（DEGRADE 默认豁免）· `1` 有 FAIL / 参数错误 / 未识别状态（MISSING、NOT_RUN） / (full) 有 SKIP 或 DEGRADE · `2` 有 BLOCKED（仅宽松模式）。
参数错误（`--case` 缺值 / `--case` 无匹配 / 裸位置参数）一律 rc=1，不得静默全跑。

## 用例

| ID | 场景 | AC/NFR | 依赖 T2 产物 |
| :-- | :-- | :-- | :-- |
| 01 | 主路径足迹 + `check` exit=0 | AC1 | `init` + shim |
| 02 | 注册 skill 数==2 且无 collision | AC1/AC6 · D3 | `pi` manifest（动态另需 pi 凭据） |
| 03 | 未物化 exit 2 + `DEGRADED:` + 恢复命令；D7 防重入；D6 解析序 | AC3/NFR3 · D5/D6/D7 | `init` + shim |
| 04 | 零网络 `check` exit=0 + strace 无 AF_INET | NFR2 · 闸门B | `init` + shim |
| 05 | 迁移精准删除 + `.nao-obsolete` 备份 + 共享目录保留 | AC4 · §12-C/D | `migrate`（或 `init` 自动迁移） |
| 06 | 契约守护：AC6 机制侧 + AC8 manifest/注入 + AC2 静态 | AC2/AC6/AC8 | 无（读 manifest + 机制脚本） |
| 07 | 真实 `pi install` 与 tarball 布局对照 | AC1/NFR2 | `pi` + npm registry |
| 08 | 评审修复回归：F1 lock 保缩进 + F2 init --force 走 migrate 防混装 | AC4 · BR5 | `migrate` / `init` |
| 09 | T509 别名解析 / check 守卫 / close 跨仓回收 | AC3 · #19 | `init` + shim |
| 10 | T510 migrate 收尾：shim 判定式 / 开关 / 单行 lock 去重 | AC4 · BR5 · #21 | `migrate` / `init` |
| 12 | 派生会话 tmux 落点：宿主窗口显式寻址（含幂等/同源） | AC1–AC7 · T517 | 无（真 tmux 隔离 socket + 桩 pi；无 tmux 则 SKIP） |
| 13 | `close` 前提与末段：非 tmux ⇒ exit 3 单行提示且无副作用；tmux 内名册离线 ⇒ 「未运行」rc=0；`--force` 不改末段；`无法确认在线` 静态归零 | AC1/AC4 · T529 | `tsx`（名册探针夹具，缺则 ⑥⑦ DEGRADE）；①–⑤ 无依赖 |
| 14 | 夹具缓存生命周期：成功清理 / 失败保留 / 用户目录永不删（守卫负控 + 早退净增 0） | AC4–AC7 · T524 | 无（私有 `TMPDIR` 内纯本地，不依赖 tmux/tsx/网络） |
| 15 | 子代理会话（`subagent-*`）在 `status`/`close` 的显式识别与排除（汇总计数 / 显式拒绝且父 pane 存活 / E2 孤儿 pane 告警回归 / 前缀边界 / `check` 守卫） | AC2–AC8 · T525 | `tmux`（缺则 SKIP）· `tsx`（名册注入，缺则 T1–T9 DEGRADE）；T10 纯 bash |
| 16 | 子代理桥口径：模板 G1–G3 契约 + 无目标占位符 + 安装说明 + 协议小节四条 + pi-subagents 配置 schema 接受/拒绝 | AC2–AC7 · T526 | `pi-subagents`（缺则 SKIP）；纯 Node 只读探针，不依赖 tmux/tsx/网络 |
| 17 | 角色→子代理 agent 单一事实：装配字节比对（卡正文去 frontmatter）· 锚点 cross-assert · 命名双向 · 假总线注册 ×6 + 幂等 + 逃生阀 + 三态负控 | AC2–AC7 · T527 | `pi-subagents`（缺则 SKIP）；纯 Node 只读探针 + 夹具副本，零 LLM/零网络，不依赖 tmux/tsx |

## NOTE 白名单（T531 · `t4_note <tag> <msg>`）

NOTE = 用例产出的**事实性说明**（合法的能力/前提说明，不是通过证据）。为避免「能力缺失时用 NOTE 跳过断言而不阻断」，NOTE 改为**白名单制**并分轴判定：

- **签名**：`t4_note <tag> <msg>`；`tag` 必须是下列三个之一（枚举**单点定义**于 `tests/t4/lib.sh` 的 `T4_NOTE_TAGS`）。
- **合法 tag（3 个）**：
  - `static-contract` —— 用**静态断言**替代动态证据（如真 `pi` 加载需凭据，改判 manifest/文档契约）。
  - `pin-fallback` —— pin 版本尚未发布，改用已发布 `latest` 只做**布局**对照（内容差异不计）。
  - `migrate-fallback` —— CLI 未提供 `migrate`，改用 `init` 的自动迁移路径。
- **判定单点**：合法性只在 `run.sh` 汇总层判定（`t4_note` 只打印、从不 `exit`）。非 full ⇒ 只计数 + 未登记 tag 打 `WARN`（不阻断，日常 `npm test` 不因旧式调用变红）；`T4_REQUIRE_FULL=1` ⇒ **未登记 tag 或无 tag ⇒ `RESULT: FAIL` + rc≠0**，输出点名 `用例号:tag`。
- **旧式调用**（`t4_note "msg"`，无 tag）：打印为 `  [NOTE] (untagged) msg`；非 full 仍跑（仅警告），full 下 FAIL —— 兼容旧分支但不放纵。
- **新增 tag 的流程**：① 在 `tests/t4/lib.sh` 的 `T4_NOTE_TAGS` 加一项 ② 在本节写清「什么情况下允许、为什么不能改用 `t4_degrade`/`t4_skip`」③ 提交信息说明新增理由。两处缺一不可（`run.sh` 复用常量，不会漏判）。
- **优先用 `t4_degrade`/`t4_skip`**：真正的「能力缺失」应显式降级（full 计分）或跳过（计 SKIP），**不要**用 NOTE 掩盖断言未执行。

## 夹具缓存纪律

- **成功清理**：跑批 `rc=0` 且缓存目录是本进程自建 ⇒ 退出时删除该目录（含 `case-<id>.log`）。
- **失败保留**：`rc≠0`（FAIL / BLOCKED / MISSING / NOT_RUN，含 `T4_REQUIRE_FULL=1` 因 SKIP/DEGRADE 判 FAIL）⇒ 目录保留并打印路径，便于查看 `case-<id>.log`。
- **用户目录永不删**：显式传入 `T4_CACHE_DIR=<dir>` ⇒ 无论成败都不删，也不清理其中任何文件。
- **逃生口**：`T4_KEEP_CACHE=1`（env-only）⇒ 成功/失败两情形均恒保留。
- **只读命令不建目录**：`--list` / `--preflight` / 参数错误（`--case` 缺值 / 无匹配 / 裸位置参数）不创建缓存目录（零净增）。
- **单点实现**：清理逻辑只在 `tests/t4/lib.sh` 的 `t4_cache_cleanup` 一处（`run.sh` 复用），删除前五道守卫：仅自建归属（`T4_CACHE_OWNED=1`，不导出）· 前缀匹配创建时捕获的 `$T4_CACHE_PARENT/nao-t4.*` · 仅一层（禁 glob 穿越）· 是目录且非软链 · 非 `/`。
- **打印与实况一致**：汇总尾部 `缓存目录: …` 后随三态（`已清理` / `已保留：失败证据` / `用户提供 · 不删`，或 `已保留（T4_KEEP_CACHE=1）`）。

## 设计要点

- **不改仓库**：只读仓库，夹具全部在临时目录；`npm pack --ignore-scripts` 构造被测包，
  模拟 `pi install --local` 的落盘布局（`.pi/npm` + `.pi/settings.json`，T1 §2 实测）。
- **BLOCKED vs FAIL**：T2 产物缺失默认即 FAIL；只有显式 `T4_ALLOW_MISSING=1` 才降级为 BLOCKED(78)。
  汇总用白名单（仅 `PASS`/`SKIP` 通过），`MISSING`/`NOT_RUN`/未知态一律 rc≠0 —— 避免「用例未跑」被误读为「通过」。
- **可追溯**：每条断言前缀 `[PASS]/[FAIL]`，用例头注释给出 Given/When/Then 与 AC 映射。
- **零网络证据**：`bwrap --unshare-net` 环境隔离（强）+ `strace connect(2)` 无
  AF_INET/AF_INET6（直接证据）。
