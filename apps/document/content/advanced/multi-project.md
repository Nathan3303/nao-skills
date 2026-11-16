---
title: 多项目布局
---

# 多项目布局

一个仓一套机制。三个仓就是三套，各自 `pi install --local`、各自 `.pi/settings.json`、各自一份 `AGENTS.md`。

## 为什么要各装一份

机制是**项目级**的：`.pi/settings.json` 的版本 pin 进仓库，团队 clone 下来就是同款；项目约定写在项目根，AI 每次会话都会读。装在全局会变成「谁先装谁生效」，供不了团队。

## 两个仓同时跑：必须设 scope

会话名形如 `<角色>[-<任务>][@<仓>]`。区分仓库靠末尾那段 scope：

```bash
cd ~/proj/api && printf 'api\n' > .agents/fleet-scope
cd ~/proj/web && printf 'web\n' > .agents/fleet-scope
```

于是会话名变成 `rd-be@api` / `rd-be@web`，互不干扰。

**不设 scope 会怎样**：第二个仓 `ensure` 同一角色时**直接报错并列出冲突的会话**，而不是悄悄顶掉第一个。这是故意的——同名会话会互相覆盖，静默成功等于给你一个「看起来有两个、其实只有一个」的舰队。

- scope 语法：小写字母数字开头，可含 `-` `_`，≤16 字符。
- 一次性指定：`ensure --scope api`（覆盖文件）。
- `status` 不读文件，它从会话名解析——带 scope 的会话会显示 `·scope=api`。
- `close rd-be` 用你当前所在仓的 scope；`close rd-be@api` 用全名。

## 跨仓并行

- 布局上，herdr 是「1 workspace / 仓 + 1 tab / 角色」；放置键取 scope（没设就取仓名），所以两个仓的窗格不会混在一起。
- 派生会话用 `--task <编号>` 隔离，并行两个任务时不要共用同一个常驻会话。
- 需要从 A 仓回收 B 仓的残留会话也可以：`status` 会给出可执行命令，定位不到时非 0 退出并打印诊断，不假装成功。

## 升级：谁先升，谁要跟

机制以 npm 包为准。某个仓升了版本、别的仓没升，是常态——**不要用「我这边是好的」来判断别人**。每个仓的 `.pi/settings.json` 决定它自己用哪版。

上游发新版时会提示你（只提示，不自动升）。要不要升、什么时候升，你定；升完 `pi update --extensions` 并**重开会话**——角色卡是启动时注入的，旧会话仍是旧卡。
