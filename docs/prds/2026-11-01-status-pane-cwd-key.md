# PRD：`status` 的 pane cwd 键口径修复（`pane_cwds` 恒空）

- 状态：待开工确认 · Owner：PM · 更新：2026-11-01
- 编号：**M20261101-status-pane-cwd-key**（维护型）· 版本预期：**v0.21.1（PATCH）**
- 指针：来源 = T537 QA 独立复现的遗留 `T537-O1`（`docs/reports/2026-11-01-T537-qa-verify.md` §缺陷）· 下游结论 `docs/tasks-state.md` 待派发队列
- 优先级：中（P3 · 无数据损坏，但会让用户在名册不可用时看到错误的「归属不可判定」并因此**不敢回收**）· 维护型小批

## TL;DR（≤5 行）

- **做什么**：修 `status` 里 `pane_cwds` 关联数组的**建键口径**（现按 `pane_id` 建键、按**会话名**查询 ⇒ 恒空），让设计中「pane 的 cwd 优先于名册 cwd」这一层真正生效。
- **给谁**：名册不可用（pi-intercom 未装 / 探针与 CLI 均失败 / broker 抖动）时，靠 `status` 判断残留并决定是否回收的 PM 与使用者。
- **成功标准**：名册不可用时，本仓会话按 pane cwd 正确判为「本仓」而不是「归属不可判定」；**名册正常的场景输出逐字不变**。
- **不做什么**：不改三态判定语义与文案、不改 fail-closed、不改归属算法、不新增任何 tmux 调用。

## 一、问题证据

- **静态实证（PM 只读行段）**：
  - `pane_cwd_snapshot()`（`.agents/scripts/nao-fleet.sh:1383`）的 awk 输出字段顺序为 `会话名<TAB>pane_id<TAB>cwd`（`print name "\t" $1 "\t" $3`）。
  - 消费处（`:1661-1664`）`while IFS=$'\t' read -r pn pname pcwd` ⇒ 变量命名与内容错位：`pname` 实际是 **pane_id**，随后 `pane_cwds["$pname"]` 以 **pane_id** 建键。
  - 查询处（`:1696` / `:1707` / `:1734`）一律用 `pane_cwds["$dname"]`（**会话名**）取值 ⇒ **键永远不匹配，恒空**。
  - `session_repo_verdict()`（`:1389` 起）语义是「pane cwds 优先，名册 cwd 仅作兜底」⇒ 「pane cwd 权威」这一层自 T535 引入以来**从未生效**。
- **行为实证（QA 独立复现，2026-11-01）**：无名册时本仓卡会话被判 `? …（归属不可判定）`；名册在位（cwd=本仓）时同一会话判 `· …（一次性会话 · 下游卡 …）`。同一会话两种结论，差别只来自兜底层。
- **危害定性**：`?`（不可判定）在设计上**不给可执行回收命令**（fail-closed）。于是名册一掉，本仓残留会话就变成「看得见、不敢动」，PM 只能人工比对 pane，与「状态外部化 + 回收闭环」纪律相悖。
- **5 Whys**：pane cwd 权威失效 ← 键错了 ← 消费处变量名（`pname`）与字段顺序错位一步、且没人验证过「名册缺失」这一层 ← 该层只在名册正常时被测（名册兜底掩盖了缺陷）← 回归用例缺少「pane-only」场景。

## 二、目标指标

- **北极星**：名册不可用时，`status` 对**本仓**会话的归属判定正确率 = 100%（现状 0%，因为永远走兜底并得出「不可判定」）。
- 预期：`?（归属不可判定）` 从「名册缺失时的默认结果」变为「真正不可判定时才出现」。
- 观测：`pane_cwds` 在 arena 内非空（用例内可断言）；无 roster 夹具下本仓会话判 `local`。

## 三、范围 / 非范围

- **范围**
  1. **A · 键口径修正**：`pane_cwds` 按**会话名**建键（与查询一致）；同一个会话名对应多个 pane 时保留现有「多行拼接」语义（不得只取第一个）。
  2. **B · 用例补位**：`tests/t4/cases/19` 增「pane-only」场景断言（名册不可用 + pane 标题契约命中 + cwd 在本仓 ⇒ `local`；cwd 在他仓 ⇒ `other`）；补一条「pane 与名册冲突 ⇒ pane 优先」断言。
  3. **C · 零回归证明**：名册正常路径的输出与修前**逐字等价**（用 `git show main:` 旧版对照）。
- **非范围**（各带理由）
  - 不改三态判定算法与文案（`session_repo_verdict` 语义不变）：理由 本批只修数据通路，语义已在 T530 定稿并有 ADR。
  - 不改 fail-closed 行为（仍不可判定 ⇒ `?` 且不给命令）：理由 这是 T530 的安全底线。
  - 不改 `card_role_set` / 卡会话识别 / 「角色未识别」节：理由 T537 刚落，回归面不应叠加。
  - 不新增 tmux/node 调用：理由 复用现有 `pane_cwd_snapshot`，本批是纯键口径修复。
  - 不顺手改 `pname/pn` 之外的变量命名风格：理由 无关变量重命名会放大 diff，评审成本无收益。

## 四、用户场景

- **画像 A（PM · 名册抖动时判残留）**：pi-intercom 探针与 CLI 都失败，`status` 仍能按 pane cwd 认出本仓会话并给出回收命令，不必人工比对 pane。
- **画像 B（多仓并行）**：名册缺失时，他仓会话仍正确标 `~（他仓 @ x）`，不会被误判成本仓而误杀。
- **画像 C（正常环境）**：名册在位时输出与今天**一字不差**，无需重新学习读数。
- **关键路径**：`status` → `pane_cwd_snapshot`（pane 标题 + cwd）→ `pane_cwds[<会话名>]` → `session_repo_verdict`（pane 优先）→ 三态显示。
- **页面状态**：不适用（CLI）。

## 五、业务规则

- **BR1 只修数据通路**：`session_repo_verdict` 的判定顺序、三态文案、`task_state_class` 的调用关系一律不动。
- **BR2 fail-closed 不退化**：两路 cwd 都拿不到时仍输出 `?（归属不可判定）` 且**不给**可执行 `close` 命令。
- **BR3 正常路径逐字不变**：名册可用时 `status` 输出与修前逐字等价（允许的唯一差异 = 本批修复所针对的名册缺失场景）。
- **BR4 pane 优先于名册**（现状语义，本批只让它真正生效）：两者冲突时按 pane cwd 判定。
- **BR5 多 pane 同会话名**：同一会话名对应多个 pane（分屏视图）时保持「拼接多行」再判定，不得只取第一个 pane 覆盖。

## 六、NFRs

- **兼容**：不改变任何命令签名与输出格式（只改判定输入的来源）；`close` / `ensure` / `check` 零改动。
- **性能**：零新增外部调用（`pane_cwd_snapshot` 已是单次 `tmux list-panes`）。
- **可核性**：`pane_cwds` 非空 + 三态判定结果 = 全部判据；负控须证明「不修则红」（变异：把键改回 `pane_id` ⇒ 新断言必须 FAIL）。
- **不适用**：安全（不涉及凭证/路径信任边界）· 并发压测。

## 七、AC

- **AC1（主路径 · pane-only 判本仓）**：Given 名册不可用（探针与 CLI 均失败）+ 本仓内一个会话名为 `<role>` 的 pane（标题契约命中）、cwd 在本仓锚内，When `status`，Then 该会话判为**本仓**（`·` 或 `! 残留`，按任务状态），**不得**是 `?`；若会话名带合规任务号后缀，则给出可执行 `close` 命令。
- **AC2（边界 · 他仓不得误判）**：同上前提但 pane cwd 在他仓 ⇒ 仍显示 `~（他仓 @ <base>）`，**整行不含**可执行 `close` 命令。
- **AC3（冲突优先级 · pane 优先）**：名册可用且名册 cwd = 本仓、pane cwd = 他仓（人为构造）⇒ 判定按 **pane**（他仓），证明优先级未反。
- **AC4（负向闭环 · 真不可判定仍 fail-closed）**：两路 cwd 均拿不到 ⇒ `?（归属不可判定）` + **不给**命令（BR2 未被为了修好 AC1 而牺牲）。
- **AC5（设计一致性 · 零回归 + 门禁）**：① 名册正常路径 `status` 输出与 `git show main:.agents/scripts/nao-fleet.sh` 旧版**逐字等价**（允许的唯一差异 = 名册缺失场景）；② 变异负控：把键改回 `pane_id` ⇒ AC1 断言**点名 FAIL**；③ `check` rc=0（roles=6 · files=50）· `npm test` rc=0 · `tests/t4` 全量 + `--case 19` 断言数增加且全 PASS · SKIP=0/DEGRADE=0/非白名单 NOTE=0；④ `git diff --stat .agents/roles.yaml` = 0。

## 八、上线闭环

- **灰度**：不适用（CLI 行为修正，仅在名册缺失场景生效）。
- **监控**：发布后由 PM 在下一批的 `status` 实跑中观察（正常环境应无任何视觉变化）。
- **回滚**：`git revert <squash-sha>`（单条）。
- **发布**：**v0.21.1（PATCH）**；`docs/releases/v0.21.1.md`（用户可见段：一句话 + 「名册抖动时不再把你的会话认成「不可判定」」）；`npm` **重发**（`nao-fleet.sh` 属包内容）。

## 九、变更治理

- **流程**：维护型，**不建 Issue**（分支用降级命名 `nao/status-pane-cwd-key`）；PRD 定稿 → 开工确认卡 → （arch 强度见开工卡）→ 派 `rd-infra` → QA 独立复核 → PM 验收 → RD squash 合并 → 发布 v0.21.1。
- **首提交夹带（BR5 口径）**：T537 的**发布后事实**随本任务 PR 首提交落地 —— ① npm 0.21.0 已核验（`latest` = 0.21.0 · `dist.integrity` = `sha512-ymY6bicO…4cmVSQ==` 与本地 tarball **155,621 B** 逐字节一致）；② `gh release create --target <短 sha>` 报 `tag_name is not a valid tag` ⇒ 实际走 `git tag -a` + `git push origin <tag>` + `--verify-tag` 降级路径；③ 发布日 AC1② 真 pi 标题实测（`π - review-helper - t537-ac1` + `status` 显示「一次性会话 · 下游卡 …」）；④ 台账里的 M 任务编号笔误订正（`M20261018` → `M20261101`）。
- **文件归属**：`nao-fleet.sh` + `tests/t4/cases/19` = rd-infra；PRD/台账/发布说明/验收评论 = PM；QA 报告 = QA 随分支提交。
- **批次边界**：不夹带 `T537-O3`/`O4`（到期 2026-12-31）与下游三仓接入指针（另批）。
