---
title: 装前置
---

# 装前置

装不起来，九成是这一步缺东西。四条硬前提，缺一条舰队就跑不起来。

## 四条前提

- **pi ≥ 1.4.0**：nao 是「7 个 pi 会话」，不是外挂程序。版本低了体检直接报红。
- **终端后端**：7 个角色得落在终端里，还要能可靠地找回来、收得掉。二选一：
  - **herdr ≥ 0.9.1（默认）**：每个角色一个 tab，身份靠 pane 标签和会话状态判定。装完还要 `herdr integration install pi`，否则舰队看不见 pi 会话。
  - **tmux（回退）**：`export NAO_TERMINAL=tmux` 就回到老行为——在当前窗口分屏，SSH 下一样能用。
  - 两个都不能用时**不会自动切换**。静默换后端会让同一条命令在别人机器上跑出另一种结果，所以宁可报错。
- **Node.js ≥ 18**：命令入口是 Node 脚本。
- **git**：每条分支、每个 PR 都要它。建议顺手装 **GitHub CLI `gh`**——没有也能跑，只是开 PR、发版这些步骤降级成手动。

## 只支持 pi

**nao 只支持 pi。** 不为 Claude Code / Codex / Cursor 之类的工具做适配，也不承诺可互换——多会话派活、回执、回收整套机制都建立在 pi 之上。

## 30 秒自检

```bash
pi --version && node -v && git --version && (herdr --version || tmux -V)
```

四条都出版本号就齐了。缺哪个按提示装：pi 见 [pi.dev](https://pi.dev)，herdr 见 [herdr.dev](https://herdr.dev)，tmux 走系统包管理器（`brew install tmux` / `apt install tmux`），Node 用 nvm 或系统包管理器。

## 两个词先说清

- **终端后端**：装角色会话的容器（herdr 或 tmux）。不是「终端模拟器」，是你已经开着的那个终端里的可编程层。
- **门禁**：能自动跑的检查，命令跑完返回 0（`rc=0`）才算过。它不会替你想问题，只负责「不合规就红」。

下一步：[装机制](/quickstart/install)。
