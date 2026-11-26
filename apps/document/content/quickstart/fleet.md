---
title: 拉队开工
---

# 拉队开工

## 三步

```bash
npx @nathan33/nao-skill plugins install-all        # 1. 装协作插件（多会话派活必需）
.agents/scripts/nao-fleet.sh check                 # 2. 体检，返回 0 才能开工
.agents/scripts/nao-fleet.sh ensure pm arch rd-fe rd-be qa rd-infra uiux   # 3. 拉起 7 个会话
```

角色名可以写别名：`arch` 就是 `arch-designer`，`infra` 就是 `rd-infra`。

不想一次全拉，就先 `ensure pm rd-be`——只留 PM 加一个研发角色也能跑。

## 体检怎么看

```
check: OK · roles=7 · files=69                            ← 摘要行：能开工
  ✓ codegraph 齐备                                        ← 可选增强状态
  · 生效后端 NAO_TERMINAL=herdr（形态 TUI …）               ← 你实际在用哪个后端
```

`files=` 的数字随版本变（装的机制文件多少不同），对不上不算装坏；`roles=7` 才是判据。

你的仓还没有代码索引时，那行 `codegraph` 会变成提示行——不影响开工。

看返回码，不看字样：`rc=0` 才算过。有想知道细节的提示行，加 `-v` 展开；失败时它一定会展开，不用你猜。

## 拉起之后

终端里会出现 7 个会话，每个会话的身份就是它的角色（会话名 `pm`、`rd-be`……）。接着在 PM 会话里说需求就行：

```text
你：想加个「导出 CSV」功能
PM：问几个问题 → 给出需求文档和优先级 → 给你一张开工确认卡
你：开工
PM：拉起还缺的角色 → 让 qa 先写用例 → 指派给 rd-be
rd-be：（做完）回执 + PR 链接
PM：逐条核验收标准 → 通过后授权合并 → 归档
```

## 两个词：回执、闸门

- 回执：干完活给 PM 的结论单，固定包含「做了什么 / 门禁数字 / 未过项 / 遗留」。没有回执就是这活没干完，PM 会追讨，不会默认为成功。
- 闸门：某个角色放行之前，必须先拿到一份书面结论。比如设计稿没经你确认，PM 不许派前端开工；PM 没验收通过，研发不许合并。闸门是流程上的把门人，不是自动检查（自动检查叫门禁）。

## 收工

派生的临时会话验收完就回收：`.agents/scripts/nao-fleet.sh close --task T1 rd-be`。常驻角色留着下次复用，`status` 会告诉你哪些是残留。

如果想让脚本读这些状态，`status --json` 给的是结构化结果（在线与否、忙闲三态、所属仓、能不能投递）；给人看的文字输出没有变，加它只是多开一扇门。再看某个角色干过什么，用 [翻会话记录](/quickstart/logs)。

卡住了看：[排错](/quickstart/troubleshoot)。
