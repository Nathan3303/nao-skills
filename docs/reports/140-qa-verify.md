# 报告：#140 / T548 复核（QA 独立验）

- 被测：`fix/140-update-check-ready` @ `45ca40e`（已 push）· 方法：干净 worktree（`npm ci`）+ 真 herdr 0.9.5 + 隔离 tmux socket + 独立变异副本 + 双后端全量门禁
- 采信 PM（未重复）：AC1 的「修前 5.1s 超时 / 修后 2s rc=0 成功 1」因果 A/B —— QA 独立复现同结论（`2216ms · rc=0 · 成功 1 / 跳过 0 / 失败 0`），记「PM 采信 + QA 复现」。
- 基线提醒：本分支基于 `main`（不含 T547 的 D-1 修复），故「herdr pane 内跑门禁」会红（见 §四 P1）。

## 一、数字

- `check` → **rc=0**（`check: OK · roles=7 · files=54 · layout=main-row2`）。
- `npm test` · herdr 腿（我在 herdr pane `w1:p1` 内）→ **rc=1**，665s，34 例，**2100 PASS / 3 FAIL / NOTE 10**；tmux 腿（`NAO_TEST_TERMINAL=tmux`）→ **rc=1**，363s，**1949 PASS / 3 FAIL / NOTE 10**。两腿的 3 条红**完全同一处** = `case 28 P2-1②`（见 §四 P1，非本批缺陷）。
- 摘 `HERDR_PANE_ID/HERDR_WORKSPACE_ID/HERDR_TAB_ID` 复跑（差分证明归因，同代码同 env 只差三件）：herdr **rc=0**（683s · **2103 PASS / 0 FAIL / NOTE 10**）· tmux **rc=0**（361s · **1952 PASS / 0 FAIL / NOTE 10**）。
- `case 23` 两腿均 **PASS** · `case 29` **PASS(18)** · `case 30` **PASS(19)**（AC4 反假阳性/幽灵 pane 未被本批放宽）。
- AC3 独立真机（隔离 tmux socket · 开关开 vs 关）：pi 命令行归一（仅替换任务名与提示文件路径）后 **diff 空 · md5 相等**（`e174ce2b…`），两态均无 ` -- ` 注入段。

## 二、三件结论（PM 问）

**1）AC2 判据不能取「固定 `--lines` + 固定时机」** —— 实测两条独立原因：
- **`--lines` 在 agent 非 idle 时直接报错**（这就是「投递后立刻读 = 0」的真因，不是单纯滚屏）：`{"error":{"code":"agent_not_idle","message":"cannot read 80 lines while w1:p1 is working: its alternate-screen history can only be captured by scrolling while idle. Wait and retry, or use --source visible"}}` ⇒ 交付瞬间（正 working）读 80/200/300 **必为 0**。
- **idle 后锚的深度随本轮输出漂移**：我这次 idle 时 80 行就能命中（8861B）、200+ 行封顶 9950B；PM 那次要 300 行 ⇒ 任何固定 N 都会在不同轮次/不同机器上假红。
- **seq 差分本身可靠但有陷阱**：idle 静默 10s seq 恒定（7→7，无自增）；投递后 0.2s 内 `idle→working` 使 seq +1，**turn 结束再 +1** ⇒ 「就绪 seq=1 → 投递后=2」只在**投递后立刻采样**成立，等 turn 完再采就是 3 ⇒ `== ready+1` 不可作判据，`> ready` 才是。
- **建议判据（不假红/不假绿）**：① 投递面 = `agent prompt` rc==0 **且** stdout 无 `"error":{"code"`；② 执行面 = 投递后 ≤10×100ms 观察 `agent_status==working` 或 `state_change_seq >` 投递前基线（同一预算内，不新增轮询面）；③ 内容面（辅助）= `agent read --source visible` 命中常量首行（screen 快照，working 期间也可读；实测 t=0…12s 恒命中）。**禁**用 `--lines`（working 必错）；若坚持历史窗口，只在 idle 后读且「缺锚」判**不确定**而非红。

**2）`--source full` 为何 0 命中** —— 不是语义差异，是**非法枚举**：herdr 0.9.5 只接受 `visible|recent|recent-unwrapped|detection`；`--source full` 返回 rc=1 `Error: ... invalid read source: full`（65 字节，无锚）⇒ 我们把错误输出当正文读了。漂移面不在 `full`（非法值不会变合法），而在 `--lines` 的 **idle 前提**与历史**深度上限**（实测封顶 ≈9950B）。

**3）`case 23` 的真实 herdr 段** —— `capture_of` 的 herdr 分支确实写 `--source recent-unwrapped --lines 80`，但该分支跑的是**替身**（`be_herdr`），而替身的 `agent read` **完全忽略 `--source/--lines`**（直接回累积 screen）⇒ ① 无时序依赖（不会因高负载翻红）；② 但**判据比真机宽松**：把 `--lines 1` 或 `--source full` 写进去照样绿 ⇒ 真机的 `agent_not_idle`/深度限制**没有任何断言覆盖**。判定：**不是「断言依赖时序」缺陷，而是「替身宽松 ⇒ 判据空转」缺陷（P2）**。

## 三、AC1–AC5 终判（+ 两处远端证据）

- **AC1 ✓**：herdr 真机 `ensure pm` → rc=0 · 2216ms · 成功 1（PM 采信 + 我复现）；tmux 真机（隔离 socket · 名册离线）→ rc=0 · 成功 1。
- **AC2 △（功能对、判据需改）**：真机自检确实送达并被执行（`agent read --source visible` 命中锚、seq 转 working；PM 另在 `pane read` 见 `npm view` 与结论行 ⇒ 采信）；但既有机械判据按 §二.1 会假红/空转。
- **AC3 ✓**：`NAO_UPDATE_ON_ENSURE=0` 与默认开的 pi 命令行**逐字相同**（`case 23` AC3①–④ 含 md5 相等；变异「拼回 argv」⇒ 14 FAIL）。注：本分支基线是 T547 之前的裸名形态（`pm`），与 #138 合并时需再核一次。
- **AC4 △**：七条件代码未改（AND 含 `idle` + `seq≥1` + `skip`；单一投递点；失败 rc 仍 0/不计失败/默认可见 warn）；`case 29`(18) 与 `case 30`(19) 绿。**但**我把 AND 里的 `agent_status == idle` 删掉后：`case 23` **PASS**、`case 29` **PASS** ⇒ 「七条件不放宽」只有**文本存在性 grep**（warn 文案即可满足），缺机械负控（P2）。
- **AC5 △（红因不在本批）**：见 §一（3 条红 = T547 的 D-1，本分支未含）。
- **tmux bracketed-paste（RD 自述核对）**：隔离 socket 实测 —— flag=0 的 pane（`cat`/`sleep`）`paste-buffer -p` 收到**裸字节**（无 `ESC[200~`）；flag=1 的 pane（自行请求 `ESC[?2004h`）收到 `ESC[200~…ESC[201~` 包裹且保留换行；归一后单行投到 flag=0 pane ⇒ 恰 1 行。**但真 pi 的 flag 在 `pane_current_command==pi`（10ms）之后 ~1349ms 才置 1**，fleet 的判定点在 ~10–100ms ⇒ 实际**总走归一**；端到端（真 pi · tmux）实测文案被压成**一行**。RD 的「真 pi ⇒ 保留多行」在本机不可达（P3：只影响形态，不影响送达/执行）。
- **负控 6 组（我自跑变异，非采信）**：① 拼回 argv ⇒ case23 **14 FAIL**（首条 = AC3 静态「不再拼进 argv」）· ② `term_deliver`→noop ⇒ **8 FAIL**（首条 = AC2① 锚 0 / 投递 0 / seq 未推进）· ③ 忽略开关 ⇒ **3 FAIL**（AC2③ 开关关仍有锚）· ④ 删 AND idle ⇒ **0 FAIL**（缺口，见 AC4）· ⑤ 失败路径静默 ⇒ **4 FAIL**（AC4① warn/error code）· ⑥ 开关开/关 md5 相等（AC3④）被 ① 同步打红 ⇒ 非空转。

## 四、缺陷与观察项

- **P1（非本批引入）** 本分支基于 `main`，`cases/28` 的 `B2_ENV` 仍缺 `HERDR_PANE_ID`（T547 已修但未合并）⇒ 在 herdr pane 内跑，两腿都红 3 条。处置：随 #138 合并自动消失；**在此之前本分支的 rc 口径须写「herdr pane 内有 3 条已知红」**。
- **P2** `case 23` 替身对 `agent read` 忽略 `--source/--lines` ⇒ AC2 真机判据空转（见 §二.3）。
- **P2** AC4「七条件不放宽」缺机械负控（删 `idle` 条件全绿，见 §三）。
- **P3** tmux 归一判定点早于真 pi 的 bracketed-paste 协商（~1.3s），实际恒归一 ⇒ 文档/回执不应声称「真 pi 保留多行」。

## 五、建议与结论

- **可交用户复验：可以**（用户场景 = `ensure pm` 应 rc=0；实测 2.2s、成功 1，自检送达并执行，失败/幂等/开关语义都对）。
- 建议本批顺手修 P2 两条（都很小）：① `case 23` 替身补 `--lines/-source` 语义（至少 working + `--lines>viewport` 返 `agent_not_idle`），真机 AC2 改用 §二.1 的 seq/visible 组合或降为冒烟；② `case 23` 加「逐条删七条件 ⇒ 必红」的变异自证。P3 只改文案口径。
