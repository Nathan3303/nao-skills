# T537 AC1② 补证：真 `pi` 会话的终端标题

- 状态：已完成 · 2026-11-01（发布日实测）· Owner：PM
- 背景：T537 的 AC1② 要求「`ensure --card` 拉起的会话，终端标题命中 `π - <role> - <cwd basename>`」。QA 复核时该条以**替代证据**放行（7 份提示文件 md5 全同 + 卡前缀逐字节），真标题未观测。本条为发布日补证，履行「到期 = v0.21.0 发布日由 PM 实测」的承诺。

## 条件

- 隔离 tmux server（`env -u TMUX` + `-S /tmp/t537-ac1.sock`），不碰生产会话
- 临时下游项目 `/tmp/t537-ac1`，卡 `./.agents/prompts/review-helper.md`（`role: review-helper`）
- 真 `pi` 进程（非桩），`NAO_SKILLS` 指向机制包根

## 观测

- pane 标题：**`π - review-helper - t537-ac1`** ⇒ 命中契约 `π - <role> - <cwd basename>`
- 进程 argv：`pi --name review-helper --append-system-prompt /tmp/nao-fleet-review-helper-*.md`
- 同场 `status` 输出：`· review-helper（一次性会话 · 下游卡 review-helper）→ close review-helper` ⇒ AC4① 的「本仓卡会话可见 + 可执行回收命令」在真机场景成立

## 清理

`kill-server` 卸载隔离 server → 删 socket → 删夹具目录；`pgrep` 无残留进程；生产 tmux server 未受影响（`list-sessions` 仅原会话）。

## 结论

AC1② **真机成立**（不再依赖替代证据）。后续同类断言仍优先真机实测，替代证据仅作临时放行并在发布日补证。
