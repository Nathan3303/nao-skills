# #132 backlog sweep · QA 非作者复核

- 结论：**GO**（0 P1 / 0 P2 / 3 P3，均不阻断）· 复核：2026-11-16 · QA
- 范围：E1 台账（PM）证据独立复核 + E2 两条守卫（rd-infra）承重性/防空转复核
- as-of：PM 给 `977914f`；**复核期间分支前进到 `640d8a0`**（`b856547` 报告计数订正 7/10/11、`640d8a0` 台账收尾）。`cases/06` 在 977914f 与 HEAD 的 blob 相同（`e3319da`）⇒ 断言实测对 HEAD 有效；门禁与 `npm test` 在 HEAD 重跑。
- 纪律：只读；全部变异在 `$T4_CACHE_DIR`/`/tmp/qa132` 副本；未 checkout/switch；真仓零触碰。

## 一、门禁抽核（HEAD `640d8a0`）

- `bash .agents/scripts/nao-fleet.sh check` ⇒ rc=0 ×2，`diff` 空；`check: OK · roles=7 · files=54 · layout=main-row2`；`find .agents -type f | wc -l` = 54。
- `npm test` ⇒ rc=0，`[PASS]` **2072** / FAIL 0；34 例（共享 22 / 专有 10 / tmux 专有 2 / PENDING 0，对账 34 = `--list`）；`SKIP=0 · DEGRADE=0 · NOTE=10` 全白名单。
- `cases/06` ⇒ **322 PASS / 0 FAIL**（E2-1 21 + E2-2 16 = 37）；`P2④` md5 断言本轮**真执行**（codegraph 齐备态）且 PASS；真仓 `git stash list` = 0、`worktree list` = 1、`git status` 静默。

## 二、E1 台账（4 个关闭逐条要证据）

- `M20261028-F2` ✅：`du -sh ../nao-todo-server/.codegraph` = **4.0K**，目录内仅 `.gitignore`（229 B）⇒「目录存在无索引」事实成立；下游自管口径同 `T529-D1`（用户 2026-11-02）。
- `T529-D1` ✅：`ls -d ../nao-todo ../nao-todo-server ../nue-ui` 三仓均存在；「无异常上报」属观察项，可接受。
- `M20261115-br5-stash-warn-tension` ✅（**实测**，临时 `git init` 仓 + `NAO_STASH_ROOT`）：新 stash（age 0）+ 默认 6h ⇒ 摘要**无 `warn=`**；`GIT_COMMITTER_DATE` 回填 8h（实测 age 28800s）+ 默认阈值 ⇒ `warn=1` 且 `-v` 命中「最老一条 8 小时前 > 阈值 6 小时（BR5）」。→ 「D1 交付后当天 stash 不再 warn」成立。
- `M20261114-stash-exit` ✅：`check_stash_residue` 存在 + `28b5d44` 加龄（同上实测双向）。
- 移出 3 行可追溯：`herdr-base`（决策轨迹 ⇒ PRD `2026-11-10-herdr-base.md`）· `T545-cache-residue`（关闭证据在 `126-qa-verify.md:66` + Issue #121）· `T543-O2`（= #130 D2，已并 `28b5d44`）⇒ 无证据丢失。
- 计数：三档表 **17 数据行**（`awk` 分节 19 − 表头 2）；「待派发队列」**0 数据行**；`M20261014-F1` 续期依据 `npm view pi-ask-me version` = **0.1.1** ✅。

## 三、E2-1 计数裁定 + fail-closed 判定

- **裁定：下限声明面 = 7 文件 / 10 行 / 11 处**（`intercom-protocol.md:36` 一行 2 处 ⇒ 行≠处）；**完备性面 = 8 文件 / 11 行**（第 8 个是 `codegraph.md:21` as-of 行，不算声明）。RD 现行报告（`b856547`）已订正为 7/10/11 = 与 PM 复算一致、与我独立复算一致；初版「8 文件 / 9 行」两数皆误。扫描面 42 文件（≥40 绊线余量 2）。
- 逐文件实测（我独立 awk，非读报告）：README:28 · AGENTS:18/:33 · intercom:36×2 · SKILL:32 · pm-operations:14 · ARCHITECTURE:45 · INSTALL:12/:22/:34，全部 == 1.4.0。
- **fail-closed 判定：判据组合成立，但承重点不在 gate 本身**：无 git 数据的根（删 `.git`）⇒ `e2_gate` 返回空 = 绿，靠 `≥40` 绊线红；删 `docs/ARCHITECTURE.md` ⇒ gate 仍空，靠「≥11 处（10）+ 逐文件覆盖」红。报告/用例注释「扫描面 fail-closed」应理解为「三条绊线使其 fail-closed」。
- 三类先红后绿（我在副本独立跑，取实测输出）：脚本常量→9.9.9 ⇒ 11 条 `文件:行 声明 1.4.0 ≠ 单源 9.9.9`（含 `README.md:28`、`docs/INSTALL.md:12`）；文档→9.9.9 ⇒ 恰 `README.md:28 声明 9.9.9 ≠ 单源 1.4.0`；摘「截至」⇒ `codegraph.md:21 未归类`。

## 四、E2-2 守卫承重 + 旁证充分性

- 删 `lib.sh` 的 `env -u NAO_STASH_ROOT` ⇒ 恰红 2 条（`E2-2① t4_run_shim 无 warn=` 实际=1、`⑤ 单点①` 期望 1 实际 0）；删 `lib-backend.sh` 的 `-u NAO_STASH_ROOT` ⇒ 恰红其对称 2 条。**各自独立承重** ✅。
- 旁证充分性（我的独立判据）：同一脚本、同一 cwd、唯一 env 差异就是 `-u`；实测翻转链 —— 注入根 + `NAO_STASH_WARN_HOURS=0` **直连** ⇒ `warn=1`；同 env **经 `t4_run_shim`/`be_run_fleet`** ⇒ 无 `warn=`；同 env **`-u` 根、hours=0 直连** ⇒ 无 `warn=`。⇒「warn=0 是被清掉」成立，非「闸门没触发」。**够用**。

## 五、防空转（三条绊线实测必红，副本改 `cases/06` 后跑 `--case 06`）

| 变异 | 结果 |
| :--- | :--- |
| `t4_assert_ge 40` → `400` | FAIL 1：`扫描面非空 …（期望>= 400 实际=42）` |
| `t4_assert_ge 11` → `110` | FAIL 1：`扫描非空转 …（期望>= 110 实际=11）` |
| 覆盖清单 `README.md` → `NOEXIST.md` | FAIL 1：`声明面覆盖 NOEXIST.md（期望=yes 实际=no）` |
| 真删 `README.md:28` 的版本声明 | FAIL 5：`≥11 处（实测 10）` + `覆盖 README.md` + ②③ 变异锚点连带（锚点即 README —— 噪声但全红） |

三条绊线**均真在且真咬**；「8 文件逐个覆盖」实为 7 文件正向 + `codegraph.md` 负向/存在断言（合计覆盖 8 文件面），表述无误读风险。

## 六、P3（均不阻断；附复现）

1. **P3-1 既有（#128，非本批引入）：`cases/06` 对宿主 `NAO_SKILLS` 敏感**。复现：`NAO_SKILLS=$PWD bash tests/t4/run.sh --case 06` ⇒ **319 PASS / 3 FAIL**（`E1 超阈值` 三条，E1 夹具 `check -v` 未覆盖 `NAO_SKILLS` ⇒ 读到真卡）；`env -u NAO_SKILLS` ⇒ 322 PASS。在 `28b5d44` 副本上同样 3 FAIL ⇒ 非本批漂移。影响：按 `AGENTS.md`「`NAO_SKILLS` 必须指向本仓根」复核的人会看到假红。修法：E1 夹具那行加 `-u NAO_SKILLS`（或 `NAO_SKILLS="$E1_LAB"`）。
2. **P3-2 E2-2① 判据过宽**：断言是「输出无 `warn=`」，而非「无 stash warn」⇒ 与全仓其它 warn 耦合。实测（加垫 204 行卡的夹具 + 注入根）：经 helper 输出 `warn=1`（来自卡预算），此时 `E2-2①` 会因无关原因红 —— 与 #126 P2-1「别把 warn 行剥掉」同族的反面色。建议改断言 `grep -c 'git stash'` = 0，或与「直连 - 注入根」的 warn 数做差。
3. **P3-3 E2-1 面/阈值口径**：① `git ls-files` 只含已跟踪文件 ⇒ 新增未跟踪 `.md` 的漂移不被扫（`git add` 后才纳入）；② `≥11 处` 与 42 文件面**贴脸** ⇒ 合法编辑（合并 `intercom:36` 的两处重复声明、删一份现行文档）会红，属 fail-closed 预期但需知；③ 完备性正则 `pi[^0-9@]*x.y.z` 会把 `pi-subagents 0.16.0` / `pi-codegraph 0.1.2` 这类包版本判「未归类」（现仓 0 命中）⇒ 报错文案会误导人加「截至」。建议正则排 `pi-` 前缀或文档写明该形态。

## 七、副作用与收尾

- 真仓：`git status` 空（本报告除外）· stash 0 · worktree 1 · 未 checkout。
- 我本轮失败演练产生的 8 个 `/tmp/nao-t4.*` 已自清；残留 **20 个**（10:53–11:34，本批早前跑次，设计上失败跑保留）建议合并前由 RD 清一次（不计缺陷，T545-cache-residue 口径已含「失败跑按设计保留」）。
