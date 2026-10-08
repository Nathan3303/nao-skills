# PRD：`migrate` 收尾（标记 / shim 判定 / lock 去重）+ 0.13.0 · T510

> Issue：[#21](https://github.com/Nathan3303/nao-skills/issues/21) · 批次：T510 · 分支：`feat/21-migrate-cleanup`（base `main`）
> 版本影响：**MINOR `0.12.1 → 0.13.0`**（新增 `--shim`/`--no-shim` CLI 能力 = additive；npm 发布由用户执行，tag/Release 由 PM 出）
> 执行：rd-infra · 验证：qa · 架构：arch-designer（设计评审 + **终签** + 补 ADR）
> 状态：**已开工**（用户 2026-10-08 拍板：范围 = F3/F4/F7 **+ B2**；版本 = 0.13.0；下游 pin 等本批一次升）· 正文为权威（Issue 只放摘要与指针）
> 设计依据：`docs/reports/2026-10-08-T510-arch-review.md`（arch 只读评审，含判定式、实测 E1–E5、AC 草稿）

## 0. 背景

`0.12.0` 的单 SKILL 化（#18 / PR #20）交付后，架构评审提出 6 项改进；F1/F2/F5 已随批修掉，**F3/F4/F7 另立 #21**（不并入 #18 以免 scope 蔓延）。本批同时纳入评审中新实测发现的 **B2**（同类静默失败缺陷）。

三项主项 + 一项并入项的共同特征：**都是「静默不做事」或「状态冗余」类缺陷** —— 迁移工具做了错误的默认动作（minimal 被装 shim）、写了无人读的标记（`.nao-migrated`）、或在特定格式下悄悄跳过关键步骤（单行 lock 去重、无 legacy 资产时的 lock 去重）。

## 1. 问题证据

| 证据 | 数据（arch 实测，2026-10-08） |
| :--- | :--- |
| **F3 死状态 + 已发散** | `MIGRATED_FILE` 仅 1 处写（`bin/nao-skill.js:462`）、**全仓无读取**；三仓 `.nao-migrated` 与 `.nao-version` 同为 `0.12.0`；把 nao-todo-server / nue-ui 复制到 `/tmp` 用 CLI 0.12.1 再跑 `migrate` → 只有 `.nao-version` 变为 0.12.1，**`.nao-migrated` 仍 0.12.0** ⇒ 两标记必然发散 |
| **F4 违反自身裁定** | `migrate()` / `init()` 均**无条件** `installShim()`；`nao-todo-minimal` 实测 `detectLegacyAssets = ['.agents/prompts/']`、无 `.agents/scripts/`、全仓 `nao-fleet` 引用 **0** ⇒ 若迁移会凭空写入 shim，违反 PRD §13「零 shim」裁定 |
| **F7 静默跳过（格式相关）** | 单行压缩 lock 夹具：`migrate` **无任何 lock 告警**、文件逐字节不变、`frontend-design` 仍在；根因 `removeJsonProperty` 的行首守卫（`lineStart` 行的 `trim().startsWith('"key"')`）在单行 JSON 下必然失败 ⇒ `stripLockDuplicate` 静默 `return false` |
| **B2 静默跳过（路径相关）** | 夹具：单行 lock（含 `frontend-design`）+ **无** legacy 资产 → `migrate` 输出「未发现旧版全套 .agents/…；按 init 处理。」⇒ **`stripLockDuplicate` 根本不执行**（`migrate()` 在 `!legacy.length` 时提前 `return init()`） |
| 格式差异实证 | nue-ui lock = 4 空格缩进、nao-todo-server = 2 空格 ⇒ **任何结构化重写都会整文件重排**（故 F7 必须走文本级/属性级删除） |
| 判定式实测 | 三仓 `needsShim = true`（已有 shim + docs 引用 12/4/5 处）⇒ 重复 migrate 零变化；minimal `needsShim = false`（A/A′/B 全假） |

## 2. 目标指标

| 指标 | 现状 | 目标 |
| :--- | :--- | :--- |
| 迁移标记 | 写两个同源标记且必然发散 | **单一事实来源**：只留 `.nao-version`；`.nao-migrated` 写入点删除 |
| shim 安装 | 无条件（违反 §13 minimal 裁定） | **按判定式** `needsShim = A ∨ A′ ∨ B`；`--shim`/`--no-shim` 可覆盖；跳过时**显式告知** |
| lock 去重 | 单行压缩 / 无 legacy 资产两条路径静默跳过 | **任一 JSON 形态都能去重**；确实无法安全删除时 **warn + 不改写**（不静默） |
| CLI 能力 | 无 shim 相关开关 | `--shim` / `--no-shim`（互斥 → `exit 2`）· `--help` 说明判定式 |
| 版本 | 0.12.1 | **0.13.0**（MINOR） |

## 3. 范围 / 非范围

| IN | OUT |
| :--- | :--- |
| `bin/nao-skill.js`：F3 删写入点 · F4 `detectShimNeed()` + migrate 分支 + 参数 · F7 `removeJsonProperty` 属性级回退 + 三态返回 · **B2 把去重移到早退之前** | ❌ **B1 修复**（legacy 目录名判定过宽）—— 本批仅写入 PRD「已知边界」，修不修另议 |
| 文档同步（B4 四处）：README「老项目迁移」+「下游仓库迁移（minimal 段）」· `SKILL.md §3` · `nao-skill --help` · `.agents/templates/AGENTS.md.example:39` | ❌ 下游三仓 pin 升级（另立批次 T511，等本批发布后一次升到 0.13.0，并顺手删 `.agents/.nao-migrated`） |
| `tests/t4/`：minimal 型夹具用例 · 开关用例 · 单行 lock 用例 · B2 用例 · 失败告警用例 | ❌ 角色语义 / 闸门语义 / `.agents/skills/**` 内容 · `.nao-obsolete/` 存量清理（B7 仅记录） |
| `package.json` → `0.13.0` + `docs/releases/v0.13.0.md` + **ADR**（arch 补写，见 §9） | ❌ 历史归档文档改写（BR3） |

## 4. 用户场景

| # | 场景 | 期望 |
| :--- | :--- | :--- |
| S1 | 纯文档仓（minimal 型）迁移 | 不再凭空出现 shim；输出一行「判定为纯文档迁移，未写 shim（可用 `--shim` 强制）」 |
| S2 | 已接入仓重复迁移 | shim 与其它文件零变化（幂等）；`.nao-migrated` 不再出现 |
| S3 | 项目明确要接入但当前零引用 | `migrate --shim` 强制装（显式逃生口） |
| S4 | lock 被格式化工具压成单行 | 去重照常生效，且**除该条目外其余字节不变** |
| S5 | 迁移时既有 `.nao-migrated`（旧版遗留） | exit 0、不读写该文件、不阻塞；文档标注「已废弃、可安全删除」 |

## 5. 业务规则

- **BR1** 机制单一事实来源：版本只由 `.nao-version`（已安装包版本）表达；迁移状态由「是否仍有旧资产」推断
- **BR2** minimal / 零引用仓**不得**被写入 shim（PRD §13 裁定的机器化落实）
- **BR3** 历史归档文档不改；只改现行指针与运行时状态
- **BR4** 迁移提示每版本最多一次 —— 达成方式改为「旧资产已删 ⇒ `detectLegacyAssets()` 空 ⇒ 无提示」（不再依赖标记）
- **BR5** 文本级改写纪律：**除目标条目外其余字节不变**（`JSON.stringify` 式整文件重排被禁止）
- **BR6** 迁移类步骤**不得静默跳过**：能安全做则做，不能则 `warn` + 不改写

## 6. NFRs

| # | 要求 |
| :--- | :--- |
| NFR1 | `npm test`（`check` + `tsc -p tsconfig.agents.json`）exit 0；`tests/t4/run.sh` 全绿（断言数 **≥ 136**，只增不减） |
| NFR2 | **判定式可复现**：纯文件树输入 + 固定 IGNORE + 固定 token 正则；无网络/时间/环境依赖；**必须排除 `.pi/**`**（否则已物化仓恒为 true，F4 空转） |
| NFR3 | 三仓已迁移仓**零回归**：重复 `migrate` 后 shim 内容与 mtime 不变、`git status --porcelain` 为空（版本一致时） |
| NFR4 | 全仓扫描性能：单仓 < 2s（跳过 >1MiB 与二进制文件） |
| NFR5 | 互斥开关冲突 `exit 2` + 可读错误；跳过 shim 时输出**显式告知**（不静默） |

## 7. AC

> 采用 arch 评审 §三 的 AC 草稿（PM 已按拍板结果编号并入；`AC-F7-4` 为 B2）

| AC | 类型 | 内容 |
| :--- | :--- | :--- |
| **AC-F3-1** | 主路径 | Given 旧版全套 `.agents/` 夹具，When `migrate`，Then 迁移完成后 `.agents/.nao-migrated` **不存在**，且代码中无其写入点 |
| **AC-F3-2** | 幂等/BR4 | Given 上述夹具已迁移，When 再次 `migrate`，Then 输出不含迁移提示（保持 test05 断言），且 CLI 版本一致时 `git status --porcelain` 为空 |
| **AC-F3-3** | 兼容 | Given 带既有 `.agents/.nao-migrated`（值 ≠ 当前版本）的夹具，When `migrate`/`init`，Then exit 0、不读写该文件、不阻塞；README/ADR 有「已废弃」说明 |
| **AC-F4-1** | 主路径 | Given minimal 型夹具（`.agents/prompts/**` 存在 · 无 `.agents/scripts/nao-fleet.sh` · 排除 IGNORE 与待移除资产后全仓 `nao-fleet\|nao-skill\|NAO_SKILLS` 命中 0），When `migrate`，Then **不创建** `.agents/scripts/nao-fleet.sh`，且输出含一行「判定为纯文档迁移，未写 shim（可用 `--shim` 强制）」 |
| **AC-F4-2** | 不误伤回归 | Given 已迁移仓夹具（shim 已就位 + docs 有 `nao-fleet` 引用），When `migrate`（版本一致），Then shim 内容与 mtime 不变、`git status --porcelain` 为空 |
| **AC-F4-3** | 开关覆盖 | Given 任一夹具：`migrate --no-shim` ⇒ 不写 shim；minimal 型夹具 `migrate --shim` ⇒ 写入；同时给 `--shim --no-shim` ⇒ `exit 2` + 可读错误 |
| **AC-F4-4** | init 边界 | Given 干净项目，When `init` ⇒ 默认写 shim；`init --no-shim` ⇒ 不写并打印 warn；`init --force` 遇旧版转 migrate 时仍装 shim |
| **AC-F7-1** | 单行去重 | Given 单行压缩 `skills-lock.json`（含 `skills["frontend-design"]` 与其它条目），When `migrate`，Then 仍合法 JSON、`frontend-design` 命中 0、**除被删 token + 一个逗号外其余字节不变** |
| **AC-F7-2** | 格式保持 | Given 4 空格与 2 空格两种多行 lock（各含 `frontend-design`），When `migrate`，Then 与「逐行去掉该条目块」的期望结果 `diff` 为空（沿用并扩展 test08） |
| **AC-F7-3** | 失败不静默 | Given 无法安全文本删除的 lock 形态（删除后 JSON 非法），When `migrate`，Then 文件字节不变 + **恰一行 `warn`**（含「手工移除」），其余迁移步骤完成、exit 0 |
| **AC-F7-4** | **B2 并入** | Given **无 legacy 资产**但 `skills-lock.json` 含 `frontend-design` 的夹具，When `migrate`，Then 去重**照常生效**（命中 0）且输出说明走的是 init/去重路径 |
| **AC-DOC** | 设计一致性 | B4 四处文档与实际行为一致：README（老项目迁移 + minimal 段）· `SKILL.md §3` · `--help`（判定式与开关）· `.agents/templates/AGENTS.md.example:39`（补「无脚本/无引用的纯文档仓除外」）；`.nao-version` 语义（B3）有一句话定义 |
| **AC-REL** | 发布件 | `package.json` = `0.13.0`；`docs/releases/v0.13.0.md` 用户可读（改了什么 / 影响谁 / 如何升级 / 回滚）且与版本号一致 |
| **AC-GOV** | 治理 | PR 标题用户可读 · `main` 合并后本批**恰好 1 条**提交、无 `wip()` · 工作区干净 · **arch 终签**（GO）已记录在 PR |
| **AC-SCOPE** | 非范围守护 | diff 审查确认未碰 `.agents/skills/**` · 角色/闸门语义 · 历史归档文档 · **未修 B1**（仅文档「已知边界」） |

## 8. 待验证项（实施第一步）

| # | 待验证 | 影响 |
| :--- | :--- | :--- |
| V1 | minimal 型夹具来源：直接快照 `nao-todo-minimal`（6 文件，无远端）是否可直接进 `tests/t4`（体积/可维护性） | 决定 AC-F4-1 夹具形态 |
| V2 | `init --force` 转 `migrate()` 的「显式接入」意图如何传递（现有 `force` 参数是否够用） | 决定 AC-F4-4 实现 |
| V3 | CRLF 形态 lock 在现有行级路径下会残留空行（arch 风险②）——本批是否顺带处理 | 决定是否加 AC 或文档标注 |
| V4 | 三仓真实快照回归（AC-F4-2 / AC-F3-3）用哪一仓（建议 nao-todo-server 最简） | 决定 T4 用例的「真实仓」夹具 |
| V5 | `--dry-run` 未纳入本批（B1 另议）——是否需要在 `--help` 里显式标注「无 dry-run」 | 文档口径 |

### 8.1 已知边界（arch 终签记录 · 2026-10-08）

| # | 边界 | 说明 |
| :--- | :--- | :--- |
| D1 | 测试落点与 ADR 初稿不同 | ADR 影响面原写「扩展 case 05/08」，实际为**新增 `tests/t4/cases/10-migrate-shim-lock.sh`**（更优：隔离新行为）——ADR 描述已同步 |
| D2 | lock 输入 JSON 非法时返回 `absent` | 沿用既有行为（不归 `failed`、不告警）；仅影响「输入本身已损坏」场景，去重失败仍不写坏文件 |
| D3 | 属性级回退会连带删除「值 → 分隔逗号」之间空白 | 形如 `"k":{…} ,` 的非常规排版；常规 JSON 无影响（「其余字节不变」纪律对标准形态成立） |
| D4 | B2 使「无 legacy 资产」仓去重时也创建 `.agents/.nao-obsolete/<stamp>/` 备份目录 | 仅备份（下游 `.gitignore` 已忽略），无 live 影响 |
| D5 | 判定式扫描跳过 symlink | 仅当引用只经 symlink 可见时为假阴性；`--shim` 可覆盖 |
| D6 | `failWarn` 文案对「唯一 key 但末位不可安全裁剪」措辞不够精确 | QA 观察项，**本批不改**（改动会触及 bin 代码、需重走终签）；留待后续批次 |

## 9. 上线闭环 / 变更治理

| 项 | 内容 |
| :--- | :--- |
| 闭环 | Issue #21 转实施单 → **arch 补 ADR**（`docs/adr/2026-10-08-migrate-shim-and-marker.md`，含备选模式对照 + 终签）→ 分支 `feat/21-migrate-cleanup` + Draft PR → qa 用例先行 → rd-infra 实施 → qa 复跑 + PR 评论 → **arch 终签（GO）** → PM 验收 → RD squash 合并 → PM 出 tag `v0.13.0` + Release → 用户 npm publish → 发布后核验 |
| Reviewer | **arch-designer**（终签；本单改 `migrate` 语义 + 新增 CLI 能力 ⇒ 非纯缺陷修复） |
| 发布 | **MINOR 0.13.0**；tag 必须指向 `main` 合并提交；`gh release create v0.13.0 --notes-file docs/releases/v0.13.0.md` |
| 回滚 | `git revert <squash 提交>`；下游按 pin 回退 |
| 后续 | **T511**：三仓 pin 一次升到 0.13.0 + 顺手删 `.agents/.nao-migrated`（用户已批「等本批一次升」）· B1 修复另议 · B6/B7 仅记录 |

## 10. 优先级

| 环节 | 结论 |
| --- | --- |
| 战略筛子 | 通过（**迁移工具语义正确性 + 消除静默失败**；B2 为同类真缺陷） |
| MoSCoW | Must：F4（违反自身裁定）+ F7/B2（静默失败）+ F3（死状态/发散）；Should：文档同步、ADR；Won't：B1、下游 pin、`--dry-run` |
| RICE | R=4 仓（本仓 + 三下游）· I=2 · C=0.8（判定式与 AC 已由 arch 定稿、实现局部）· E=中 → 高 |
| Kano | Must-be（工具语义错误 = 缺失项） |

## 11. 验收结论（2026-10-08 · 上游 PM）

| 项 | 结果 |
| :--- | :--- |
| AC-F3/F4/F7 系列 + AC-F7-4(B2) | **全部通过** |
| T510-QA（用例先行） | 基线 `--baseline` **34/34 全绿**（缺陷全在场）· 四条可证伪断言（A1–A4）已建档 |
| T510-RD | F3 写入点归零 · F4 判定式（`.pi/**` 硬排除 + >1MiB/NUL + legacyAssetPaths 排除）· F7 属性级回退 + 三态告警 · **B2 去重提前** · 门禁 `check` 0（roles=6）· `npm test` 0 · t4 **10 用例/179 断言/0 红**（基线 136）· 三仓 `check` 0 · 真仓 `/tmp` 副本 re-migrate 零变化（shim md5+mtime 不变、未读写 `.nao-migrated`） |
| T510-QA2（独立验证） | **64/64 PASS rc0**（含 `.pi/**` 硬排除专项 + F7 末位属性不可裁剪形态）· 四条断言整体翻面 · 门禁连跑两次一致 · 三仓回归通过 |
| **arch 终签** | **GO**（签署 v0.13.0 @ `d1ff9d0`）—— 决策 1–6 与判定式 8/8 逐项核验一致，无 ≥ 中严重度偏差 |
| PM 独立复核 | 自核 `detectShimNeed`（6 项排除齐全）· decision **在备份/移除前采样** · `stripLockDuplicate` **确在早退之前** · `MIGRATED_FILE` 全仓 0 · 非范围命中仅 `SKILL.md §3` 文档段 · 历史归档 0 改动 · notes 用户可读 |
| 缺陷 | **0**（6 项已知边界见 §8.1，均为记录级） |
| 遗留（转 T511 / 后续） | 三仓 pin 一次升 0.13.0 + 删 `.agents/.nao-migrated` · B1 修复另议 · D6 文案留待后续批次 |
