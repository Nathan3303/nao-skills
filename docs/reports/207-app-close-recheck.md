# #207 真机复验（app 后端 `live+done` 回收）

- 状态：已定稿（放行；PM 2026-11-26 据此关闭 #207，`status=idle` 观察转 Issue #240 / T582） · 更新：2026-11-26 · Owner：qa
- 指针：Issue [#207](https://github.com/Nathan3303/nao-skills/issues/207) · 夹具级验证 `docs/reports/573-574-qa-verify.md`「未覆盖与风险」 · 被测 `ff32b6f`（v0.35.0）

## TL;DR

夹具级 AC1/AC2 之后唯一未覆盖项 = **真机 app 后端 `live+done` 回收**，本次补齐并放行。三判据全过：终端消失（`hc ls --all` 命中 0）· 回收后 `ensure` 同角色不撞 `name_taken`（rc=0，拉起 t25）· 回收失败 fail loud（rc=1、零成功行、终端保留）。故障演练用 `hc ls` 错误 payload 走通 D8 分支；另记录 1 条观察（`status=idle` 不在忙闲分支内）。

## 环境

- app 后端形态：`HC_TERMINAL_SOCKET` / `HC_TERMINAL_ID` / `HC_SCOPE` 均在（本会话 = `t22`，`qa`）；`hc 0.1.22`；`NAO_TERMINAL` 未设 ⇒ 每条 fleet 命令显式前置 `NAO_TERMINAL=app`。
- 现场已有真实会话：`pm`(t21, live+done) · `qa`(t22, working) · `arch-designer`(t23, working)。**全部未触碰。**

## 造数（为什么这样造）

`hc run --bg --keep --name <角色> -- pi -ne --no-session -n <角色>` → 发一句「只回复 ok」等它跑完一轮 ⇒ 得到 `state=live · status=done`（`--keep` 保活 = #207 描述的缺陷现场）。再补舰队标签 `nao.name` / `where` / `herdr.space` / `herdr.tab`，让它与真实舰队终端同形（否则 `status` 报「集成缺 labels」，`close` 仍能用但形状不真）。`-ne --no-session` 保证不注册 intercom 会话、不写 session 文件。

- 造数结果：`hc ls --all` → `{"address":"t24","name":"rd-fe","state":"live","status":"done"}`；`status` → `✓ rd-fe 在线（--name rd-fe；卡片 frontend-developer.md）`。

## 判据（effect，不信 rc 与文案）

```bash
NAO_TERMINAL=app bash .agents/scripts/nao-fleet.sh close rd-fe
#   [fleet] 回收「会话已结束、终端保活」（rd-fe ⇒ t24：state=live · status=done）
#   [fleet] 已回收 app 终端：rd-fe（t24）   rc=0
```

- **① 消失**：`hc ls --all --json | …` → `rd-fe 命中条数 = 0`（finished 列表里也没有）。
- **② 不撞名**：`NAO_TERMINAL=app bash .agents/scripts/nao-fleet.sh ensure rd-fe` → rc=0、`已拉起 1 个会话（成功 1 / 跳过 0 / 失败 0）`、新终端 `t25`，无 `name_taken`。
- **③ 失败 fail loud + 保留**：在 herdr-core 下起一个「接受即断」的探针 socket，令 `hc ls` 返回 `{"error":{"kind":"unavailable","message":"lost the core: Connection reset by peer"}}`（rc=0 ⇒ 走 D8 的 payload 判定），再跑同一命令：
  `NAO_TERMINAL=app HC_TERMINAL_SOCKET=/run/user/1000/herdr-core/qa-probe.sock bash .agents/scripts/nao-fleet.sh close rd-be`
  → `回收结果不可判定（hc ls 读不到）：rd-be ⇒ 不报成功；终端可能仍在` + **rc=1**、零成功行；复核 `hc ls --all` → `{"address":"t26","name":"rd-be","state":"live","status":"done"}` **仍在**。
- 前置守卫正样本：`HC_TERMINAL_SOCKET=/tmp/qa207-nonexistent.sock` → `不在 /run/user/1000/herdr-core/ 下（stale/外贸 env ⇒ 拒绝，防串台）` + rc=3（命令未执行，fail loud）。

## 清理

- `close rd-be`（真 socket，live+done 第二个正样本，rc=0）· `close rd-fe`（t25，rc=0）；探针 socket 与进程已删（`/run/user/1000/herdr-core/` 只剩 `default.sock` / `default.holder.*.sock`）。
- 清理后 `hc ls --all`：`t2/t1y/t1z/t20`（历史）· `t21 pm live+done` · `t22 qa live+working` · `t23 arch-designer live+working` —— **我造的 t24/t25/t26 全部不在**。

## 观察（不阻断，转下一批）

- `status=idle` 不在 `_term_app_reclaim` 的忙闲分支里（分支只覆盖 `working|blocked|done|-/空`）⇒ 对「已启动但还没跑过一轮」的会话，`close` 直接杀、不给 `--force` 提示（t25 实测：只打印「已回收 app 终端」）。是否要按 busy 处理由 PM 定，不影响 #207 的三条 AC。
- `t1z`（finished · name=pm）是 app 重启前留下的陈旧终端，不属本次造数，未清理；`ensure` 已对它打「陈旧放置标签 ⇒ 不沿用」提示。

- 修订：2026-11-26 首版（真机 3 正样本 + 1 故障演练）· 2026-11-26 结案：#207 关闭、观察转 #240
