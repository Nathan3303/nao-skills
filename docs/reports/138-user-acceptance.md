# 用户验收单：多仓并行（`--fleet` · #138）

- 版本 0.25.0 · 前置 `pi ≥1.4.0` + herdr（默认；回退 `export NAO_TERMINAL=tmux`）+ `herdr integration install pi` · 每条自己跑，结果填「回填」栏（`✓/✗` + 一行现象）。

1. **两仓各起一支队（零配置）**：`cd ~/proj/api && .agents/scripts/nao-fleet.sh ensure pm rd-be qa`；`cd ~/proj/web && … ensure pm rd-fe qa`
   期望：两套**同时在场**，名字 `pm@api`/`qa@api` 与 `pm@web`/`qa@web`；`herdr workspace list` 有 label=`api`、`web` 两个 workspace；`herdr pane list` 里 api 队 pane 的 `cwd` = 你 `cd` 的那个 `api` 仓（不是别的目录），web 队同理。
   回填：____

2. **看全（`status`）**：任意目录 `nao-fleet.sh status`
   期望：一张表列清两支队伍；行尾有 `·fleet=api` / `·fleet=web`，常驻行显示 `--name pm@api` 全名。
   回填：____

3. **只回收本仓那一支**：`cd ~/proj/api && nao-fleet.sh close qa`
   期望：「已回收 qa@api（herdr pane …）」；`web` 的 `qa@web` 不受影响。
   回填：____

4. **跨仓回收**：`nao-fleet.sh close pm@web`（带 `@<fleet>` 的全名，在哪跑都行）
   期望：定位到 `web` 那一支并回收；定位不到 ⇒ 非 0 + 诊断（不假装已回收）。
   回填：____

5. **旧会话并存，别起第二个 PM**：升级前已有裸名 `pm`（`status` 里无 `·fleet=`）时，在**同仓** `ensure pm`
   期望：「已在运行（legacy 裸名 pm ≡ pm@<本仓 slug>）…跳过」，**pane 数不变**。
   回填：____

6. **回收那个旧会话**：同仓 `close pm`
   期望：「close 命中同仓 legacy 裸名 pm」+「已回收…」；**不会**打印「未运行（无需回收）」。
   回填：____

7. **改名分家 / 撞名保护**：`ensure --fleet alpha pm` ⇒ 新会话 `pm@alpha` + workspace `alpha`（与 `pm@api` 是两个）；两仓算出同一 fleet 时，第二仓 `ensure` 同 core ⇒ **报错并列在场会话**（不静默顶掉），照提示换 `--fleet`。
   回填：____

8. **名长两态 / 旧写法**：仓目录名过长（默认 slug）⇒ 自动截短 + 恰一行提示；显式 `--fleet`（≤16）装不下 ⇒ 报错并说该缩哪一段。`ensure --scope alpha pm` ⇒ 等同 `--fleet alpha` + 恰一条「已弃用」提示（`--help` 以 `--fleet` 为主）。
   回填：____

## 本轮已修（0.25.0）

- pane 的工作目录 = 你 `cd` 的那个仓（此前会落 herdr server 的目录，导致 pi 问「Trust project folder?」、同仓重复 `ensure` 报「同 core 但 fleet/仓不同」）；第 1 步的 `cwd` 判据就是验这一条。

## 验收结论（PM 填）
- [ ] 第 1–8 步全部 ✓ 或已归口
