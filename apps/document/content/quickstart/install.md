---
title: 装机制
---

# 装机制

机制（角色卡、清单、技能、协议）**装进 npm 包，不铺进你的仓库**。你的项目里只多三个入口。

## 两条命令

```bash
cd 你的项目
pi install --local npm:@nathan33/nao-skill   # 声明 pin，并把机制包物化到项目内 .pi/npm
npx @nathan33/nao-skill init                 # 写转发入口 + 生成 AGENTS.md
```

- 第一条只做「声明依赖 + 下载」。它把版本写进 `.pi/settings.json`——**这个文件进仓库**，团队 clone 下来就是同款机制。
- 第二条才真正落地：写一个转发脚本、生成项目级约定文件。

想钉版本就写全：`pi install --local npm:@nathan33/nao-skill@0.24.0`；只想跟最新版就省略 `@版本号`。

## 你项目里多了什么

```text
你的项目/
├── AGENTS.md                      # 项目级约定（PM 维护，AI 每次会话都会读）
├── .pi/settings.json               # 机制包的 pin 版本（进仓库）
├── .pi/npm/                        # pi 自己物化的包（pi 自建 gitignore，不提交）
└── .agents/scripts/nao-fleet.sh    # 转发入口：自动定位包内机制并转发
```

三个入口，没有第四个。角色卡、清单、技能、协议正文全在依赖包里——**升级机制不会在你仓库里留下 diff**。

## 已有 AGENTS.md 会怎样

**合并追加，不覆盖。** 你原来写的东西一字不动，只在末尾补机制需要的项目级约定段。装完建议扫一眼，把你自己的口头约束补进去（比如「发布前必须经我确认」）。

## 升级与卸载

- **升级**：改 `.pi/settings.json` 里的版本号 → `pi update --extensions`。
- **卸载**：从 `.pi/settings.json` 去掉这一条 → 删掉 `.agents/scripts/nao-fleet.sh` → `AGENTS.md` 里机制段落自行删除（不清也无害，只是没人用）。
- 两者都不需要碰你的源码。

下一步：[拉队开工](/quickstart/fleet)。
