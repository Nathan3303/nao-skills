# T4 发布后核验：`@nathan33/nao-skill@0.12.0`（真实安装 + 发布物内容）

- 状态：**两段核验完成 · 全部通过 · 未发现缺陷** · 更新：2026-10-08 · Owner：qa
- 分支/线：`main`（需求分支 #18 已合并）· 目的：发布后收尾核验（arch 验证口径提醒项）
- 事实基线（registry 实测）：`dist-tags.latest = 0.12.0` · `version = 0.12.0` ·
  tarball `https://registry.npmjs.org/@nathan33/nao-skill/-/nao-skill-0.12.0.tgz` ·
  `dist.shasum = 21117209dd079b2c94ddf83a5af19f56504d49ba` ·
  `dist.integrity = sha512-O/SUHZxAGMYDyd5iPBolZDS30gxq0kedNn1KI2bwbh0rNFVJxS5h9oRDeXev/Kr8IdE3J5/Ui5YlV3NRuzYM2A==` ·
  registry 元数据 `pi.skills` = 2 条按文件声明，无 `pi.prompts`
- 环境：node v24.20.0 · npm 11.19.0 · pi 1.1.0 · Linux（全部在临时项目/临时目录执行，**未改本仓源码**）

---

## 段 1 — 真实安装核验（临时项目）

流程：`pi install -l --approve npm:@nathan33/nao-skill@0.12.0` → 用**已发布包内 bin** `init` → shim `check` → 真 pi 注册核验。

| 断言 | 结果 | 证据 |
| :-- | :-- | :-- |
| 真实安装成功 | ✅ | `pi install` exit 0 · `Installed npm:@nathan33/nao-skill@0.12.0` |
| 落盘路径 | ✅ | `<proj>/.pi/npm/node_modules/@nathan33/nao-skill`（`package.json` version=`0.12.0`） |
| settings pin | ✅ | `.pi/settings.json` → `"npm:@nathan33/nao-skill@0.12.0"` |
| `init`（发布包内 bin） | ✅ | exit 0；项目足迹仅 `.agents/{scripts/nao-fleet.sh, .nao-version}` |
| shim `check` | ✅ | `check: OK · roles=6 · files=43 · layout=main-row2`，**exit 0** |
| 注册 skill 数 | ✅ | nao 包贡献 **2**：`nao-fleet`、`frontend-design`（location 均在 `.pi/npm/node_modules/@nathan33/nao-skill/.agents/skills/**`） |
| collision 诊断 | ✅ | stdout/stderr 均 **0**（`"type":"collision"` 0；`name "x" collision` 0） |
| 项目内 `.agents/skills` 注册 | ✅ | **0**（项目 `.agents/` 仅 shim，无 skill） |

> 说明：真 pi 会话内共注册 30 条 skill（含用户级 `~/.agents/skills/arkcli-*` 等 27 条 + nao 包 2 条 + 插件 1 条）；本核验按 nao 包路径过滤，nao 贡献恰为 2，且无 collision。

## 段 2 — 发布物内容核验（已发布 tarball）

命令：`npm pack @nathan33/nao-skill@0.12.0`（拉下**已发布 tarball**）→ 解包核对。

- 文件数：**48**；tarball 大小 **109 211 B**；`sha256 = 8c6b530a6e7113bbcee8d6800a22136be176357cdc6febd32a139296306e92fe`

| 核验项 | 要求 | 结果 |
| :-- | :-- | :-- |
| `.agents/skills/nao-fleet/SKILL.md` | 含 | ✅ 含 |
| `bin/shim/nao-fleet.sh` | 含 | ✅ 含 |
| `.agents/roles.yaml` | 含 | ✅ 含 |
| `.agents/checklists/` | 含 | ✅ 含（8 文件） |
| `.agents/templates/` | 含 | ✅ 含（6 文件） |
| `tests/` | 不含 | ✅ 不含（`^(tests|docs)/` 零命中） |
| `docs/` | 不含 | ✅ 不含 |
| README / LICENSE / package.json | （files 白名单内，允许） | ✅ 含 |

含 `README.md`、`LICENSE`、`package.json`（`files` 白名单指定），符合预期。

### 与「tag `v0.12.0` 本地 `npm pack`」对比

- tag `v0.12.0` → commit `197dd6e`（squash 合并提交）。
- 本地：`npm pack --ignore-scripts`（detached worktree @ `v0.12.0`）。
- 对比结论：
  - 文件清单 **完全一致**（48 = 48，`diff` 无差异）
  - 逐文件内容 **完全一致**（`diff -r` 无差异）
  - tarball 大小一致（109 211 B），**sha256 完全一致**（`8c6b530a6e7113bbcee8d6800a22136be176357cdc6febd32a139296306e92fe`）

> registry 元数据 `gitHead = f971bc8`（发布时检出点）与 tag 指向的 `197dd6e` 不同，但**发布物内容与 tag 逐字节一致**，属发布流程记录点差异，非缺陷。

---

## 结论

- 段 1、段 2 全部断言通过，**未发现缺陷**：已发布 `0.12.0` 安装可用、注册恰 2 个 skill 无 collision、`check` exit 0；
  发布物内容符合 `files` 白名单（含 shim/SKILL/roles/checklists/templates，不含 tests/docs），且与 tag `v0.12.0` 逐字节一致。
- 观察到但非缺陷项：① 发布元数据 `gitHead` 与 tag 提交点不同（内容一致）；② 用户级 `.agents/skills` 会随环境带入额外注册（与 nao 无关，已按包路径过滤）。
- 本核验**不覆盖**：下游 4 仓消费行为（AC5，T3 范畴）、`0.12.0` 之后的回归（需新批次）。

## 环境与命令留痕

- 全部命令可复现：`pi install -l --approve npm:@nathan33/nao-skill@0.12.0`；`node <pkg>/bin/nao-skill.js init`；
  `bash .agents/scripts/nao-fleet.sh check`；`pi --mode json --approve --no-session --no-mcp -p ok`；
  `npm pack @nathan33/nao-skill@0.12.0`；`git worktree add --detach <dir> v0.12.0 && npm pack --ignore-scripts`。
- 临时产物在 `/tmp/t4-post.*`、`/tmp/t4-pub.*`、`/tmp/t4-local.*`；已移除 tag worktree。本仓源码未改动。
