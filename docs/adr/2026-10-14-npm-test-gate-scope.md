<!-- ADR（T522）：骨架遵 .agents/templates/adr.md.example；实施类内容下沉 docs/reports/2026-10-14-T522-arch-review.md -->

# ADR：npm test 门禁范围与严格性

- 状态：已接受（待落地 v0.18.0）
- 更新：2026-10-14
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-10-14-t4-gate-wiring.md` · 评审报告 `docs/reports/2026-10-14-T522-arch-review.md`

## 背景

- 本仓无 CI，`npm test` 是唯一机械门禁；历史上只覆盖 `check` + `tsc`（≈3s）。
- 1874 行 `nao-fleet.sh` 的回归靠 `tests/t4`（12 例 / 263 断言 / ≈2min），历批 AC 只双写「`npm test` rc=0」与「t4 全绿」，无机械执行（T521 备注 N2 实证）。
- 约束：不加 CI；不拆脚本；`tests/` 不入 npm 包；发布路径不得被外部网络/凭据阻塞。

## 决策

`npm test` = `test:agents && test:t4`（默认即全量门禁，t4 默认严格：缺 T2 产物=FAIL）；`prepack` 仅 `test:agents`；新增 `test:t4:full`（`T4_ALLOW_MISSING=0 T4_REQUIRE_FULL=1`，SKIP 计数>0 即 FAIL）作发布前置口径；严格性拆两正交轴（缺产物 / 环境能力）。

## 理由

1. 业务匹配：门禁唯一 ⇒ 默认必须是全量；轻量默认等于无护栏（护栏本体已绿，缺的只是接线）。
2. 成熟度：复用 t4 既有退出码约定（0/1/2/77/78）与 `npm pack --ignore-scripts`，不引入新框架或 CI。
3. 团队能力：形态为 `package.json` 5 行 scripts，6 角色与下游三仓照抄即可；快循环走具名 `test:agents`。
4. 成本：4 个实现文件 + 2 条契约断言；`prepack` 与 `test:agents` 时长不变（≈3s），无新增依赖。

## 对照过的备选模式

1. **维持现状（`test` = check+tsc，t4 靠人工）** —— 适用：有 CI 兜底或套件极廉价；代价：历批双写约定零执行，回归可静默漏过；不采纳：本仓无 CI，唯一门禁必须自证。
2. **`test` 保持轻量 + 新增 `test:all` 全量聚合** —— 适用：本地快循环频繁、门禁另有 CI 承载；代价：全量入口非默认，调用依赖人的记忆；不采纳：与「唯一机械门禁」目标冲突。
3. **`prepack` / `prepublishOnly` 承载全量门禁** —— 适用：发布强一致且网络/凭据恒可用；代价：打包/发布被 2min + pi/tmux/registry 阻塞，离线即无法发布；不采纳：违反「发布路径不劣化」约束。
4. **把 `tests/` 加入 `files`，使消费者也能跑** —— 适用：套件本身即对外能力；代价：把断言实体与真发 LLM/registry 的用例随包分发；不采纳：体积与副作用不可接受。
5. **`test:t4` 容错（缺套件 / 无匹配即退 0）** —— 适用：脚本可能被非源码环境调用；代价：正是「未跑 = 通过」假绿本身；不采纳：与本批封堵目标相反。

## 后果与风险

- 正面：机制脚本缺陷可被默认门禁机械拦截；SKIP/NOTE 显式计数，「绿 + N SKIP」不得称全量通过。
- 负面：本地全量由 ≈3s 升至 ≈2min（默认）——以具名 `test:agents` 作快循环缓解。
- 风险：环境能力缺失时默认门禁仅 SKIP 通过（弱证据）⇒ 以 `test:t4:full` 作发布判据；网络/凭据面已改极性，不得产生 flaky FAIL。

## 限制与已知边界

- `test:t4:full` 判据 = 汇总层 SKIP 计数（含用例输出 `[SKIP]` / `SKIP:` / `SKIP+空格` 行）为 0；NOTE 允许并计数。
- 消费者侧：`tests/` 不入包 ⇒ 安装包内 `npm test` 不适用（rc≠0 属预期）；本 ADR 不覆盖消费方门禁形态。
- 仅约束本仓；下游三仓「照抄」为约定而非继承，是否接受 SKIP 语义由各仓自定。

## 相关指针

- 骨架：`.agents/templates/adr.md.example` · 规范：`.agents/checklists/deliverable-docs.md` §四 · 模式对照法：`.agents/skills/arch-patterns.md`
- 闸门 / 负控 / 清单全文：`docs/reports/2026-10-14-T522-arch-review.md`

## 参考来源

- [Scripts · npm Docs（Life Cycle Scripts）](https://docs.npmjs.com/cli/v12/using-npm/scripts/) · 访问 2026-10-14 · `prepack` 于 `npm pack` / `npm publish` / git 依赖安装前触发，`prepublishOnly` 仅 `npm publish` 触发。
- [config · npm Docs（ignore-scripts）](https://docs.npmjs.com/cli/v10/using-npm/config) · 访问 2026-10-14 · `ignore-scripts` 为真时不运行 package.json 生命周期脚本（`npm test` 等显式命令仍运行，但其 pre/post 不跑）。
