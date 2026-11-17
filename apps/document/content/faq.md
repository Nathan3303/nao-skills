---
title: 常见问题
---

# 常见问题

前五条与首页同一口径，后面是装完以后才会问到的。

## 装之前

<details>
<summary>会改我的代码库吗？</summary>

只会新增项目根 `AGENTS.md`、`.pi/settings.json`，以及一个转发入口 `.agents/scripts/nao-fleet.sh`。角色卡、清单、技能这些机制文件都在依赖包里，不铺进你的仓库，也不碰你原有文件（已有 `AGENTS.md` 时是合并追加，不覆盖）。
</details>

<details>
<summary>除了 pi，能配别的编程 Agent 吗？</summary>

不能。nao 的多会话派活、回执、回收整套机制都建立在 pi 之上，只支持 pi，不为其他编程 Agent 做适配，也不承诺可互换。
</details>

<details>
<summary>它会在 GitHub 上开 PR 吗？</summary>

会。每个需求一条分支、一个 PR（草案早开、CI 早跑），你确认验收后由研发角色 squash 合并，main 上只留 1 条可读提交。没有远端或 `gh` 时降级为本地分支，流程不变。
</details>

<details>
<summary>跑完的会话要留着吗？</summary>

派生会话验收完就回收，常驻角色留着复用。`.agents/scripts/nao-fleet.sh status` 会提示哪些是残留，目标在别的项目里也能回收。
</details>

<details>
<summary>为什么需要终端后端？</summary>

舰队要把 7 个角色会话放进终端里，还要能可靠地找回与收掉。默认 herdr：每个角色一个 tab，身份靠结构化事实判定；tmux 是回退方案，在当前窗口分屏，SSH 下同样可用。
</details>

## 装完之后

<details>
<summary>能换别的模型吗？</summary>

能。舰队不绑模型，但长链路交接（派活 → 回执 → 验收）对模型的纪律遵守很敏感，换模型后如果回执质量下降、闸门被跳过，多半是模型的问题不是机制的问题。项目里可以在拉起时用 `ensure -m <模型>` 指定。
</details>

<details>
<summary>它会自己上网吗？</summary>

会，但分工明确：PM 查同类功能的**产品形态**，架构师对照**业界成熟方案**。抓来的内容要落成文件（`docs/research/`），不能只留在聊天里；技术选型仍只由架构师定。
</details>

<details>
<summary>没有 GitHub 也能用吗？</summary>

能跑，但要降级：分支、PR、发版改成手动或本地操作，流程顺序不变。代价是「一条提交对应一个需求」这种可回滚性需要你自己维护。
</details>

<details>
<summary>会话聊久了会不会丢事？</summary>

不会。状态落在文件里：需求文档在 `docs/prds/`，任务状态与接续快照在 `docs/tasks-state.md`，验收报告在 `docs/reports/`。重开会话后 PM 先读台账再干活。
</details>

<details>
<summary>成本大概什么量级？</summary>

取决于需求和模型。可预期的部分：一次常规需求约 4–6 个角色参与，每个角色跑几轮；纯咨询类（不写码）消耗很低。想压成本，先只装 PM + 一个研发角色。
</details>

<details>
<summary>我不想要某个角色怎么办？</summary>

删掉对应文件即可（或干脆不 `ensure` 它）。只留 PM + 一个研发角色也能跑，只是设计与测试这两道闸门要你自己补。
</details>

<details>
<summary>怎么卸载？</summary>

从 `.pi/settings.json` 去掉这一条 → 删 `.agents/scripts/nao-fleet.sh` → 自行清理 `AGENTS.md` 里的机制段（不清也无害）。源码一行不动。
</details>

还有不认识的名词：[术语表](/glossary)。
