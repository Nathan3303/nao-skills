# T4 用例集 —— nao-skills 单 SKILL 化 + pi 原生分发（PRD #18）

独立验证 PRD `docs/prds/2026-10-08-nao-skills-pi-package.md` 的 AC1/AC3/AC4/AC6 与
NFR2/NFR3，契约来源另含 §11 D3/D5/D6/D7、§12 闸门 A–D，以及
`docs/reports/2026-10-08-T1-pi-package-verify.md`（pi 1.1.0 实测）。

## 运行

```bash
bash tests/t4/run.sh --list                 # 列用例
bash tests/t4/run.sh --preflight            # 前置探测（不执行用例）
bash tests/t4/run.sh                        # 跑全部（宽松：T2 未交付=>BLOCKED）
T4_ALLOW_MISSING=0 bash tests/t4/run.sh     # T2 回执后严格复跑（缺产物=FAIL）
bash tests/t4/run.sh --case 03              # 单跑
```

退出码：`0` 全 PASS/SKIP · `1` 有 FAIL · `2` 有 BLOCKED。

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

最近一次跑批：`T4_ALLOW_MISSING=0 bash tests/t4/run.sh` → exit 0 · 8/8 PASS · 109 断言 / 0 红
（复跑基线 `5537270` v0.12.0；详见 `docs/reports/2026-10-08-T4-qa-report.md`）。

最近一次跑批：`T4_ALLOW_MISSING=0 bash tests/t4/run.sh` → exit 0 · 7/7 PASS · 94 断言 / 0 红
（详见 `docs/reports/2026-10-08-T4-qa-report.md`）。

## 设计要点

- **不改仓库**：只读仓库，夹具全部在临时目录；`npm pack --ignore-scripts` 构造被测包，
  模拟 `pi install --local` 的落盘布局（`.pi/npm` + `.pi/settings.json`，T1 §2 实测）。
- **BLOCKED vs FAIL**：T2 产物缺失在宽松模式记为 BLOCKED(78)；T2 回执后以
  `T4_ALLOW_MISSING=0` 复跑，缺失即 FAIL。避免「用例未跑」被误读为「通过」。
- **可追溯**：每条断言前缀 `[PASS]/[FAIL]`，用例头注释给出 Given/When/Then 与 AC 映射。
- **零网络证据**：`bwrap --unshare-net` 环境隔离（强）+ `strace connect(2)` 无
  AF_INET/AF_INET6（直接证据）。
