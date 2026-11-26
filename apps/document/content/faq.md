---
title: 常见问题
---

# 常见问题

## 装之前

<details>
<summary>会改我的代码库吗？</summary>

只会新增三样东西：项目根的 AGENTS.md、.pi/settings.json，以及一个转发入口脚本。角色卡、清单、技能这些机制文件都在依赖包里，不铺进你的仓库，也不碰你原有文件；仓库里已有 AGENTS.md 时是合并追加，不会覆盖。
</details>

<details>
<summary>除了 pi，能配别的编程 Agent 吗？</summary>

不能。nao 的多会话派活、回执、回收整套机制都建立在 pi 之上，只支持 pi，不为其他编程 Agent 做适配，也不承诺可互换。
</details>

<details>
<summary>它会在 GitHub 上开 PR 吗？</summary>

会。每个需求一条分支、一个合并请求，草案早开、检查早跑。你确认验收后，由研发角色合并，主干上只留 1 条可读提交。没有远端或没装 gh 时降级为本地分支，流程顺序不变。
</details>

<details>
<summary>跑完的会话要留着吗？</summary>

派生会话验收完就回收，常驻角色留着复用。`nao-fleet.sh status` 会提示哪些是残留，目标在别的项目里也能回收。
</details>

<details>
<summary>为什么需要终端后端？</summary>

舰队要把 7 个角色会话放进终端里，还要能可靠地找回与收掉。后端只有 herdr：每个角色一个 tab，身份靠结构化事实判定。旧的 tmux 后端已经删了，不会悄悄换后端。如果你的环境变量或启动脚本里还设着 `NAO_TERMINAL=tmux`，启动时会直接报错并告诉你改哪儿。把它删掉就行；不设这个变量时默认就是 herdr。
</details>

## 装完之后

<details>
<summary>能换别的模型吗？</summary>

能。舰队不绑模型，但长链路交接（派活 → 回执 → 验收）对模型的纪律遵守很敏感。

换模型后如果回执质量下降、闸门被跳过，多半是模型的问题，不是机制的问题。项目里可以在拉起时用 `ensure -m <模型>` 指定。
</details>

<details>
<summary>它会自己上网吗？</summary>

会，但分工明确：PM 查同类功能的产品形态，架构师对照业界成熟方案。

抓来的内容要落成文件（放在 docs/research 里），不能只留在聊天里。技术选型仍只由架构师定。
</details>

<details>
<summary>没有 GitHub 也能用吗？</summary>

能跑，但要降级：分支、合并请求、发版改成手动或本地操作，流程顺序不变。

代价是「一条提交对应一个需求」这种可回滚性要你自己维护。
</details>

<details>
<summary>会话聊久了会不会丢事？</summary>

不会。状态都落在文件里：需求文档在 docs/prds，任务状态与接续快照在 docs/tasks-state.md，验收报告在 docs/reports。

重开会话后 PM 先读台账再干活。
</details>

<details>
<summary>成本大概什么量级？</summary>

取决于需求和模型。可预期的部分：一次常规需求约 4–6 个角色参与，每个角色跑几轮；纯咨询类（不写码）消耗很低。

想压成本，先只装 PM 加一个研发角色。
</details>

<details>
<summary>我不想要某个角色怎么办？</summary>

删掉对应文件即可，或者干脆不 `ensure` 它。

只留 PM 加一个研发角色也能跑，只是设计与测试这两道闸门要你自己补。
</details>

<details>
<summary>怎么卸载？</summary>

1. 打开 .pi/settings.json，把关于 nao 的那一条删掉。
2. 删掉 .agents/scripts/nao-fleet.sh 这个转发脚本。
3. 把 AGENTS.md 里跟 nao 有关的段落清掉（不清也不影响使用）。

源码一行都不会被改。

</details>

还有不认识的名词：[术语表](/glossary)。
