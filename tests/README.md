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
T4_REQUIRE_FULL=1 bash tests/t4/run.sh         # 发布前置：SKIP 计数>0 即 FAIL
npm test                                       # 唯一机械门禁 = test:agents + test:t4
npm run test:t4:full                           # 发布前置双轴（= 上面两个环境变量）
```

- **默认严格**：`T4_ALLOW_MISSING` 默认 `0` —— 依赖的 T2 产物缺失即 FAIL；宽松模式**只有显式 `T4_ALLOW_MISSING=1`** 才启用（缺产物记 BLOCKED）。
- **`T4_REQUIRE_FULL=1`**（与上者正交，只管 SKIP/DEGRADE 轴）：汇总层 **SKIP 计数 + DEGRADE 计数必须均为 `0`** —— SKIP 含从用例输出解析的**行首** `[SKIP]` / `SKIP:` 行；DEGRADE 为能力降级标记。NOTE 允许并计数。发布用 `npm run test:t4:full`。
- **`test:t4:full` 能力要求**：`pi` CLI · tmux · bwrap · strace · npm registry 可达。缺任一即产生 DEGRADE/SKIP ⇒ **full rc≠0**（这正是 full 的意义：要求能力齐备）；默认 `npm test` 不因能力缺失变红。
- **用例 13 的额外能力依赖**：④（名册可用且为空的反向断言）与 ⑤（`offline_verifiable` 判据三处）需要 `tsx`（跑名册探针夹具）；缺失时这两组记 `[DEGRADE]`（默认豁免、`test:t4:full` 计分），其余断言照跑。①②③⑥ 只依赖 bash + 本仓脚本，无额外能力。
- **DEGRADE 语义**：环境缺能力但**其余断言继续跑**（不同于 `t4_skip` 会终止用例）；默认模式豁免、`T4_REQUIRE_FULL=1` 时计分。
- **计数可见**：汇总尾部打印 `SKIP=n · DEGRADE=m · NOTE=k`；「绿 + N SKIP/DEGRADE」不得表述为「全量通过」。
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
| 11 | 宿主阶梯 / 失败语义 / 非 tmux 句柄 | AC1–AC14 · T513 | 无（桩驱动 + 真 tmux） |
| 12 | 派生会话 tmux 落点：宿主窗口显式寻址（含幂等/同源） | AC1–AC7 · T517 | 无（真 tmux 隔离 socket + 桩 pi；无 tmux 则 SKIP） |
| 13 | `close` 末段在线判定护栏：不可验证 ⇒ 非静默失败（双侧极性 + 判据三处） | AC2–AC8 · T523 | `tsx`（名册探针夹具，缺则 ④⑤ DEGRADE）；①②③⑥ 无依赖 |

## 设计要点

- **不改仓库**：只读仓库，夹具全部在临时目录；`npm pack --ignore-scripts` 构造被测包，
  模拟 `pi install --local` 的落盘布局（`.pi/npm` + `.pi/settings.json`，T1 §2 实测）。
- **BLOCKED vs FAIL**：T2 产物缺失默认即 FAIL；只有显式 `T4_ALLOW_MISSING=1` 才降级为 BLOCKED(78)。
  汇总用白名单（仅 `PASS`/`SKIP` 通过），`MISSING`/`NOT_RUN`/未知态一律 rc≠0 —— 避免「用例未跑」被误读为「通过」。
- **可追溯**：每条断言前缀 `[PASS]/[FAIL]`，用例头注释给出 Given/When/Then 与 AC 映射。
- **零网络证据**：`bwrap --unshare-net` 环境隔离（强）+ `strace connect(2)` 无
  AF_INET/AF_INET6（直接证据）。
