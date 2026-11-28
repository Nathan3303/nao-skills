# 并行开发（worktree · 多任务同时在飞）

> **何时读**：同时有 ≥2 个任务在飞 · 要开第 2 个 worktree · 需要「另一版基线」对照（golden / 旧版行为）· 作为 QA 独立复核别的分支。
> **本文件不复制不变量**：`github-flow.md §工作区纪律` 的 3 条（禁动别人工作区 / 切分支与并行写作必须 worktree / 提交路径级）是**正文唯一处**，此处只讲「怎么并行不出事」。
> **一句话**：worktree 解决「两个任务抢一个 HEAD」，不解决「两个任务抢一个事实源」—— 后者靠命名与冲突热点纪律。

## 一、什么时候真的需要 worktree

| 场景 | 需要？ | 理由 |
|---|---|---|
| 本仓只有我一行会话在写 | **不需要** | 直接在主仓干（`github-flow` 已允许，判据是「我是不是唯一写入者」） |
| 已有一个未提交的任务在手里，又必须切分支 / 起第二个任务 | **需要** | 判例见 `github-flow.md §工作区纪律` 第 2 条（2026-11-26 事故） |
| 要跑「另一版基线」做对照（旧行为 / 别的 PR head） | **需要** | 同一 HEAD 上做不了两版对照 |
| QA 独立复核一个 PR | **需要**（只读，detached） | 复核必须与被测分支同内容、且不污染主仓 |

## 二、命名与建法（一任务一 worktree 一分支）

```
# 干活（新建分支，从最新 main 切）
git fetch origin && git worktree add /tmp/wt-<编号>-<role> -b <branch> origin/main

# 接着一个已存在的远端分支
git worktree add /tmp/wt-<编号>-<role> <branch>

# 只读复核（不建分支）
git worktree add --detach /tmp/wt-qa<编号> origin/<branch>
```

- 路径 `/tmp/wt-<编号>-<role>`；**编号必带**，否则两天后没人知道哪个 worktree 属于谁
- **一个 worktree 只服务一个任务**；同一个 worktree 里换任务是「共用事实源」的伪装形态，`git status` 一片脏时无法归因
- 分支与 worktree 一一对应；`git worktree list` 就是「在飞任务」的机器视图

## 三、worktree 里**缺什么**（本仓实测，别猜）

| 缺的东西 | 后果 | 处置 |
|---|---|---|
| **`.codegraph/`**（gitignore，8.4M，不入库） | 新 worktree **没有索引**，`codegraph_explore` 对该路径不可用 | 定位退回 `grep -rn` + `sed -n '<a>,<b>p'`（**禁 cat 全文**）；要索引就在该 worktree 里重建，别指望继承 |
| `node_modules/` | 本仓**不需要**：`bin/*.js` 零依赖，`devDependencies` 只用于类型检查 | 不用 `npm install`；需要 `tsc` 时才装 |
| 独立的 `docs/` | 每个 worktree 是**副本** ⇒ 台账/索引改动一旦两边都改，合并必冲突 | 见 §四 |

## 四、冲突热点：`docs/tasks-state.md` 与 `docs/README.md`

> 并行 PR 最贵的冲突不是源码，是**这两个高频文件**：每个任务都想写自己那行。

- **规则（硬）**：同一批在飞的多个 PR 中，**只有一个**碰 `docs/tasks-state.md` 与 `docs/README.md`（称「文档承运 PR」，由 PM 指定，通常是本批第一个落地的）
- 其余任务**只写自己 `docs/<编号>-<slug>/` 内**的文件 —— 任务目录互不相交，天然无冲突
- 顺序建议：**文档承运 PR 先合**，其余 PR 再 `git rebase origin/main`（否则台账行会反复冲突）
- 台账/Batches 的事实由 PM 在承运 PR 里写；RD 不代写（避免同一行两个作者）

## 五、长驻服务与端口

- 一个 worktree **一套端口**；`dev server` / 预览 / 截图基线，端口写进回执的 `工作区=` 段
- 同一端口两处监听 ⇒ 后者静默失败（看不清的假绿），这是并行开发最常见的假绿来源
- 用完即停；`/tmp` 里的 worktree 服务常被遗忘

## 六、会话边界（**不要**在 worktree 里再起舰队会话）

- `ensure` 按 **git common-dir** 判定仓身份（`ensure.sh:131`）⇒ 在主仓的 worktree 里 `ensure` 会被判为**同一个仓**，复用同一 workspace ⇒ 同角色两个 tab **撞名/撞 label**
- 正确姿势：**同一个会话里 `cd /tmp/wt-...` 干活**；用 `pwd` 自证当前在哪个树，别靠记忆
- 需要第二个会话（如 QA）时，用**主仓路径**起，进去后 `cd` 到目标 worktree

## 七、收尾（三件事，缺一即残留）

```
git worktree remove /tmp/wt-<编号>-<role>   # 有未提交改动**或未跟踪文件**会拒绝（实测报「包含修改或未跟踪的文件」）⇒ 先想清楚要不要，别用 --force 掩盖
git branch -d <branch>                      # 已合并才可 -d；-D 需说明
git worktree prune                          # 清掉已手动删目录的元数据
```

- **残留判据**：`git worktree list` 里**每一项**都必须对应一个在飞任务或一个待复核 PR；对不上 ⇒ 当场清
- 忘了收尾的典型症状：下次 `git worktree add` 报「路径已存在」或「分支已被检出」
- `/tmp` 会被系统清 ⇒ 目录消失但 worktree 元数据还在 ⇒ 必须 `prune`

## 八、PM 侧：在飞看板与 WIP 上限

- 在飞任务数 = `git worktree list` 非 main 项 + 已 push 待复核分支；**两者必须一致**（有分支没 worktree 说明干活的人没隔离；有 worktree 没分支说明忘了开分支）
- **WIP 上限建议 2–3**：真正的瓶颈是 QA 串行（全量只有它能跑），并行开 5 个只会让 4 个挂在「等复核」
- 每个在飞任务在台账有且只有一行；合并即销行

## 九、反模式（都在本仓实际发生过）

- 在共享工作区 `checkout` 别人的分支（2026-11-26，未提交改动差点被卷走）
- worktree 里 `cat` 全文定位 —— 那里**没有索引**，全文读只是更慢的 grep
- 两个任务共用一个 worktree，最后没人说得清哪几行是谁的
- 端口复用导致截图基线假绿（页面还是上一个任务的）
- 收尾只 `rm -rf` 目录、不 `prune` ⇒ 下次建树报错
- 忘了 worktree 是**副本** `docs/` 也是副本 ⇒ 台账两边各写一版，合并时手改冲突（本机制禁止手改冲突内容）
