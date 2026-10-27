# 是否需要新增 CodeReview 角色（舰队机制评估）

- 状态：已定稿（决策待落地）· 更新：2026-10-14 · Owner：PM
- 指针：`.agents/roles.yaml` · `.agents/prompts/architecture-designer.md` · `.agents/skills/github-flow.md` · `.agents/common/intercom-protocol.md` · 待建 PRD

## 结论摘要

- **缺口成立**：实现质量（命名 / 重复 / 错误处理 / 边界 / 安全细节 / 死代码 / 隐式耦合）当前**无第二签收人**，落到 RD 自审。
- **不新增常驻第 7 角色**：常驻成本与「单点串行审签」瓶颈大于收益，且 review 频次尖峰、不适合常驻。
- **采用最小改动包 A+B+C**：RD 只读 reviewer 子代理自审 + Reviewer 默认改同栈互审并纳入实现质量 + 记逃逸指标。
- **升级判据**：连续 2 批出现「合并后才抓获的实现级缺陷」→ 升级；升级形态优先**按需角色**（用完即回收），不是常驻。

## 一、现状：谁审什么（证据）

- **`arch-designer`**：默认 PR Reviewer，但范围**明确排除实现细节**——`architecture-designer.md:104`「评审范围限于架构与契约一致性；实现细节与门禁数字归 RD/QA」。
- **PR Reviewer 可为空**：`github-flow.md:49`「纯 CRUD 可写『无』并注明理由」⇒ 大批需求实际无人工 review。
- **`qa` 不管代码质量**：`test-engineer.md:23` 只允许改测试代码；产出是用例 / 缺陷 / 门禁精确数字（`test-engineer.md` §五）。
- **PM 不深审实现**：`product-manager.md:63` 验收 = 核对回执门禁数字 + 读变更文件核对 AC，「不可改码」。
- **结论**：链路上唯一看实现的人是作者本人。这不是理论风险——现有机制里没有任何条款把「实现质量」指给某个角色。

## 二、为何仍不建议做常驻角色

- **机制维护成本**：新角色 = 角色卡 + checklist + skill + `roles.yaml` 条目 + `check` 校验（卡片 frontmatter 一致性 / 行数阈值）+ `intercom-protocol` / README / `pm-routing` / `github-flow` 四处交叉引用 + `tests/t4` 回归用例。
- **调度成本**：每需求多一跳同步等待；PM 闸门链变长（派发 → 实现 → review → 验收）。
- **单点瓶颈**：一个 `cr` 会话串行审 rd-fe / rd-be / rd-infra 全部 PR；review 工作量分布极不均（CRUD 需求零痛点，重构/安全相关需求峰值高），常驻会话大部分时间空转。
- **替代通道已存在但未被用**：`intercom-protocol.md:42` 已授权角色在自身 turn 内起只读 `reviewer` 子代理——零会话增量。

## 三、推荐最小改动包（A+B+C，零新增会话）

- **A. RD 侧自审**：RD 卡在提交前用只读 `reviewer` 子代理扫本次 diff（`worktree:false`、不改码），结论写入回执 `done(full)` 的风险段。改写或关闭提交由 RD 自行决定，不越权。
- **B. Reviewer 归属**：`github-flow.md` 的「纯 CRUD 可写无」改为「**同栈 RD 交叉互审**（rd-fe ↔ rd-be / rd-infra）」；Reviewer 范围加一条「实现质量」，`arch-designer` 保持只兜契约 / 分层 / 影响面（不动其边界）。
- **C. 指标留痕**：`docs/tasks-state.md` 每批记两个数字——合并后抓获的实现级缺陷数、PM 验收打回原因分布（实现质量占比）。
- **AC 草案**：三处文本改动可 grep 验证；`check` + `npm test` rc=0；A+B 在两批真实需求上跑通且回执格式未破。

## 四、升级路径（若 C 触发）

- **形态**：`roles.yaml` 增 `reviewer` 条目 + 角色卡，**非常驻**——PM 仅在有待审 PR 的需求上 `ensure reviewer`，验收通过后 `close --task <编号>`。
- **理由**：review 是短时、可并行、频次不均的工作，契合现有「派生会话验收即回收」纪律；不承担常驻上下文占用。
- **前置**：先补角色卡版本纪律（bump `version` + `updated`）+ `check` 校验 + t4 用例，与新增任何角色同标准。

## 五、未决 / 风险

- **A 的效果未实测**：只读 reviewer 子代理对小型 diff 的实际命中率未知；若连续两批零发现，需判定是「质量够好」还是「扫描无效」——届时用一次人工注入缺陷（负控）验证。
- **B 的互审质量依赖 token 预算**：跨卡互审会拉长 RD turn；若显著拖慢交付，退化为「仅 review 涉及 >N 文件或跨包 diff」。
- **不建议**用「arch 扩范围」替代：会与其既有边界冲突并加剧 arch 单点。

## 六、待办（下一批次立项）

- 立项后建 Issue / 降级批次分支，范围 = A+B+C 的文本改动 + 指标栏位；Reviewer 建议 `arch-designer`（仅校验与既有边界不冲突）。
- 发布：PATCH（文档与流程口径变更，无脚本语义变更）。

## 来源

- 仓库内证据（上列行号）；外部实践未检索——本判断基于本项目机制现状，不引用竞品做法。
- 访问日期：2026-10-14

- 修订：2026-10-14 首版（PM 基于 T527 批次间隙的机制评估，用户选定 A+B+C 路径）
