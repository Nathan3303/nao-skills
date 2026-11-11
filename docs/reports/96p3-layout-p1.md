# #96 三期 P1 · herdr 布局 A + 空间判据（J1–J5）+ 真机整轮（交付报告）

> 分支 `feat/96p3-layout`（base main `08425c3`）· 范围 = PRD `docs/prds/2026-11-10-herdr-base.md` **附三**（三期评审与 PM 裁定）
> + §七 **AC3.1 / AC3.2 / AC3.5**。**本批不动默认值**（`NAO_TERMINAL` 仍默认 `tmux`）、不做 P2（默认切换 / 双 golden 分离 /
> exit 3 文案 / `check` 渲染 / 文档三处）。
>
> 本报告不含实现代码，只给契约、判据、本机实测数字与**与 PM 清单的两处偏差**。

## 一、交付面（一句话）

herdr 后端的放置从「一个 workspace 里往同一 tab 里 split」改成 **布局 A**：**1 workspace/仓（`label`=scope）+ 1 tab/角色
（`label`=角色名）+ 每 tab 恰 1 pane**；既有会话（旧布局的共享 tab）用 `pane move --new-tab` + `tab rename` **无损迁移**；
放置后**自测空间**（J1/J5：herdr 不报空间不足、rc 不可作判据）——不足只 warn、0 尺寸 pane 计 `SPAWN_FAIL`；新增真机整轮
用例 `cases/32`（四件私有 env ⇒ 结构性不碰用户 `default`/`~/.pi`）。

## 二、契约（唯一事实）

### 2.1 布局 A（AC3.1）

| 维度 | tmux（零回归） | herdr（本批） |
| :-- | :-- | :-- |
| 拓扑 | 逐字不变（派生宿主窗口 + `split-window` + 布局重排） | **1 workspace/仓**（`label` = scope，无 scope ⇒ `HERDR_SESSION`）+ **1 tab/角色**（`label` = 会话全名，含 `@scope`）+ 每 tab 恰 1 pane |
| 判据 | 列宽算式（`main_row2_min_col` / 137 / 184） | **结构判据（非几何）**：`tab list` 的 `pane_count == 1` ∧ `pane list` 的 `tab_id` 对应 ∧ pane_id 唯一 |
| 新角色 | `split-window` | `tab create --workspace <ws> --cwd <repo> --label <name> --no-focus`（首角色复用 `workspace create` 的根 tab，`tab rename` 归位） |
| 顺序 | 先建后起 | **先 `tab rename`（tab label）→ 先 `pane rename`（角色身份）→ 后 `pane run`**（顺序是契约：否则 `status` 可能抓到无 label 的 pi pane） |
| 重入 | 判重跳过 | 同（`running_verdict=same` ⇒ 跳过；实测重跑 `0/2/0`、tab 结构零变化） |

角色 tab 已在场、但**没有 pane 命中该角色**（例如 `--force` 撞上仍在场的 pi）⇒ **不猜**：warn + `SPAWN_FAIL`（不新建第二个同名 tab、
也不接管他人 pane）。这是相对二期的一处**语义收紧**（二期会新建 pane 并留下 2 个同名 label），理由是 AC3.1 的「每 tab 恰 1 pane」
在重复 tab 下不可判定；改法已写进 warn（先回收/重建会话，再 `--force`）。

### 2.2 迁移无损（AC3.1 后半）

| 现场 | 动作 | 判据 |
| :-- | :-- | :-- |
| pane 在**共享 tab**（旧布局：一个 tab 内多 pane）且 label=目标名 | `pane move <pane> --new-tab` → `tab rename <新 tab> <角色名>` | `pane_id` **不变**、被搬空的 tab **由 herdr 自动关闭**、`status` 仍在线 |
| pane **独占**一个 tab 但 tab label 是旧的（如根 tab 的 `"1"`） | 只 `tab rename`（零 pane 搬动） | 更小 effect：不触发 pane 重建 |
| tab label 已是角色名但 pane_count > 1（人为 split 过） | **只 warn，不搬动**（他人 pane 归属不可判定） | 不擅自迁移别人的 pane；文案给 attach 收口指路 |

### 2.3 空间判据 J1–J5（AC3.2）

arch 实测事实（附三）：herdr **不报**空间不足（split 从不失败、pane 可被压到 0 行且无 warn、`pane resize` 静默无效）
⇒ **rc 不可作判据**，必须自测。

| 条 | 实现 |
| :-- | :-- |
| **J1** | 放置后 `pane layout --pane <pane>` 取**该 pane 对象**的 `rect`（不取 tab 级 `area`）⇒ `width ≥ TERM_MIN_COLS` ∧ `height ≥ TERM_MIN_ROWS`（默认 **60×10**，`NAO_TERM_MIN_COLS/ROWS` 可覆盖）；不足 **只 warn**，rc 保持 0（沿用 D3） |
| **J2** | 结构判据见 2.1（`pane_count == 1` ∧ pane_id 唯一）；收敛逻辑见 2.2 |
| **J3** | 静态证明：herdr 实现区 `grep -c 'TMUX_MIN_PANE_WIDTH\|main_row2_min_col\|137\|184'` == **0**（扩 `lib.sh::t4_scan_term_herdr_forbidden`，带两条变异负控） |
| **J4** | 小空间可注入：私有 `XDG_CONFIG_HOME` + `[server] headless_cols/headless_rows`（实测 60×20 生效）⇒ 40×8 warn + 指路 + **无 0 尺寸 pane** |
| **J5** | 失败文案三件套：① 哪个 pane 多少列/行 ② 三个可执行动作（调 `[server] headless_*` / attach 后重排 / 切 `NAO_TERMINAL=tmux`）③ 文档指针（`docs/INSTALL.md`「herdr 后端」+ PRD AC3.2）；**不半启动** = 0 尺寸不计成功 |
| 0 尺寸 | `width < 1 或 height < 1` ⇒ warn「空间不可用」+ `SPAWN_FAIL`（摘要说「失败 1」而不是「成功 1」） |

## 三、实测：布局 A / 迁移 / 空间（真 herdr 0.9.1）

用例 `cases/32` 的运行时取证行（`npm test` / `NAO_TEST_TERMINAL=herdr` 的日志里可 grep）：

```
-- 布局 A 实测：workspace=w1 · tabs=[w1:t1/pm/1 w1:t2/rd-fe/1 ]（tab_id/label/pane_count）
-- 布局 A 实测：panes=[pm→w1:p1(w1:t1) rd-fe→w1:p2(w1:t2) ]（label→pane_id(tab_id)）
-- 迁移实测：pane move w1:p1 --tab w1:t3 --split right ⇒ pane_id=w1:p1（不变）· 源 tab w1:t1 已自动关闭 · tab 现=w1:t3
-- J1/J4 实测：headless 60×20 ⇒ 无 warn（pane 60×20 ≥ 60×10）· headless 40×8 ⇒ warn「列=40 行=8」+ 三件套 + 无 0 尺寸 pane
```

- **迁移后 `status` 仍在线**：`✓ pm` 断言在位（迁移不动会话，只动放置）。
- **`close`/`cleanup` 判 effect**：`close rd-fe` 后 pane 从 `pane list` 消失；`cleanup` 后 `sessions/` 空 + 零 herdr/pi 残留进程。
- **幂等**：同一条 `ensure pm rd-fe` 连跑 2 次 ⇒ `（成功 0 / 跳过 2 / 失败 0）` + tab 结构逐字不变。

小空间实测（本批 arch 口径复核，真 herdr + 真 pi）：

| 几何（`[server] headless_*`） | pane `rect` | 结果 |
| :-- | :-- | :-- |
| 120×40（默认） | 120×40 | 无 warn |
| 60×20 | 60×20 | **无 warn**（60×20 ≥ 阈值 60×10 —— 见 §六 偏差①） |
| 40×8 | 40×8 | warn「列=40 < 60 或 行=8 < 10」+ 三件套；**仍计成功**（rc 0） |
| `headless_rows = 0` | — | herdr 直接忽略非法值（回落 120×40）⇒ **真机造不出 0 行 pane**（除非多 pane 挤压，布局 A 结构上不存在）⇒ 0 尺寸负控放在用例 22 的替身上 |

造价（本机实测，`/tmp` 私有实验根，三次独立跑）：`session-start` 0.25s · **`ensure` 2 角色 2.3–6.0s** · `status` 0.9s ·
`ensure` 重跑 0.8s · `close` 1.6s · `cleanup` 0.36s ⇒ **整轮（session-start→ensure→status→迁移→close→cleanup）
6.6–13.8s**。**AC3.5 的「3–6s」在热缓存跑次成立**（实测 6.59s；冷跑次 13.8s，差值主要是两次 pi 冷启动）。用例断言上限
90s（宽松护栏，防 CI 抖动假红），并把实测毫秒数打进日志（`-- 实测：ensure 2 角色 …ms`）。

## 四、真机整轮用例 `cases/32`（AC3.5 · own · 到期 2027-06-30）

- **四件私有 env**：`XDG_CONFIG_HOME` / `HOME` / `PI_CODING_AGENT_DIR` / `TMPDIR`（结构性隔离，不是「小心别碰」）。
- `herdr integration install pi` **尊重 `PI_CODING_AGENT_DIR`**（实测装到私有 `pi/extensions/herdr-agent-state.ts`，
  日志回显私有路径；用户 `~/.pi` 近 3 分钟窗口内零新增）。**注**：`herdr integration install pi` 要求
  `$PI_CODING_AGENT_DIR/extensions` 目录已存在（pi 未初始化时先 `mkdir -p`，否则 `pi extension directory not found`）。
- 流程：`session-start`（清宿主句柄 + 枚举清 `HERDR_*`）→ `ensure` 2 角色（pm + rd-fe）→ 布局 A 结构断言 →
  **就绪七条件在权威源 `agent list` 上逐条复核**（`agent_session` / `idle` / `screen_detection_skipped=true` /
  `state_change_seq ≥ 1`）→ `status` 双在线 → 迁移无损 → `close` 一个 → `cleanup`。
- **缺 herdr ⇒ SKIP 给原因**（AC1.5）：`SKIP: 环境缺少 herdr（需 ≥0.9.1）…`（实测：把 herdr 从 PATH 里摘掉跑同一用例，
  用例 rc=0、汇总 `32 SKIP`）。
- **用户侧零副作用**：`~/.pi` 与 `~/.config/herdr` 的**路径集合**前后逐字一致。只比路径集合、不比内容 —— 并发运行的真实
  舰队会持续向自己的 session 日志追加，比内容会恒假红（这是本批的一条判据设计选择，写在这里便于复核）。

## 五、门禁与证据（本机实测）

| 项 | 结果 |
| :-- | :-- |
| `bash .agents/scripts/nao-fleet.sh check` | **rc=0 ×2**，两次输出逐字相同（`check: OK · roles=7 · files=54 · layout=main-row2`） |
| `npm test` | **rc=0**（`test:agents` + t4 全量 31 例） |
| 用例数（唯一出处） | `bash tests/t4/run.sh --list \| tail -n +2 \| wc -l` = **31**（本批 +1 = 32 号） |
| herdr 门禁 | `NAO_TEST_TERMINAL=herdr bash tests/t4/run.sh` **rc=0**：共享 **20** / 后端专有 **9** / tmux 专有 **2** / PASS **PENDING 0**（对账 20+9+2+0 = 31） |
| 断言增量（运行时 PASS 行，第二轮后） | `case20` 106 → **109**（两后端；close 提示新语义 3 条）· `case22` 34 → **39**（tmux）/ 55 → **61**（herdr；P2-2 静态核 5 条 + herdr 多 1 条 warn 点名）· `case28` 383 → **402**（两后端；P2-1 负控 19 条）· `case32` **75**（herdr）/ 0（tmux 后端门控 NOTE） |
| 全量 PASS 行 | tmux **1593**（第一轮 1566，+27）· herdr **1705**（第一轮 1677，+28）；对**改动前 main 基线**：tmux 1550 → +43 · herdr 1565 → +140 |
| 用例 32 造价（门禁实测） | ensure 2 角色 **2.28s** · 整轮 **6.59s** · 整例（含两场小空间夹具）**13.4s** |
| BR1 三处 md5（tmux 落地段） | 句柄层 `9549f513b7a66fbced68bc1a1fa1dc10` · cleanup 体 `d8937134bb3ed4ceca29fb581d4acf2c` · socket 候选 `e4950f3897670a97d7baaea8f54727c3` —— **与 B3 之前逐字相同** |
| BR1 另两处 md5 | `status` 全文 `144f3447c9ff406d6aed828d9c9720e5`（与 golden 相等）· `ensure` blob `c2de6533a1826dbf470dcc401cb29063`（与 golden 相等） |
| 默认值 | `grep -cE '^NAO_TERMINAL='` = **1**（`NAO_TERMINAL="${NAO_TERMINAL:-tmux}"`，未动） |
| herdr 区禁字 / 台账 | `t4_scan_term_herdr_forbidden` 命中 **0** 行（含新增 J3 四类字样）· `t4_scan_term_bare_calls` 台账 **0** 行（只减不增继续咬） |
| 敏感/机器特定值 | 改动文件内 `/home/<user>`、`/Users/`、私钥、token 模式 **0 命中** |
| `git diff --shortstat main...HEAD` | 见回执（本报告随 PR 提交，故数字以 PR head 为准） |

## 六、与 PM 清单的偏差（两处，均给实测依据）

① **J4 的「60×20 ⇒ warn」不成立**：阈值默认 60×10，60×20 的 pane **满足** 阈值 ⇒ 不该 warn（arch 原话「实测 60×20 生效」
  指的是 `[server] headless_*` 旋钮生效，不是「60×20 会 warn」）。用例 32 按「60×20 不 warn（旋钮生效 + 判据不误报）/
   40×8 warn + 三件套」两场取证；`40×8 < 60×10` 同时覆盖列与行两侧。

② **「0 行 pane ⇒ 计 SPAWN_FAIL」的负控只能用替身**：真 herdr 在布局 A 下结构上造不出 0 行 pane（每 tab 1 pane = 全区域；
   `headless_rows = 0` 被 herdr 忽略并回落 120×40，实测）。故该负控落在 `cases/22`（`herdr-double` 的 `pane layout` 旋钮注入
  `term_rows=0`）：warn「空间不可用：… 行=0 ⇒ 计 SPAWN_FAIL」+ 摘要 `失败 1` + 零成功行。

## 六·二、第二轮（QA：无 P1、2 条 P2）已修

### P2-1 文案与新语义对齐（两处 + 三处同类旧文案）

| 位置 | 旧 | 新 |
| :-- | :-- | :-- |
| `--force` 分支（鬼影/前台非 shell） | 「--force ⇒ 新建 pane…（随后同名 label 会有 2 个，status 将标歧义）」 | 「--force **也不**向在场程序注入按键」+「随后按布局 A 放置：**角色 tab 已被占用 ⇒ fail loud**（不新建重复 label；改法：先 `close` 该角色再 `ensure`）；旧 pane 在共享 tab 里才会新建独立 tab（旧 label 仍在 ⇒ status 标同名歧义）」 |
| 角色 tab 被占（放置失败） | 「attach 后核对/回收…或 cleanup + session-start 重建」 | 「**先回收该角色（`nao-fleet.sh close <role>`）再重跑 ensure**；--force 不绕过本条（避免同名 label 重复）」 |
| `close` 常驻提示 | 「任务闭环后应 `ensure --force` 重开」 | 「任务闭环后应**先 `close` 该角色再 `ensure` 重开**（pane 仍在场时 `ensure --force` 会 fail loud）」 |
| 前台不可判 / process-info 错误 | 「或加 `--force` 新建（会产生同名 label）」 | 「先 close 该角色再 ensure；**--force 不绕过本条**」 |
| 前台非 shell（无 `--force`） | 「或加 --force 新建（会产生同名 label，需人工收口）」 | 「或加 `--force` 后按布局 A 放置（角色 tab 被占用 ⇒ fail loud，不新建重复 tab/label）」 |

**负控（用例 28 B2，19 条断言）**：① tab label 在、pane label=`intruder` + `--force` ⇒ 新文案「角色 tab 已在场但无 pane 命中该角色」+「先回收该角色（nao-fleet.sh close rd-fe）再重跑 ensure」+ 摘要 **失败 1** + **同名 label 仍 1**（pane 数不变、rd-fe tab 仍 1 个、零 `pane run`/`pane split`）· ② 在线 pi 占位 + `--force` ⇒ 「--force 也不向在场程序注入按键 / 角色 tab 已被占用 ⇒ fail loud」+ pane 未增 · ③ `close rd-fe` ⇒ 新提示「先 close 该角色再 ensure 重开」且旧文案「应 ensure --force 重开」已退场 · ④ `close` 后 `ensure --force` ⇒ **成功 1**（证明新提示可执行，不再「照做即失败」）。

### P2-2 J5 文档指针可静态核（用例 22，新增 5 条 + herdr 1 条）

- 脚本里确实写了 `docs/INSTALL.md` 指针；`docs/INSTALL.md` 存在且含**稳定片段** `## herdr 后端`（不写死整行标题 —— PM 改措辞不会假红）；warn 文案与文档同名（「herdr 后端」两端一致）。
- **红/绿双向**：绿 = 正常跑 5/5 PASS；红 = 把 INSTALL 那节标题临时改名 `## herdr-backend-RENAMED` ⇒ 恰好 **1 条**断言红（`未包含: ## herdr 后端`），恢复后 `md5 30c2e436b4694040cc5d17015d9e0e9c` 逐字一致。
- 另有常驻变异负控：把章节名改掉的**副本**上跑同一判据 ⇒ 必红（防判据空转）。

### P3-1（顺手，1 行 → 8 行）迁移日志条件化

旧：无条件写「被搬空的 tab 由 herdr 自动关闭」（源 tab 里还有他人 pane 时不会关 ⇒ 假陈述）。
新：`pane move` 后回查源 tab 是否还在，按实况二选一 —— `被搬空的 tab <tid> 已由 herdr 自动关闭` / `源 tab <tid> 仍有其他 pane（未关闭）`。

### 文档漂移（**提请注意，本批未改**）

`docs/prds/2026-11-01-downstream-role-sessions.md:86`（AC4③）与 `docs/reports/2026-11-01-T537-{arch,rd}.md` 仍写着旧固定前缀
「常驻会话 …：任务闭环后应 `ensure --force` 重开」。用例侧已改为断言稳定片段（`[fleet] 常驻会话 qa：` + `先 close 该角色再 ensure 重开`）+
反向断言旧文案已退场，故**不会假绿**；PRD/历史报告属你（PM）文档域，未被本批改动。

## 七、改动面（只碰约定范围）

| 文件 | 性质 |
| :-- | :-- |
| `.agents/scripts/nao-fleet.sh` | 生产：布局 A 放置 / 迁移收敛 / J1·J5 空间判据 / J2 结构收敛 + 常量 `TERM_MIN_COLS/ROWS` + 头注释与环境变量文档。**默认值、`status` 渲染、tmux 侧逐字未动** |
| `tests/t4/cases/32-real-herdr-roundtrip.sh` | 新增（own，到期 2027-06-30） |
| `tests/t4/run.sh` · `tests/t4/backends/herdr.txt` | 登记 32 号（own）+ 标题 |
| `tests/t4/lib.sh` | `t4_scan_term_herdr_forbidden` 扩 J3 四类字样 |
| `tests/t4/cases/22-ensure-outcome-lines.sh` | 新增 AC5 段：J1 小空间只 warn / 0 尺寸 ⇒ SPAWN_FAIL / J5 三件套 / J3 静态 + 两条变异负控（tmux 后端按 `backend-gate` 门控） |
| `tests/t4/cases/28-naming-contract.sh` | B2 桩扩 tab/move/layout（含 pane/tab id **max+1 分配器**，防撞号覆盖既有 pane）+ 布局 A / 迁移断言（tmux 后端同样跑） |
| `tests/t4/fixtures/herdr-double/herdr-double.cjs` | 替身扩 tabs / `tab list|create|rename` / `pane move` / `pane layout`（`term_cols/term_rows` 旋钮，0 合法）+ 同款 id 分配器 |
| `tests/README.md` | 登记集计数（31 例 / 共享 20 / 专有 9）+ `case32` 行 + 布局 A 说明 |
| （第二轮）`.agents/scripts/nao-fleet.sh` | 5 处文案与新语义对齐（`--force`/角色 tab 被占/`close` 提示/前台不可判/process-info 错误）+ 迁移日志条件化 |
| （第二轮）`tests/t4/cases/28-naming-contract.sh` | P2-1 两条负控（intruder 占位 + close→ensure --force），并让桩的 `pane close` 像真 herdr 一样关掉变空的 tab |
| （第二轮）`tests/t4/cases/22-ensure-outcome-lines.sh` | P2-2 静态核 5 条 + herdr 侧 warn 点名章节 1 条 |
| （第二轮）`tests/t4/cases/20-downstream-card-sessions.sh` | close 提示断言改用稳定片段 + 反向断言旧文案退场（两处，各 +3） |

## 八、遗留与观察项

1. **`--force` 语义收紧**（§2.1 末）：`--force` 撞上仍在场的 pi 时改为 fail loud（不再造出 2 个同名 label）；文案已按新语义全量对齐（§六·二）。观察项仍在：真实用户是否更希望「先关后开」的一步式 `--force`（属回收面，需另立口径）。
2. **attach 客户端尺寸变化后的重排**：仍只有文档口径（PRD 附三「未验」），本批不碰（布局 A 的拓扑判据与几何解耦，风险面缩小但仍未实测）。
3. **`pane move` 迁移后 pi 会话长稳**：本批只到 `pane_id`/即时 `status` 级（与 PRD 附三「未验」一致）。
4. **P2 待办**（另派）：herdr 转默认 1 行 + 双 golden 分离 + 6 条 exit 3 文案 + `check` 渲染 + 文档三处（README / INSTALL / 协议脚注）。
5. **台账**：仍 **0**（本批未新增裸后端调用；herdr 新调用全部走 `_term_herdr_exec`，`--session` 由唯一入口注入）。
6. **P3-2 观察（J3 字面量面）**：J3 用裸 `137|184` 匹配 —— herdr 实现区将来任何含这两个数字的注释/超时值都会误红。建议将来收紧为**具名常量**（如 `TMUX_CAP_137`）或改为只匹配 `main_row2` 相关标识符；本批按 PM 裁定只记录。
7. **P3-3 观察（用例 22 0 尺寸负控）**：现判据是「摘要 `成功 0 / 跳过 0 / 失败 1`」+ 文案「空间不可用 / 行=0 / SPAWN_FAIL」，**未单列**一条「0 尺寸 ⇒ 零成功行（`launch_lines`=0）」的独立断言（用例 22 的 `launch_lines` 只在 AC1–AC4 用）。本批按 PM 裁定只记录，不改判据。
