# #88 `cases/06` 期望收单处与负控自包含 —— QA 非作者复核

- 分支：`fix/88-case06-decouple` · 复核基线 HEAD `9ff9b41`（`git diff main...HEAD` = 4 文件 +139 −69）
- Draft PR [#89](https://github.com/Nathan3303/nao-skills/pull/89) · Issue [#88](https://github.com/Nathan3303/nao-skills/issues/88)
- 结论：**GO（0 P1 / 0 P2 / 3 P3）** —— 另附一条**与本批无关的既有 flake**（`cases/19`），见 §五。
- 方法：所有变异由 QA 在 `/tmp` 独立工作树里自造（不改分支工作区），跑完即删。

## 一、AC4 防自洽空转（最重要）— 通过

**期望来源审计**（`grep` 全量看 `cases/06`）：期望值只来自 `tests/t4/expected-roles.txt`（`expect_tsv` / `EXPECT_N` / `EXPECT_HINT` / `build_selfcontained`），真 `.agents/roles.yaml` 只作为**被检对象**解析（`manifest_tsv` 读取后与期望比对），**没有任何「以真清单推导期望」的路径**。用例内唯一的「再造期望」是 AC4 自己的负控：`sed 's/^rd-infra\t/rd-infraX\t/' "$EXPECT" > "$WRONG"` —— 从**期望文件**派生，方向正确。

**独立变异（改真期望文件，不是只在用例内）**：把 `tests/t4/expected-roles.txt` 的 `rd-infra` 改成 `rd-infraX` ⇒ `cases/06` rc=1，主断言给出**双向点名**：

```
角色集不一致：清单 7 个 / 期望 7 个 · 清单多出: rd-infra · 清单缺少: rd-infraX
—— 新增/删除角色或改别名/卡名请更新 tests/t4/expected-roles.txt
```

⇒ 不是拿真清单自证，闸没被拆。附带的第二红见 P3-1。

## 二、AC1/AC2 恰 1 条红 — 通过

- **新增第 8 角色**（`newrole.md` 卡 + `roles.yaml` 条目，期望文件不动）：rc=1，**恰 1 条断言红**（主断言），文案 `角色集不一致：清单 8 个 / 期望 7 个 · 清单多出: newrole —— …请更新 tests/t4/expected-roles.txt`；`check roles=` 断言按设计**自跳过**并打 `-- 存在清单漂移 ⇒ 跳过 check roles= 断言（避免同源重复红）`。
- **删除一个角色**（删 `qa` 条目、卡仍在）：rc=1，**恰 1 条红**，文案 `清单缺少: qa` + 指路。
- **两条历史误导红已消失**：`grep '复位后断言复绿\|check 只降到 warn=1' cases/06` = **0 处**；复位语义改为**与变异前快照比对**（`t4_assert_eq "$SNAP" "$r"`）。

## 三、AC3 五态真阳性（独立在真树上各造一次）— 通过

| 态 | 红数 | 精确点名（实际文案节选） |
| :-- | :-- | :-- |
| 摘条目（uiux-designer） | 1 | `清单缺少: uiux-designer` |
| 加未登记卡（probe-role.md） | 1 | `probe-role.md：卡存在但 roles.yaml 未登记（孤儿卡）` |
| 删别名（uiux-designer → `[uiux]`） | 3 | `uiux-designer：别名 [uiux] 与期望 [uiux,uiux-designer…] 不一致` + `check` 自身 rc=1 两条 |
| 卡文件缺失（test-engineer.md） | 3 | `qa：卡文件不存在（test-engineer.md）` + `check` 两条 |
| frontmatter role 不一致（`qa-mutated`） | 4 | `qa：卡 frontmatter role=qa-mutated 与清单 id 不一致` + `check` 两条 + 自包含基线一条（P3-1） |

后三态的 `check` 两条红**不是级联噪声**：`check` 本身对别名/卡缺失/frontmatter 冲突就报 mechanism error（rc=1），用例同时报告两件真事。

## 四、断言作用域（纪律③）— 大体做到；两处偏松（P3，不阻断）

做到的部分：主断言用**空问题列表精确相等**（`t4_assert_eq "" "$real_problems"`），`manifest_problems` 每条问题一行、带角色 id 与字段；负控复位用**快照比对**；五态里 4 条的 `want` 串都具体到「角色 + 字段 + 值」。

偏松的两处（建议下批各 1 行）：
1. `t4_assert_contains "$out" "roles=$EXPECT_N"` —— 作用域是**整段 `check` 输出**（应取汇总行）。语义上风险低（`check` 只在汇总行打 `roles=`），但按纪律③应写明作用域。
2. `neg_state "摘条目" "qa"` —— `want` 只是一个角色 id，**任何含 qa 的问题行都能满足**。旁边有 `p != ""` 与快照复位兜着，所以不会把「摘条目」的错诊断放行成绿，但这条「精确点名」的声明比判据强（与 #86 P3-1 同型）。
⇒ 因主断言为精确相等、且负控有快照兜底，实际假绿面很窄，我判 **P3 而非 P2**；若 PM 要严格按纪律③，改这 2 处即可。

## 五、遗留裁决：`expected-roles.txt` 与 `roles.yaml` 双写 — **同意**

- 若由 `roles.yaml` 生成期望 ⇒ 拿真清单自证，AC4 直接失效（本批存在的唯一理由就是防这个）。
- 由**卡集**生成期望也不行：别名只存在于 `roles.yaml`，卡集给不出 `aliases`，且「卡在、清单未登记」正是要抓的漂移（#82 A）。
- 第三种做法「从**某个 git 快照**的 roles.yaml 派生期望」：本质仍是双写（要么钉 sha、要么钉内容），但可读性更差、要读历史、跨 `--depth=1` 检出即失效 ⇒ **没有收益**。
- ⇒ 双写是这套闸的**必要摩擦**（新增/删除/改名角色必须动两处），接受含到期 2027-05-05。**附加条件**：那条红必须永远可执行地指路（我已验：新增/删除两态都是一条红 + `请更新 tests/t4/expected-roles.txt`）。

## 六、缺陷与观察

**P3-1 · 期望文件写错会带出 1 条级联红**：自包含夹具会 `cp` 真卡内容，期望里角色名写错时（如 `rd-infraX`），夹具内该卡的 frontmatter role 仍是真值 ⇒ `A 负控: 自包含夹具基线一致` 也红。主断言已精确双向点名，级联红文案也可执行，故不阻断；可选收敛：夹具合成卡时**按期望重写 frontmatter role**（或对「期望写错」这条场景不再比基线）。

**P3-2 · 「正常新增角色」的文案含 2 行、其中 1 行冗余**：`清单多出: newrole` 与 `newrole.md：卡存在但 roles.yaml 未登记（孤儿卡）` 是同一事实的两面（同属**一条**断言，故红数仍为 1）。建议孤儿卡检查跳过「已判为清单多出」的角色。

**P3-3 · 两处断言作用域偏松**：见 §四。

**环境观察（与本批无关，但会咬发布闸）· `cases/19` 间歇性失败**：本轮首次 `npm test` rc=1（981 断言 / 2 红，全部落在 `M 还原后（原脚本）复绿`）与首次 `dual` 组 1 rc=1（同型）。**在 `main`（`0c3ed87`）同条件复现**（2 次里 1 次红，子断言同样是 AC1/AC2/AC3 的 `status` 行不匹配）⇒ 非本批引入。随后 `--case 19` 连跑 **5/5 绿**，重跑 `npm test` 与 `dual` 均绿。两次失败都发生在单轮耗时明显变长时（3m55 / 7m24，正常 2m25 / 5m20）⇒ 与机器负载相关的时序 flake（疑似 roster/tsx 或 tmux 采样时序）。建议记 O-1 类并单独立项排查（与 #86 的 `cases/02` 不同源：那个是 LLM 超时，已有重试吸收）。

## 七、门禁（QA 自跑 · 串行 · 跑前 `ps`）

- `check` rc=0 ×2 · `check: OK · roles=7 · files=54 · layout=main-row2` · 两次输出逐字一致（新增 `tests/t4/expected-roles.txt` 不计入 `files`，与 PM 自证一致）。
- `npm test` rc=0 · 用例 **25** · 断言 **983** · `SKIP=0 · DEGRADE=0` · `NOTE=3`（白名单 `06:static-contract` ×2 + `07:pin-fallback`，后者因 `package.json` 0.22.3 领先 registry 0.22.2）· `[FAIL]` 0。
- `npm run test:t4:full:dual`（第 2 次）rc=0 · 组 1 / 组 2 各 **983 断言 / 25 例 / `SKIP=0`**、白名单 NOTE=3、非白名单 NOTE=0、`[FAIL]` 0。（第 1 次因 §六 `cases/19` flake 组 1 rc=1。）
- 变更面：`.agents/scripts`、`bin`、`package.json`、`.agents/roles.yaml`、`.agents/prompts` 在 `main...HEAD` **0 行**改动；零敏感值；分支工作区 0 项。

## 八、结论

**GO（0 P1 / 0 P2 / 3 P3）**。P3-1/P3-2 可随下批顺手；P3-3 若要严格落纪律③建议本批末补 2 行（不影响判定正确性）。`cases/19` flake 与本批无关，但**建议在发布前置里把「组 1 偶发红 ⇒ 单跑定性再重跑」写进流程**（本批已两次用到）。
