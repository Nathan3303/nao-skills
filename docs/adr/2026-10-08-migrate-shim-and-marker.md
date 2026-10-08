# ADR：migrate 收尾 —— 迁移标记、shim 判定式与 lock 去重

- 状态：**已接受（已落地 v0.13.0 · T510）** · 日期：2026-10-08 · 出具：arch-designer（T510-ARCH / T510-ARCH2，用户已拍板）· 落地：rd-infra（T510）
- 指针：Issue [#21](https://github.com/Nathan3303/nao-skills/issues/21) · 上游 ADR `docs/adr/2026-10-08-nao-skills-single-skill-pi-package.md`（D1–D8）· PRD `docs/prds/2026-10-08-nao-skills-pi-package.md`（§11 决策台账 / §12 闸门 A–D / §13 特例与待办）· 评审报告见 T510-ARCH 回执

## 背景

上游单 SKILL 化（v0.12.0，A′ 方案：机制单源在包内 `.agents/`，项目内仅转发 shim）落地后，`bin/nao-skill.js` 的 `migrate` 路径遗留三项问题，由 #18 的 PR 实现评审提出（F3/F4/F7，F6 仅记录）：

- **F3**：`.agents/.nao-migrated` 只写不读（死状态），而 BR4 要求「每条旧路径提示迁移，每版本最多一次」。
- **F4**：`migrate` 无条件写 shim，与 PRD §13 对 `nao-todo-minimal` 的**零 shim**裁定冲突（该裁定此前纯靠文档约束）。
- **F7**：`stripLockDuplicate` 走文本级删条以保住缩进/其余字节；当 `skills-lock.json` 被压成单行时 `removeJsonProperty` 返回 `null` ⇒ **静默跳过去重**。

另在评审中实测发现相邻缺陷 **B2**：`migrate()` 在 `!legacy.length` 时提前 `return init(...)` ⇒ `stripLockDuplicate` 永不执行；以及**已知边界 B1**：`LEGACY_TOP_DIRS`（`prompts`/`common`/`checklists`/`templates`）按目录名判定 nao 资产，项目自有同名目录会被备份+移除。

## 决策

1. **F3 = 移除 `.nao-migrated`**：删除其写入点（`bin/nao-skill.js` 的 `MIGRATED_FILE` 常量与 `migrate()` 内 1 行写入），**不再读写该标记**。BR4 的达成方式改由「迁移即移除已知 nao 资产 ⇒ `detectLegacyAssets()` 为空 ⇒ 不再产生迁移提示」保证，并在 README/本 ADR 写明。存量文件（三仓 tracked）由 T511 三仓 pin PR **手动删除**；代码不自动删。
2. **F4 = 自动判定 + 显式开关覆盖**：新增 `needsShim = A ∨ A′ ∨ B` 判定式（全文见下）；`migrate` 默认按判定式，`--shim` / `--no-shim` 覆盖（同时给出即 `exit 2`）；`init` 默认装 shim，`init --force` 转 `migrate()` 时传 `forceShim=true`（显式接入意图不被自动判定改写）。跳过 shim 时必须**显式告知**（不静默）。
3. **F7 = 属性级（token 级）删除回退 + 强制校验 + 失败告警**：行级删除失败时，删除「该属性最高层键值 + **一个**分隔逗号」，其余字节/缩进不动；随后强制 `JSON.parse(next)` 成功 ∧ 目标 key 不存在，否则**不改写**并打印一行 `warn`。`stripLockDuplicate` 返回三态（`ok` / `absent` / `failed`）。
4. **B2 并入本批**：把 `stripLockDuplicate` 置于 `migrate()` 的早退判断**之前**（或等价地让 `init` 路径也执行去重），使「无 legacy 资产但 lock 有重复项」的仓库也能完成去重。
5. **版本口径 = MINOR `0.13.0`**（新增 `--shim`/`--no-shim` CLI 能力属 additive）。治理条款「shim 保留 2 个 MINOR（0.12.x / 0.13.x）」不变。
6. **B1 本批不修**，仅写入 PRD「已知边界」并保留在下方「后果与风险」。

## 理由（四步法要点）

- **业务匹配**：三项均为 #21 明确验收项；不改变角色模型、注入方式与闸门语义（BR1/BR2 不受影响），风险面最小。
- **技术成熟**：判定式只依赖确定性文件树 + 固定 IGNORE 列表 + 固定 token 正则（Node 实现，不用 shell `grep`），无网络/时间/环境依赖；`.pi/**` 硬排除使结果与仓库是否已物化无关。
- **团队能力 / 成本**：复用既有 `detectLegacyAssets` / `isShimFile` / `removeJsonProperty` 结构，新增代码量小；F7 回退是 `removeJsonProperty` 的局部扩展，回归面可控（test08 已建立逐字节断言基线）。
- **成本效益**：术语与状态收敛为单一标记（`.nao-version`），消除一处误导性死状态；zero-shim 特例由自动判定兜底，不再依赖人工记忆。

## 对照过的备选模式（含不采纳理由）

### F3 迁移标记

| 模式 | 结论 | 不采纳理由 |
| :--- | :--- | :--- |
| ⓪ 维持现状（只写不读） | 不采纳 | 死状态；且实测已**发散**（见「证据」E1），违反机制单一事实来源纪律 |
| ① 实现读取（`.nao-migrated` = 上次迁移版本，版本不同才打提示） | 不采纳 | ①BR4 所需的「不刷屏」已由资产删除天然达成，读取是第二套冗余判定；②其内容/写入时机与 `.nao-version` 完全同源，本质是第二份版本文件，却因 `init()` 不写而更不可信；③新增分支 + 测试成本换不来任何行为差异 |
| ② **移除写入 + 文档说明** | **采纳** | 单标记（`.nao-version`），零行为回归（`tests/t4/cases/05-migration.sh` 的 BR4 断言保持不变） |

### F4 shim 安装

| 模式 | 结论 | 不采纳理由 |
| :--- | :--- | :--- |
| ⓪ 维持现状（无条件装 shim） | 不采纳 | 与 PRD §13 minimal 零 shim 裁定冲突，特例纯靠文档约束 |
| ① 仅新增 `--no-shim` 开关 | 不采纳为唯一方案 | minimal 特例仍靠人记住加开关，同病未除（保留为覆盖手段） |
| ② 仅自动识别 | 不采纳为唯一方案 | 存在「已决定接入但当前零引用」的假阴性 ⇒ 静默无 shim，且缺显式逃生口 |
| ③ **自动判定 + 开关覆盖** | **采纳** | 默认对四仓实测正确（见「证据」E3），同时保留用户/文档的最终控制权 |

被否的实现细节：显式失败改为 `exit 2`（不适用，本项非「不可运行」场景）· 以 `.pi/settings.json` pin 作为唯一判据（不采纳：只表明已物化，不能替代「有无调用点」）· 用 shell `grep -r` 实现（不采纳：跨平台可复现性差，改 Node 遍历）。

### F7 lock 去重

| 模式 | 结论 | 不采纳理由 |
| :--- | :--- | :--- |
| ⓪ 维持现状（静默跳过） | 不采纳 | 去重永不发生，与 §12-C「nao 包为唯一来源」的长期目标冲突 |
| ① 检测到该形态即告警并保持原样 | 不采纳为唯一方案 | 同上：容忍重复来源长期存在；本 ADR 将其降级为**最后兜底** |
| ② 结构化重写（`JSON.parse` + `JSON.stringify(parsed, null, 2)` 回写） | 不采纳 | 两仓真实缩进不同（nue-ui 4 空格 / nao-todo-server 2 空格）⇒ 整文件重排；违 F1 已确立的「其余字节不变」原则，并打破 test08 的 `keep-me` 逐字节断言；下游 review 噪音大 |
| ③ **属性级回退 + 校验 + 失败告警** | **采纳** | 既完成去重，又只触碰被删属性 token 与一个分隔逗号 |

### B2 相邻缺陷

| 模式 | 结论 | 不采纳理由 |
| :--- | :--- | :--- |
| ⓪ 另立 Issue | 不采纳 | 与 F7 同属 `stripLockDuplicate` 的调用位置问题，同批修改成本更低、回归更聚焦（用户已拍板并入） |
| ① **把 `stripLockDuplicate` 提到早退之前** | **采纳** | 改动小、语义清晰：去重是否执行不应取决于「是否检测到 legacy 资产」 |

## 判定式全文（F4）

前置采样：在备份/移除**之前**计算（`legacyAssetPaths` 依赖待移除清单）。

```
needsShim(t) := A ∨ A′ ∨ B

A  旧版真脚本存在 := exists(.agents/scripts/nao-fleet.sh) ∧ ¬isShimFile(该文件)
A′ 已存在 shim      := exists(.agents/scripts/nao-fleet.sh) ∧  isShimFile(该文件)
B  存在外部调用点  := ∃ 文件 f ∈ walk(t) \ IGNORE，且 f ∉ legacyAssetPaths(t)，
                      且 readText(f) 匹配 /nao-fleet|nao-skill|NAO_SKILLS/

IGNORE            = .git/** · node_modules/** · .pi/** · .agents/.nao-obsolete/**
                    · 二进制（含 NUL 字节）文件 · > 1 MiB 文件
legacyAssetPaths  = .agents/ 下 LEGACY_TOP_DIRS ∪ LEGACY_TOP_FILES
                    ∪ LEGACY_SCRIPT_FILES ∪ LEGACY_SKILL_ENTRIES 的对应绝对路径
isShimFile(p)     = readText(p) 含 'NAO_SHIM_ENTERED'
```

交互语义：

- `migrate` 默认按 `needsShim`；`--shim` 强制装 · `--no-shim` 强制不装；两者同时给出 ⇒ `exit 2` + 可读错误。
- 跳过时输出（不静默）：`未发现 nao 脚本/引用 → 判定为纯文档迁移，未写 shim（需要时用 --shim 强制）`。
- `init` 默认装 shim（新项目 = 明确接入舰队）；`init --no-shim` 跳过并 `warn`；`init --force` 遇旧版转 `migrate()` 时传 `forceShim=true`。

**硬约束**：`.pi/**` 必须排除。否则任何已物化仓库都会经 `.pi/npm/node_modules/@nathan33/nao-skill/.agents/scripts/nao-fleet.sh` 命中 B，判定恒真、F4 空转。

### 反例清单（为何「不误伤」）

| # | 仓库形态 | 判定 | 期望 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| ① | 曾装旧版全套（含真 `nao-fleet.sh`） | A = true ⇒ 装 | 装 | 曾用 fleet，必须保留入口 |
| ② | 新形态仓（已有 shim） | A′ = true ⇒ 装 | 装 | 幂等；内容比对相同则不写文件 |
| ③ | CI 里 `npx @nathan33/nao-skill exec check` | B 命中 `nao-skill` ⇒ 装 | 装 | 保守多装 |
| ④ | 文档/CHANGELOG 提到过 fleet | B 命中 ⇒ 装 | 装 | 保守多装（宁装不省） |
| ⑤ | 仅有项目自有 `.agents/prompts/**`，零引用、无脚本 | 三者皆假 ⇒ **跳过** | 跳过 | 此时无任何 shim 调用点 |
| ⑥ | `nao-todo-minimal`（无脚本、无引用、仅 `.agents/{commands,prompts}`） | **跳过** | 跳过 | PRD §13 零 shim 裁定由自动判定兜底 |
| ⑦ | 已迁移仓（`legacy=[]`，docs 有真实引用） | B 命中 ⇒ 装 | 装 | 重复 `migrate` 零变化（实测） |
| ⑧ | 仓库计划将来接入、当前零引用 | **跳过** + 显式提示 | 跳过（可用 `--shim` 覆盖） | 残余假阴性，已由提示 + 开关缓解 |

## 证据（评审实测，2026-10-08）

- **E1 F3 发散**：`MIGRATED_FILE` 仅 1 处写（`bin/nao-skill.js:462`，`migrate()` 内），全仓无读取；`init()` / `update()` / `install()` 均不写。三仓 `.nao-migrated` 与 `.nao-version` 同为 `0.12.0` 且均 tracked。以 CLI `0.12.1` 对 nao-todo-server / nue-ui 的 `/tmp` 副本重跑 `migrate` → 走 `init` 分支 → `git status` 仅 `.nao-version` 变 0.12.1，**`.nao-migrated` 保持 0.12.0**（同一时刻写的两标记在第二次运行必然失配）。
- **E3 判定式实测**：nao-todo `legacy=[]` / A′=true / B=12 ⇒ true；nao-todo-server `[]` / A′=true / B=4 ⇒ true；nue-ui `[]` / A′=true / B=5 ⇒ true；nao-todo-minimal `['.agents/prompts/']` / A=false / A′=false / B=0 ⇒ **false**。三仓重复 `migrate` 后仅 `.nao-version` 在 CLI 版本不同时更新，shim 内容与 mtime 不变。
- **E4 F7 静默跳过**：合成夹具（legacy 资产 + 单行 `skills-lock.json` 含 `frontend-design`）→ 迁移输出无任何 lock 告警、文件逐字节不变、`frontend-design` 仍在。根因：`removeJsonProperty` 的行级守卫要求该行 `trim().startsWith('"key"')`，单行下 `lineStart=0`、首字符为 `{` ⇒ 返回 `null` ⇒ `stripLockDuplicate` 静默 `return false`。对照：4 空格与「属性独占一行 + 值压缩」形态均正确删条。
- **E5 B2**：合成夹具（单行 lock 含 `frontend-design`，**无** legacy 资产）→ 输出「未发现旧版全套 .agents/ 机制副本；按 init 处理。」⇒ lock 未被去重（仍 1 命中），证明早退分支跳过 `stripLockDuplicate`。

## 影响面

| 面 | 内容 |
| :--- | :--- |
| `bin/nao-skill.js` | 删 `MIGRATED_FILE` 常量与写入（F3）；新增 `detectShimNeed()` + `migrate()` / `init()` 分支 + `--shim`/`--no-shim` 解析与互斥校验（F4）；`removeJsonProperty` 属性级回退 + `stripLockDuplicate` 三态返回与告警（F7）；`stripLockDuplicate` 调用位置上移（B2）；`help()` 文本 |
| 文档 | `README.md`（「老项目迁移」+「下游仓库迁移」两段，含 minimal 表述与判定式）· `.agents/skills/nao-fleet/SKILL.md` §3 · `.agents/templates/AGENTS.md.example` §指针（「项目内 `.agents/` 只有 shim」需补「无脚本/无引用的纯文档仓除外」） |
| 测试 | 新增 `tests/t4/cases/10-migrate-shim-lock.sh` + `run.sh` 注册（断言 136→179） |
| 发布件 | `package.json` → `0.13.0` · `docs/releases/v0.13.0.md` · PR [#24](https://github.com/Nathan3303/nao-skills/pull/24) |
| 下游三仓 | pin 升级 PR（T511）顺手删除 tracked `.agents/.nao-migrated`；`.gitignore` 无需改（该文件为 tracked，不在忽略面） |

## 后果与风险

- **正面**：状态收敛为单一版本标记；zero-shim 特例由自动判定兜底（不再依赖人工记忆）；lock 去重不再受 JSON 排版形态限制；B2 消除「无 legacy 资产 ⇒ 永不去重」的空洞。
- **F3 存量标记**：`.agents/.nao-migrated` **已废弃**——代码不再读写；存量文件可安全删除（三仓 tracked 的由 T511 三仓 pin PR 删除，代码不自动删）。
- **残余风险 / 已知边界**：
  - **B1（本批不修，写入 PRD「已知边界」）**：`LEGACY_TOP_DIRS` 按**目录名**判定 nao 资产 ⇒ 项目自有的 `.agents/prompts` / `.agents/common` / `.agents/checklists` / `.agents/templates` 会被备份+移除（有 `.nao-obsolete/` 备份兜底，但 live 消失）。缓解选项（后续单）：`--dry-run`、内容特征白名单（如 `prompts/` 下须存在 nao 角色卡文件名）。
  - **假阴性**：仓库计划将来接入但当前零引用 ⇒ 跳过 shim；已由显式提示 + `--shim` 缓解。
  - **CRLF**：`removeJsonProperty` 行级路径在 CRLF 下会残留一个空行（合法 JSON，可接受）；实测三仓为 LF。
  - **B6（记录）**：zero-shim 仓调用 `bash .agents/scripts/nao-fleet.sh` 会得到 shell「文件不存在」而非 `exit 2 + DEGRADED:`（NFR3 口径针对「机制包未物化」）；以文档说明处理，不引入假 shim。
  - **B7（记录）**：`.agents/.nao-obsolete/` 备份内含旧 `nao-fleet.sh` / 角色卡 ⇒ 任何「引用扫描」类功能必须排除该路径（判定式已排除）。
  - **`.nao-version` 语义（定稿口径）**：= 已安装机制包版本（pin 对照 / 升级提示；install/init/migrate/update 都写），**不表达迁移状态**；迁移状态可由 `detectLegacyAssets()`（是否仍存旧资产）与 `.agents/.nao-obsolete/`（曾迁移过）推断。
- **治理**：版本 `0.13.0`（MINOR）；「shim 保留 2 个 MINOR（0.12.x / 0.13.x），移除 = 1.0.0」条款不变。

## 参考来源

- 本仓（访问 2026-10-08）：`bin/nao-skill.js`（v0.12.1 工作树：`migrate()` / `migrateLegacy()` / `init()` / `installShim()` / `writeVersion()` / `stripLockDuplicate()` / `removeJsonProperty()`）· `docs/prds/2026-10-08-nao-skills-pi-package.md`（§11 D1–D8 / §12 闸门 A–D / §13）· `docs/adr/2026-10-08-nao-skills-single-skill-pi-package.md` · `tests/t4/cases/05-migration.sh`、`08-fix-regressions.sh` · `README.md`
- 实测对象（本地快照，访问 2026-10-08）：`nao-todo` · `nao-todo-server` · `nue-ui` · `nao-todo-minimal`
- **未检索到**外部来源：本 ADR 的结论仅依赖本仓实现与下游实测；`needsShim` 判定式为自研启发式，无可引用的业界先例。

## 相关指针

- Issue [#21](https://github.com/Nathan3303/nao-skills/issues/21) · 上游 ADR / PRD 见首部指针 · 评审报告见 T510-ARCH 回执（本 ADR 为其结论的正式归档）
- 后续：T511（rd-infra 落地，含 PRD/ADR 随分支首提交）· T510-ARCH3（RD 实现后的终签复核，GO/NO-GO）

- 修订：2026-10-08 首版（用户拍板 F3(b) / F4(c) / F7(c) + B2 并入，MINOR 0.13.0）
