# T1 前置验证报告：pi 原生分发（PRD #18 · V1–V3）

- 状态：待 arch/PM 会签 · 更新：2026-10-08 · Owner：rd-infra
- 指针：PRD `docs/prds/2026-10-08-nao-skills-pi-package.md#8` · Issue `#18` · Draft PR `#20`
- 范围：**只验证不实现**（T2/T3 待 T0 + 本报告双闸门后派发）
- 环境：pi 1.1.0 · node v24.20.0 · npm 11.19.0 · Linux 7.0.0-38-generic

## TL;DR

1. **V1**：`pi install --local` 把包**物理装进项目内** `<proj>/.pi/npm/node_modules/<pkg>/`（项目级 npm root），并写 `.pi/settings.json`；`PI_PACKAGE_DIR` **不是**包定位手段（它是 pi 自身安装目录的 override，session 内不导出）。包内脚本定位用 node resolve 表达式（见 §2）。
2. **V2**：目录含 `SKILL.md` ⇒ 视为 skill root 且**停止递归** ⇒ `references/*.md` **不会**被登记为独立 skill。内聚可行；但不要把文件放到 `.agents/skills/` 下**无 SKILL.md 的子目录**（会被登记）。
3. **V3**：CI 无 pi 会话跑 `check` 的可行方案 = **项目内 `.pi/npm` + 显式 `npm ci` 物化 + shim 本地解析**；npx 转发与全局缓存都不满足 NFR2。**pi 启动会隐式 `npm install`**，离线空缓存直接 exit 1 —— 这条必须在 arch 方案里显式改造。
4. **下游 4 仓**：nao-todo / nao-todo-server / nue-ui 的 `nao-fleet.sh` 与上游 main 逐字节一致，且 CI **未**调用 `check`（0 命中）；nao-todo-minimal 无脚本。迁移期零改动成立。

## 1. 方法与边界

- 验证全程在 `/tmp/t1/**` 临时项目进行；本仓仅新增本报告；下游 4 仓**只读**（验证后 `git status --short` 均 0 条）。
- 全部结论给「结论 / 可复现命令 / 原始证据 / 风险」，命令可照抄（§附录）。
- 定位手段：先读 pi 1.1.0 `docs/` 与 `dist/` 源码，再用真实 pi 启动复核（`--mode json` 导出 system prompt）。

## 2. V1 — 项目级 npm 包落盘路径与解析

- **结论**：`pi install --local npm:@nathan33/nao-skill@0.11.0` 生成：
  - `<proj>/.pi/settings.json`：`{"packages":["npm:@nathan33/nao-skill@0.11.0"]}`（pin 版本）；
  - `<proj>/.pi/npm/`：标准 npm 项目根，内含 `package.json` + `package-lock.json` + `node_modules/@nathan33/nao-skill/`（**项目内物理落盘**）；
  - 与个人级 `~/.pi/agent/npm/` **隔离**（实测全局目录未新增该包）。
- **`PI_PACKAGE_DIR` 判定：不能用于解析包内文件**。源码 `dist/config.js:317 getPackageDir()` 读它作为 **pi 自身包根**的 override（Nix/Guix 用途，`docs/environment-variables.md:83`）；全 bundle 仅「读取」无「赋值」，真实 pi 会话 `env` 无该变量。
- **可照抄的解析表达式**（shim 定位包内脚本，实测 rc=0）：
  ```bash
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  PKG_JSON="$(node -e "try{process.stdout.write(require.resolve('@nathan33/nao-skill/package.json',{paths:['${ROOT}/.pi/npm/node_modules']}))}catch(e){}" 2>/dev/null || true)"
  [ -n "$PKG_JSON" ] || { echo "nao: 未安装 @nathan33/nao-skill，请先 npm ci --prefix .pi/npm" >&2; exit 70; }
  exec bash "$(dirname "$PKG_JSON")/.agents/scripts/nao-fleet.sh" "$@"
  ```
- **原始证据**（节选）：
  ```
  $ pi install --local npm:@nathan33/nao-skill@0.11.0
  added 1 package in 4s
  $ ls .pi/npm/node_modules/@nathan33/nao-skill/.agents/scripts/
  intercom-probe.mts  nao-fleet.sh  qq-notify  ui-tokens-check.sh
  $ env | grep -c '^PI_PACKAGE_DIR='      → 0   （真实 pi 会话内未导出）
  $ bash <shim> check                      → check: OK · roles=6 · files=42 · layout=main-row2  (rc=0)
  ```
- **风险**：
  - pi 生成 `.pi/npm/.gitignore`（`*` + `!.gitignore`）⇒ `package.json`/`package-lock.json`/`node_modules` **默认不进 git**；`node_modules` 缺失时 pi 启动会**隐式** `npm install @nathan33/nao-skill@0.11.0 --prefix .pi/npm --legacy-peer-deps`（实测离线空缓存 → `ENOTCACHED`、**pi exit 1**）。锁文件是否 force-commit 属治理决策，见 §4/§6。
  - 第二次 `pi install --local`（同版本）在未信任项目上因「Project is not trusted」失败；重装/物化需 `--approve`。

## 3. V2 — `references/*.md` 是否登记为独立 skill

- **结论**：**否**。发现规则（`dist/core/package-manager.js:207 collectSkillEntries`）：目录含 `SKILL.md` ⇒ 作为 skill root，**登记后立即 return，不再递归**。故 `skills/<name>/references/*.md`、`checklists/*.md` 均不注册。
- **边界（易踩坑，务必区分 mode）**：
  - **`.agents/skills/**`（mode=agents）**：根目录裸 `.md` 不登记；**无 SKILL.md 的子目录**里的裸 `.md` **会**登记为独立 skill。
  - **包内 `skills/**`（mode=pi）**：仅根目录裸 `.md` 登记，子目录裸 `.md` 不登记。
  - 裸 `.md` 无 frontmatter `description` ⇒ **静默跳过**（无诊断）。
- **原始证据**（真实 pi 启动 `--mode json`，system prompt `<available_skills>` 节选）：
  ```
  nao-fleet  -> /tmp/t1/proj2/.agents/skills/nao-fleet/SKILL.md        （登记）
  unrel-one  -> /tmp/t1/proj2/.agents/skills/unrel/one.md             （无 SKILL.md 子目录，登记）
  checklists-md / bare-ref -> <absent>  （在 nao-fleet/references/ 下，未登记）
  pkg-nao-fleet -> .../testpkg/skills/nao-fleet/SKILL.md              （登记）
  pkg-ref-checklist / pkg-orphan-one -> <absent>                       （包 mode 下均未登记）
  ```
- **对 checklists 内聚的判定**：把 checklists 放在「**含 SKILL.md 的 skill 目录之下**」（如 `nao-fleet/references/checklists/*.md`）即安全；**禁止**放 `.agents/skills/` 下无 SKILL.md 的子目录。PRD 「移出 skills/ 避注册」可放宽为「置于 skill 根之下」。

## 4. V3 — 无 pi 会话的 CI 如何跑 `check`

三方案对比（结论）：
1. **A npx 转发** —— 需要包新增 `exec/check` 子命令（0.11.0 bin 仅 `install`）。离线空缓存 `ENOTCACHED` rc=1；在线可用但每次拉 registry，属**隐式网络** ⇒ 直接违反 NFR2，且引入对 npm registry 的运行时依赖。
2. **B 全局本地缓存**（`~/.pi/agent/npm/...`）—— 实测该目录**不存在** `@nathan33/nao-skill`（`--local` 装的是项目内）；CI 干净 runner 不可用 ⇒ 不可复现。
3. **C 项目内 `.pi/npm` + 显式物化**（推荐）—— pi 已生成标准 `package-lock.json`，CI 执行 `npm ci --prefix .pi/npm` 即可确定重现；之后 shim 本地解析、离线 rc=0。代价：需 `git add -f .pi/npm/package.json .pi/npm/package-lock.json`（被 pi 的 `.gitignore` 忽略）。
- **NFR2 结论**：CI **必须**含一条**显式**物化步骤（`npm ci --prefix .pi/npm`，或 `pi install --local --approve`），**不得**依赖 pi 启动隐式安装；这样网络依赖是「显式声明的一步」，满足「不隐式依赖网络」。
- **原始证据**（节选）：
  ```
  $ npx --offline -y @nathan33/nao-skill@0.11.0 --version   → ENOTCACHED, rc=1     （A 空缓存）
  $ ls ~/.pi/agent/npm/node_modules/@nathan33               → No such file        （B）
  $ npm ci --prefix .pi/npm                                 → added 1 package, rc=0（C）
  $ bash .pi/npm/node_modules/@nathan33/nao-skill/.agents/scripts/nao-fleet.sh check
    → check: OK · roles=6 · files=42 · layout=main-row2, rc=0
  $ pi --approve -p ...（先删 node_modules、空缓存 + offline）
    → npm error code ENOTCACHED ... Error: npm install @nathan33/nao-skill@0.11.0 ... failed with code 1；pi exit=1
  ```
- **下游 4 仓影响面**（只读核查）：
  - nao-todo / nao-todo-server / nue-ui：`nao-fleet.sh` sha `f0967886…` 与上游 main 一致；CI workflow grep `nao-fleet|nao-skill|.agents` **0 命中** ⇒ 今天下游 CI 不跑 `check`，本次改动**不影响**其 CI。
  - nao-todo-minimal：仅 `.agents/{commands,prompts}`，无脚本。
  - 迁移期旧 `.agents/scripts/nao-fleet.sh` 全量副本照跑（零改动成立）；后续若切新 shim，下游需自行加物化步骤（或由 `init` 写入/文档化）。
  - nao-todo、nao-todo-server 已有 `.pi/APPEND_SYSTEM.md`（无 `settings.json`）；nue-ui `.pi/` 空。

## 5. 对 AC1 / AC3 的定型建议

- **AC1（主路径）**：足迹应为 `AGENTS.md` + `.pi/settings.json` + `.pi/npm/`（**含 force-commit 的 package.json/lockfile**）+ `.agents/`(shim)；`check` 通过 shim 本地解析包内脚本，exit=0（本报告已实测）。若 `.pi/npm` 不入库，则「团队 clone 即得、CI 可复现」不成立。
- **AC3（异常）**：建议 shim 解析失败固定 `exit=70` + 可读错误 + 降级指引（本报告已给形态）；pi 未装时走同一路径（不依赖 pi）。pi/npm 不可达时 pi 自身会 exit 1 且打印 npm 错误（实测可读），可接受。
- **推荐**：C 为主；A 仅作需显式联网/预热的可选快捷；B 不采纳。

## 6. 风险与未决（需 arch/PM 拍板）

1. **锁文件治理**：是否接受 `git add -f .pi/npm/package-lock.json`（+ `package.json`）。不接受则 NFR2 无法在无 pi CI 下满足。
2. **pi 启动隐式安装**：`PI_OFFLINE` + 空缓存 + 缺 `node_modules` ⇒ pi exit 1（非降级）。arch 方案需明确「先显式物化、再离线启动」或改为不依赖 pi 自动安装。
3. **版本耦合**：`PI_PACKAGE_DIR` 与 `.pi/npm/.gitignore` 语义随 pi 版本可能变化；shim 不依赖 `PI_PACKAGE_DIR`，且不应假设 `.pi/npm` 布局永久不变（建议解析走 node resolve）。
4. **未决**：包内 skill 路径形态（`.agents/skills` 复用 vs 迁移到 `skills/`）属 T2 设计，需 arch 在 T0 一并定。

## 附录：复现与环境

- 夹具与全部命令见 §2/§3/§4 内联代码块；临时产物在 `/tmp/t1/**`，未入仓。
- V2 复核入口：`pi --mode json --approve -p ok --no-session`，在输出 `system.sections.skills` 中核对 `<name>/<location>`。
- 本仓门禁（改动仅新增本报告）：`bash .agents/scripts/nao-fleet.sh check` → exit=0 · roles=6 · files=42 · layout=main-row2；`npm test` → exit=0（check + tsc 干净）。
- 修订：2026-10-08 首版（V1–V3 结论 + AC1/AC3 建议 + 下游影响面）。
