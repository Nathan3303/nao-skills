# PRD 索引

> 交付闭环后归档的 PRD 索引。正文权威在 `docs/prds/*.md`（离线可用、会话重开读本地）；Issue 只放摘要与指针。
> 写作与归档规则见 `.agents/skills/pm-operations.md` §五。

| 日期 | 主题 | Issue | 版本 | 状态 |
| :--- | :--- | :--- | :--- | :--- |
| 2026-10-08 | [nao-skills 单 SKILL 化 + pi 原生分发](2026-10-08-nao-skills-pi-package.md) | [#18](https://github.com/Nathan3303/nao-skills/issues/18) | v0.12.0 | 已交付（PR #20 合并 `197dd6e` · 已发布 npm + Release） |
| 2026-10-08 | [舰队工具修复批：别名解析 + 守卫 + 跨仓回收](2026-10-08-fleet-alias-close-fix.md) | [#19](https://github.com/Nathan3303/nao-skills/issues/19) | v0.12.1（PATCH） | 已交付（PR #23 合并 `bcac6f0` · tag+Release 已发 · npm 发布待用户） |
| 2026-10-08 | [`migrate` 收尾（标记 / shim 判定 / lock 去重）+ 0.13.0](2026-10-08-migrate-cleanup-0.13.0.md) | [#21](https://github.com/Nathan3303/nao-skills/issues/21) | v0.13.0（MINOR） | 已交付（PR #24 合并 `6eb9b74` · tag+Release 已发 · npm 发布待用户） |
| 2026-10-08 | [下游三仓 pin 升级到 0.13.0 + 清理废弃标记](2026-10-08-downstream-pin-0.13.0.md) | [#25](https://github.com/Nathan3303/nao-skills/issues/25) | 三仓无版本变更 | 已交付（PR [#190](https://github.com/Nathan3303/nao-todo/pull/190)/[#51](https://github.com/Nathan3303/nao-todo-server/pull/51)/[#74](https://github.com/Nathan3303/nue-ui/pull/74) 已合并 · AC6 一项治理偏差已接受并修流程） |
| 2026-10-12 | [非 tmux 宿主的舰队派生（宿主阶梯 + 前台可见 + 句柄模型）](2026-10-12-non-tmux-host-spawn.md) | [#26](https://github.com/Nathan3303/nao-skills/issues/26) | v0.14.0（MINOR） | 已交付（PR [#27](https://github.com/Nathan3303/nao-skills/pull/27) 合并 `cda59b0` · tag `v0.14.0` + Release 已发 · **npm 发布待用户**） |
| 2026-10-13 | [移除 qq-notify 能力（机制包 + 文档全清除）](2026-10-13-remove-qq-notify.md) | [#22](https://github.com/Nathan3303/nao-skills/issues/22) | v0.15.0（MINOR） | 已交付（PR #28 合并 `7c68901` · tag+Release 已发 · npm 发布待用户） |
| 2026-10-13 | [close 会话名精确锚定 + 实验场安全清理入口](2026-10-13-close-anchor-safe-clean.md) | [#29](https://github.com/Nathan3303/nao-skills/issues/29) | v0.16.0（MINOR） | 已交付（PR [#30](https://github.com/Nathan3303/nao-skills/pull/30) 合并 `e86817b` · tag `v0.16.0` + Release 已发 · npm 已发布，用户执行，latest→0.16.0） |
| 2026-10-13 | [视觉测试移交用户侧（用户验收清单）](2026-10-13-user-visual-acceptance.md) | 无（降级分支 `nao/qa-visual-acceptance`） | v0.16.1（PATCH） | 已交付并发布（PR [#32](https://github.com/Nathan3303/nao-skills/pull/32) 合并 `1aecd9d` · 与 `abd8982`（#31）合发 · tag `v0.16.1` + Release 已发（发布提交 `23e567c`）· **npm 发布待用户**） |
| 2026-10-13 | [派生会话 tmux 落点修正：建到宿主窗口（显式目标寻址）](2026-10-13-t517-derived-pane-window.md) | [#33](https://github.com/Nathan3303/nao-skills/issues/33) | v0.16.2（PATCH） | 已交付并发布（PR [#34](https://github.com/Nathan3303/nao-skills/pull/34) 合并 `536d030` · QA 独立验收 **GO** · AC1–AC9 全过 · tag `v0.16.2` + Release 已发（发布提交 `d37dc79`）· npm 已发布（latest→0.16.2 · integrity 与 registry 逐字节一致）） |
