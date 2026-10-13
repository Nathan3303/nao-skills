# T515 机制 bug 猎捕报告（第三轮 · rd-infra）· 2026-10-13

> 接续 `2026-10-13-T515-forensics.md`。实验场 `/tmp/t515v4`（隔离 tmux server，全部调用
> `env -u TMUX` + 统一 `TMUX_TMPDIR`）；护栏：close 前自查身份 `nao-rd-infra`（pane %0 /
> pid 132203），目标仅夹具名；禁 `pkill -f`；夹具用 `sleep` 桩，不派生真实 pi。
> 每完成一个实验块立即 append（增量落盘）。

## 块 0 · 死因取证补全（读两次死亡会话原始 jsonl）

- 死亡 1（01a13333，03:10:48Z 最后一条 bash）：fb2 夹具收尾 `tmux kill-server` **裸跑**
  （`TMUX_TMPDIR` 只前缀到两次 ensure）→ tmux 客户端在 `$TMUX` 已设时**无视
  `TMUX_TMPDIR`** → kill-server 打到真 server（调用者自己的 `nao-rd-infra` 会话在内）
  → 自灭。CALL 无回执（pi 与 bash 同 pane 同批被 SIGHUP）。
- 死亡 2（01a1333f，03:37:49Z 最后一条 bash）：v3 实验同样以裸 `tmux ls` +
  `tmux kill-server` 收尾 → 同型自灭；工具结果与截断的助手消息均已写盘（SIGHUP 时序差）。
- coredumpctl 无记录、无 OOM ⇒ 两次均为**「夹具清理脚本连坐真实 server」**，非 pi 崩溃、
  非 fleet close 的 kill 路径打到自己（见块 3 复证）。

## 块 1 · V4 复证：close bugz「仅派生在场」（接手 /tmp/t515v3 残点）

夹具：隔离 server（/tmp/t515v4/tmux-1000/default）仅一个派生桩 `nao-bugz-T2`
（标题 `π - bugz-T2 - lab`），精确 `nao-bugz` 不存在；名册无 bugz 条目。

- **status bugz 误报在线**：`✓ bugz 在线（--name bugz；卡片 bugz.md）`——根因
  `running()` 第③层 `tmux has-session -t nao-bugz` 被 tmux 的**会话名唯一前缀匹配**
  命中 `nao-bugz-T2`（v3 的误报同源，本轮给出机制级解释）。
- **close bugz 误回收派生**：rc=0、`已回收 bugz（tmux 会话 nao-bugz）@ .`——
  close 的 pane 三层定位（标题契约/名册 tmuxPane）均不命中后，退到
  `kill-session -t nao-bugz`，同一前缀语义把派生 `nao-bugz-T2` 一起杀掉
  （事后 `tmux ls` = no server，桩已死），且**谎报成功、零警告**。
- 自体核验：pane %0 / pid 132203 存活 ✓（close 本身未伤调用者）。

**结论**：缺陷坐实——「常驻名 close」在仅派生在场时会静默误回收派生会话
（tmux -t 唯一前缀匹配 + fleet 未用 `=name` 精确锚）。误报在线与误回收同根因。

## 块 2 · V4：close 目标精确性与修复对照（tmux 层）

夹具：keeper(占 %0 防跨 server 撞号) + 精确 `nao-bugz` + 派生 `nao-bugz-T2`。

- **双在场时精确**：`close bugz` → 只杀精确 `nao-bugz`（pane %1，标题契约层①命中），
  派生 T2 存活，rc=0 —— 标题契约是精确前缀串（`π - bugz - `），不误伤 `π - bugz-T2 - `。
  （插曲：首跑夹具 pane id `%0` 与我本尊 pane `%0` 跨 server 撞号 ⇒ F1 闸门**假阳性拒绝**
  rc=1、零杀伤——安全方向的误报，顺带证明闸门在位；见块 3。）
- **仅派生在场时误杀根因 = tmux 前缀语义**（干净重跑）：
  - `has-session -t  nao-bugz` → rc=0（**误命中**派生 nao-bugz-T2）
  - `has-session -t =nao-bugz` → rc=1 `can't find session`（**= 锚定精确匹配，正确**）
  - `kill-session -t nao-bugz` → rc=0，派生 T2 被杀（ls 只剩 keeper）
- 修复方向：fleet 的 `has-session/kill-session -t nao-<name>` 一律改 `=nao-<name>`
  （或先 `list-sessions -F` 全等过滤），否则「close 常驻名」在任何仅派生在场场景
  都会静默误回收派生会话并谎报成功。

## 块 3 · V4：F1 自伤闸门双向验证 + 死亡根因机制实证

- **闸门真阳性**：`TMUX_PANE=<夹具 pane id>` 跑 `close bugz-T2` → `拒绝回收 bugz-T2：
  解析出的 pane %1 与调用者自己的 pane（$TMUX_PANE=%1）相同`，rc=1，桩无损。
- **闸门假阳性（安全方向）**：跨 server pane-id 撞号（两 server 各有 %0）→ 误拒
  （块 2 插曲）。pane id 只在单 server 内唯一，跨 server 字符串比较不可靠。
- **死亡根因机制实证（只读）**：`$TMUX` 已设时，`TMUX_TMPDIR=… tmux list-sessions`
  仍返回**真 server** 会话（nao-rd-infra）；`env -u TMUX` 后才返回夹具（keeper/nao-bugz-T2）。
  ⇒ 两次死亡的裸 `tmux kill-server` 必然命中真 server，调用者 pane 同灭。
- 自体核验：pane %0 / pid 132203 全程存活 ✓。

## 结论

**(a)「仅派生在场 / 名字前缀误杀」是否自然被「自己 DD 本人」？**
缺陷本身自然可达（任何 `close <常驻名>` 在精确会话缺席、其派生在场时触发），但
**打不到调用者自己**：误杀对象是「目标名的前缀会话」（nao-bugz*），调用者会话名
nao-rd-infra 不在其前缀内；且 close 对自 pane 的路径已被 T513-S2 的 F1 闸门双向
闸死（块 2 假阳性 / 块 3 真阳性）。自然自达的是**夹具清理习惯**：裸 `tmux kill-server`。

**(b) 两次死亡是否 self-close / 被 close 链打到？**
否。证据链：① 两次死亡最后一条命令收尾均裸 `tmux kill-server`（01a13333@03:10:48Z、
01a1333f@03:37:49Z，全文已还原）；② close 实验在 v2/v3/V4 三轮复跑均 rc 正常完成、
pane 未消失；③ `$TMUX` 继承使 TMUX_TMPDIR 失效（块 3 实证）→ kill-server 连坐真
server 上调用者所在的 nao-rd-infra 会话；④ PM 不在 tmux（名册 tmuxPane=null）⇒ PM
存活，与「PM 活 RD 死」矛盾自洽；⑤ 无 coredump/无 OOM ⇒ pi 是被 SIGHUP 带走的，
非崩溃。**死因 = 实验夹具收尾误杀真实 server，fleet close 无责。**

**(c) 缺陷清单（按严重度）**
1. 【高·close 家族】tmux 会话名唯一前缀误命中：`has-session/kill-session -t nao-<名>`
   在精确会话缺席时误命中派生 `nao-<名>-<task>` ⇒ status 误报在线（V4-1a）+
   close 静默误回收派生并谎报成功（V4-1b/2c'）。最小修复：一律 `=nao-<名>` 锚定。
2. 【高·操作/工具缺口】裸 tmux 客户端连坐真实 server：`$TMUX` 已设时 TMUX_TMPDIR
   被无视（块 0 + 块 3b 实证），两次自灭的直接原因；fleet 缺「实验场安全清理」入口，
   文档应明令实验/夹具一律 `env -u TMUX` 且清理用 `-S <socket>`。
3. 【中】F1 闸门跨 server pane-id 撞号假阳性（块 2/块 3）：拒绝是安全方向，但会
   误挡合法回收；修复需记录并校验 pane 所属 server。
4. 【低】close 回执 repo 误导：pcwd 取 pane_current_path（继承 client 端 cwd），
   回执 `@ nao-skills` 与夹具事实不符（V4-2a'/2b），审计易误读。

实验场 /tmp/t515v4 已清理：`env -u TMUX` + `-S` 精确 kill-server 首跑 rc=0、复跑 rc=1
（no server running，零残留；未触碰真 server——真 server 仅剩 nao-rd-infra）。
