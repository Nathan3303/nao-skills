# RD 报告：`status` 的 `pane_cwds` 键口径修复（M20261101 · v0.21.1）

- 状态：待 QA 独立复核 · 更新：2026-11-01 · Owner：rd-infra
- 指针：PRD `docs/prds/2026-11-01-status-pane-cwd-key.md`（AC1–AC5 · 附录 D1–D4）· 分支 `nao/status-pane-cwd-key`

## TL;DR

- **做了什么**：把 `status` 里 `pane_cwds` 的建键口径从 **pane_id** 改为 **会话名**（与查询一致），让「pane cwd 优先于名册 cwd」这一层真正生效。
- **结论**：AC1–AC5 全部达成；名册正常路径输出与 `main` 旧版**逐字等价**（真机 md5 相同）；缺陷已由变异负控证明「不修则红」。
- **影响面**：只在「名册不可用 / pane 与名册冲突」时改变判定；`close`/`ensure`/`check`、三态文案与 fail-closed 零改动。
- **待办**：QA 独立复核 → PM 验收 → squash 合并 → 发布 v0.21.1（含 npm 重发）。

## 一、范围 / 不测

- 范围：① 键口径修正（`nao-fleet.sh` 消费处读序与注释）② `tests/t4/cases/19` 补 pane-only / 冲突 / fail-closed 断言 + 键口径变异负控 ③ 零回归证明。
- 不测：真实 pi-intercom 名册协议（本批不碰，夹具全用假探针）· 多仓三仓接入（另批）· T537-O3/O4 遗留。

## 二、改动（2 文件 · +95 −8）

- `.agents/scripts/nao-fleet.sh:1660`：`read -r pn pname pcwd` → `read -r pname pn pcwd`（字段序 = `会话名<TAB>pane_id<TAB>cwd`）；同名多 pane 仍拼接多行后判定（BR5）；变量命名风格未动。
- `.agents/scripts/nao-fleet.sh:1657-1660`：删除「保留 pane_id 键口径」的旧注释，改写为字段序 + 为什么必须按会话名建键。
- `tests/t4/cases/19-status-repo-attribution.sh`：`run_status` 增「agent-dir / 被测脚本」两个可选参数（名册不可用模拟 = 指向无 tsx 目录；旧版对照 = 临时副本路径）；新增 AC1/AC2/AC4（pane-only）、AC5①（旧版逐字对照）、AC3（pane 优先冲突）、AC5②（键口径变异负控）四组。

## 三、环境与命令

- 环境：tmux 3.8 · 夹具走**隔离 socket**（`$LAB/sock`）+ `env -u TMUX` · 名册走假探针 · 夹具根硬断言不在任何 git 仓内。
- 命令：`bash .agents/scripts/nao-fleet.sh check` · `npm test` · `bash tests/t4/run.sh` ×2 · `T4_ALLOW_MISSING=0 T4_REQUIRE_FULL=1 bash tests/t4/run.sh` ×2 · `bash tests/t4/run.sh --case 19` ×2。

## 四、结果（两轮逐字一致）

- `check`：rc=0 · roles=6 · files=50 · layout=main-row2。
- `npm test`：rc=0（check + tsc + t4 全通过）。
- `tests/t4` 全量（`T4_ALLOW_MISSING=0 T4_REQUIRE_FULL=1`）：**20 个用例 · PASS=20 · FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=2（均为白名单 `06:static-contract`，非白名单 NOTE=0）** rc=0；连跑 2 次同结果。
- `--case 19`：断言 **38 → 62**（+24）· FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=0；连跑 2 次断言数一致、rc=0。
- `git diff --stat .agents/roles.yaml` = 空（AC5④）。
- 幂等：`status` 连跑 2 次 rc=0 且输出逐字一致（effect=0）。

## 五、AC 证据

- **AC1（pane-only ⇒ 本仓 + 可执行 close）**：名册不可用（无 tsx ⇒ 探针与 CLI 首步即失败）+ `π - rd-infra-T9001 - …` pane（cwd=本仓锚）⇒ 行走 `· `、tag `! 残留`、行含 `close --task T9001 rd-infra`。断言：`AC1 名册不可用 pane cwd 在本仓 ⇒ 判本仓（不是 ?）` 等 4 条 PASS。
- **AC2（他仓不误判）**：同前提、pane cwd 在他仓 ⇒ `~ （他仓 @ otherrepo19-…）`，整行无 `close --task`。3 条 PASS。
- **AC3（pane 优先）**：名册把 `qa-T9004` 登记在**本仓**、pane cwd 在**他仓** ⇒ 仍判 `~`，且无命令。6 条 PASS（含「名册登记本仓」夹具自证）。
- **AC4（fail-closed 未退化）**：pane 标题不符契约（无 pane cwd）+ 名册不可用 ⇒ 仍 `?（归属不可判定）` 且不给命令。3 条 PASS。
- **AC5①（零回归）**：同一名册夹具下，新版与 `git show main:.agents/scripts/nao-fleet.sh` 旧版 status 输出 md5 相同（断言 PASS）；真机实跑 `diff -u` 为空（两版 md5 均 `2ff03906…`，名册可用场景）。
- **AC5②（变异负控）**：临时副本把读序改回 `read -r pn pname pcwd`（键=pane_id ⇒ 复原缺陷）⇒ 子进程 `RESULT: FAIL`，点名 `AC1 名册不可用 pane cwd 在本仓 ⇒ 判本仓（不是 ?）`（另连带 AC1/AC2/AC3 共 7 条 FAIL）；真仓库脚本 md5 与 `git status` 前后一致，还原后复绿。

## 六、真机实证（本仓 · 只读）

- 名册可用：`bash .agents/scripts/nao-fleet.sh status` 与旧版逐字一致（AC5①/画像 C 无视觉变化）。
- 名册不可用（`PI_CODING_AGENT_DIR=/nonexistent-agent`）：旧版 `? rd-infra-M20261101（归属不可判定）→ 人工核对（勿在本仓回收）`；新版 `· rd-infra-M20261101  ? M20261101 仅散文提及（非表内记录）→ 核对后 close --task M20261101 rd-infra` —— 正是 PRD 北极星（`?` 从「默认结果」变为「真不可判定时才出现」）。

## 七、缺陷 / 未覆盖与风险

- 缺陷：无（未发现新缺陷）。
- 风险（低）：pane 标题契约若被外部改写成同名他仓路径（理论），pane 优先会按 pane 判 —— 这是 PRD BR4 的既定语义，本批只让它生效。
- 未覆盖：真实 pi-intercom 探针输出形态（本批不适用的改动面）· 多 pane 同会话名（BR5）仅在实现层保留拼接语义，未单独构造分屏夹具断言（现有行为逐字沿用，故不计入本批断言）。

## 八、发布建议

- 建议按 D4 发 **v0.21.1（PATCH）**：`docs/releases/v0.21.1.md` 用户段一句话 =「名册抖动时不再把你的会话认成「不可判定」」；`npm` 需重发（`nao-fleet.sh` 属包内容），成功判据用 registry 直连实测（`latest` + `dist.integrity` 与本地 tarball 逐字节一致）。

- 修订：2026-11-01 首版（键口径修复 + 用例补位 + 门禁与变异证据）
