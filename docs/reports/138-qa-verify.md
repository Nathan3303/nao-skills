# 报告：#138 / T547 全量验收（QA 独立复核）

- 结论：**AC1–AC12 逻辑逐条可达；门禁在 herdr pane 内跑不绿 = 测试夹具缺陷 D-1（非实现缺陷）；另有既有缺陷 O-1 让 AC1/AC7 的真机可用性打折**。建议本批修 D-1（一行）与 D-3（两处文案），O-1 立即立项。
- 被测：`feat/138-fleet-param` @ `20ad2f8`（实测 `f946879`；`git diff 20ad2f8 f946879` 仅 `docs/tasks-state.md` +6 行，代码同一）
- 方法：干净 worktree（`npm ci`）+ `check` + `npm test` 全量 ×3 组环境 + **真 herdr**（独立 session `qa-t547`，判据取 `pane list` / `workspace list` 原文）+ 差分/变异负控；只报不修
- 环境：herdr 0.9.5 / protocol 22 · 宿主 pane `w1:p1`（session `nao-skills`）· pi ≥1.4.0

## 一、门禁数字（命令 → rc / 例数 / 断言 / SKIP·DEGRADE·NOTE）

- `bash .agents/scripts/nao-fleet.sh check`（worktree）→ **rc=0**：`check: OK · roles=7 · files=54 · layout=main-row2`；1 条 `! codegraph 已就绪但当前仓无索引` = worktree 无 `.codegraph` 的环境产物（主仓同命令 rc=0 无 `!`）。
- `npm test` · **自然 env（我在 herdr pane `w1:p1` 内，= 默认后端的常态）** → **rc=1**，715s；34 例；断言 **2119 PASS / 3 FAIL / 11 NOTE**；SKIP=0 / DEGRADE=0。
  - 唯一红 = `case 28` 的 `P2-1②` 三连（`close rd-fe rc=1`）⇒ 成因 D-1；同场景在真 herdr 上手工复跑 rc=0（§三）。
- `npm test` · 全摘 `HERDR_*` → rc=1，645s；唯一红 = `case 27`「生产端点不可判定」（该例**按设计**要宿主真实端点做渗透判据）⇒ 摘 env 不是绕过路径；两例要求互相矛盾 ⇒ 修点必须在 `case 28` 夹具。
- `case 28` 差分负控：自然 env ⇒ **FAIL 3 断言**；仅摘 `HERDR_PANE_ID/HERDR_WORKSPACE_ID/HERDR_TAB_ID` ⇒ **PASS**（rc=0）。唯一变量 = 宿主 pane 身份。
- 首轮全量（重启前 `20ad2f8`）：rc=1，1156s，2112 PASS / 5 FAIL / NOTE 11 / SKIP=1；除 case 28 三连外多出 `case 33` AC6 两条（未复现，见 O-2）。

## 二、AC1–AC12 终判（真 herdr 实物判据）

- AC1 ✓ 零配置多仓：两临时仓（无 `fleet-scope`）各 `ensure pm` ⇒ `pm@api`（ws `api`）+ `pm@web`（ws `web`）并存。⚠️ 两 pane 的 `foreground_cwd` 都是 herdr **server** 目录（O-1）。
- AC2 ✓ `api` 同名两仓 + `--fleet alpha` / `--fleet beta` ⇒ `pm@alpha` / `pm@beta` 并存，workspace `alpha` / `beta` 独立（panes=1 各）。
- AC3 ✓ 三档各一：`--fleet xfile`（来源 `--fleet/--scope`）> 文件 `yfile`（来源 `.agents/fleet-scope`）> slug `tiers`（来源 `默认仓 slug`）。
- AC4 ✓ 正向：本仓（目录名 `nao-skills`、零配置）`ensure rd-fe` ⇒ `rd-fe@nao-skills` + ws `nao-skills`（保留前缀只限 core）；反向：`--as nao-x` / `--as subagent-x` ⇒ rc=1「不得以保留前缀 … 开头」+ 零 pane；正控 `--as code-reviewer-notes` 接受并拉起。
- AC5 ✓ `--fleet x --scope y` ⇒ rc=1「等价，只能给一个」，pane 数不变（零副作用）。
- AC6 ✓ 同仓 legacy 裸名（真 pi，`π - rd-infra - nao-skills`）⇒ `close rd-infra` 打印「close 命中同仓 legacy 裸名」+「已回收（herdr pane wC:p1）」，**无**「未运行（无需回收）」；rc=0。
- AC7 ✓（有前提）同名重复 `ensure`：**pane cwd == 仓** 的会话 ⇒「已在运行…跳过」rc=0、pane 1→1；**pane cwd ≠ 仓**（O-1 场景）⇒ rc=1「同 core 但 fleet/仓不同」⚠️ 假冲突。实现口径 = warn+跳过（PRD 写 fail loud，case 33 断言「跳过」，属既有语义）。
- AC8 ✓（代码面）`case 28` / `case 33` 的「改回旧实现必红」负控全绿；门禁整体 rc 受 D-1 影响（测试侧）。
- AC9 ✓ `--scope dep9` ⇒ `rd-fe@dep9` + ws `dep9`（等价 `--fleet`），`已弃用` 提示**恰 1 行**；`--help` 里 `--fleet` 为主、`--scope` 标「已弃用」。
- AC10 ✓（正文一致）INSTALL「会话命名与多仓舰队」/ README 多仓段逐条对得上实现：fleet 恒非空 · 保留前缀只限 core · 文件=「覆盖默认值」· 零配置示例 · 撞车条件 · 名长两态 · `--scope` 弃用 · 并存期 · `status` 显示 `·fleet=`。两处**文案级**不一致 → D-3。
- AC11 ✓（安全关键）同仓 legacy 裸名在场 + `ensure rd-infra` ⇒ pane **1 → 1**，「已在运行（legacy 裸名 rd-infra ≡ rd-infra@nao-skills…）跳过」。
- AC12 ✓ 默认 tier（目录 16 + core 36）⇒ 截短 `a2345678901`（11 字符）+ **恰 1 行**提示，pane 正常；显式 `--fleet` 16 位同 core ⇒ rc=1（53 > 48）、零 pane、点明「core 不变时最多 11 字符」；三常量未改（48 / 卡 core≤32 / fleet≤16）。
- 术语：`status` 在线行 = `✓ pm 在线（--name pm@api；卡片 product-manager.md）·fleet=api`；全文 `·fleet=` 1 处、`scope=` 0 处。

## 三、缺陷与观察项（分级 · 只报不修）

- **D-1（严重 · P1 · 测试夹具 · 本批必修）** `tests/t4/cases/28-naming-contract.sh:1097` `B2_ENV` 未隔离宿主 `HERDR_PANE_ID`（同文件 `B3_ENV:1782` 已钉 `w9:p9`，B2 漏）。B2 夹具 pane 固定 `w1:p1`，herdr 单 pane 会话宿主恰是 `w1:p1` ⇒ `_term_herdr_self_refuse` 判「调用者自身」⇒ close rc=1 ⇒ **默认后端下 `npm test` 必红**（TMUX 跑者看不到）。修法：`B2_ENV` 加 `HERDR_PANE_ID="w9:p9"`（B3 同款）。证据：自然 FAIL(3) / 摘三件 PASS / 手工 close 复现 rc=1→摘三件 rc=0「已回收」。
- **O-1（严重 · P1 · 既有缺陷 · 本批暴露）** `ensure` 的 `repo` 保留 `roles.yaml` 的 `workspace: .`（相对值）：`herdr workspace create --cwd "$repo"` 由 **server** 解析 ⇒ pane 与 `cd .` 都落在 server 目录。三症状：① pane cwd 错（两仓都落同一目录）；② 同仓重复 `ensure` 误报「同 core 但 fleet/仓不同」（rc=1 假冲突）；③ 跨仓 legacy 等价/归属判据拿不到正确 cwd。差分：`ensure rd-fe@/abs/repo` ⇒ `foreground_cwd` 正确、就绪门通过；`ensure rd-fe` ⇒ server 目录 + pi 弹 Trust。`main` 同码（非本批引入），但它是 AC1「两仓各一支队」真机可用性的关键。修法：spawn 前 `repo="$(_fleet_phys "$repo")"`（或 `pane run` 用绝对 `cd`）。
- **D-2（一般 · P2 · 测试 flake · 已定性）** `case 06` `E2-1 夹具自证`：`printf '%s\n' "$decl" | grep -Fxq "$loc"` + `set -o pipefail` ⇒ `grep -q` 早退时上游 `printf` 收 SIGPIPE（pipeline rc=141）⇒ **真命中判成「未归类」**。同文件 `tests/t4/lib.sh:281-283` 已记录同类（T534-O2，修法 here-string），`e2_gate` 漏改。复现：8 路并发 320 轮 ⇒ 3 次（点名 `AGENTS.md:33` / `docs/INSTALL.md:34`）；机制确定性演示：decl > 管道缓冲时同写法 rc=141。**与 server 死亡/并发/`MIN_PI_VERSION` 残留无关**。修法：`grep -Fxq -- "$loc" <<< "$decl"`。
- **D-3（轻微 · P3 · 文档 · PM 归属）** ① `docs/INSTALL.md:123`「预算：`core` ≤32」缺「卡」限定（实现 = **卡 core** ≤32；派生 core 只受总长 48 约束）。② `.agents/common/intercom-protocol.md:11` 指针仍写「会话命名与多仓 scope」，本批已改名「会话命名与多仓舰队」。
- **O-2（一般 · P2 · 观察项 · 未复现）** `case 33` AC6 两条 close 断言在首轮高负载全量红，单跑 2 次全绿，未抓到掉线/`9.9.9` 残留。归口：观察项，到期 **2026-12-05**（下批首日复核；再复现即升级缺陷）。

## 四、风险与建议

- D-1 让「默认后端的 QA/RD 跑门禁」恒红，极易被误读成实现回归；PM 在 tmux 侧看不到 ⇒ 验收数字必须写明**跑者所在 pane**。
- O-1 让多仓并行「看起来能用、其实两个队在同一目录」，并让重复 `ensure` 报假冲突 ⇒ 用户侧第一个反馈大概率是它。
- 建议：本批修 D-1 + D-2 + D-3（都极小）；O-1 一行修后单独立 PATCH/MINOR 复核；修完重跑 `npm test`（herdr pane 内）+ `--case 28` 差分即可。

## 五、复跑命令

- `cd <worktree> && npm ci && bash .agents/scripts/nao-fleet.sh check`
- `npm test`（在 herdr pane 内；预期唯一红 = case 28 `P2-1②`）
- `env -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID npm test`（预期红 = case 27）
- `bash tests/t4/run.sh --case 28`（自然 FAIL / 摘三件 PASS）

## 六、复核轮（`015777c` · 四项已修）

- 采信 PM 抽验（未重复）：`--case 28` PASS、`--case 06` PASS、`check` rc=0、工作树空。
- 门禁（herdr pane `w1:p1`，默认后端）：`check` **rc=0**（主仓无 `!`；worktree 唯一 `!` = 无 `.codegraph` 的环境产物）；`npm test` **rc=0**，727s，34 例，**2133 PASS / 0 FAIL / NOTE 11**（全白名单）/ SKIP=0 / DEGRADE=0。与 RD 报的 2135/10 差 2 PASS+1 NOTE = **断言与 NOTE 计数随后端变化**（实测 `--case 09` herdr 35+1 / tmux 47+0；`--case 34` herdr 57+1 / tmux 58+0）⇒ 跨后端总数不可直接比，判据取 rc。
- **D-1 ✓**：同一命令 `HERDR_PANE_ID=w1:p1 --case 28` 首轮 FAIL(3) → 本轮 **PASS**；修复 = `B2_ENV` 加 `HERDR_PANE_ID="w9:p9"`（与 `B3_ENV` 同款）。自判据未被掩盖：`B3⑤`「祖先链命中」与「不可判定+全等」两组仍绿，且 B3 自己显式注入 `w1:p1` 撞号场景。
- **D-2 ✓**（自造 SIGPIPE，非采信）：① 老写法 + pipefail，11MB `decl`（命中在首行）⇒ **rc=141 5/5**，here-string ⇒ **rc=0 3/3**；② 复刻首轮压力形态（每轮新建 lab + 全 `e2_gate`，8 lane）⇒ 老写法 **1/240 假红**（点名 `.agents/common/intercom-protocol.md:36`），here-string **0/240**；③ `--case 06` 在 ≥8 路并发（`--case 19`×8）下连跑 **3/3 PASS**；④ 真规模（≈500B decl）串行 2000 轮老写法 0 次 ⇒ 竞态窗口在「大输出/高 I/O」，与 server 死亡无关。
- **O-1 / AC13 ✓**（真 herdr，server cwd 故意设为 `/tmp/t547-evidence/serverdir` ≠ 任何仓）：正控 `ensure pm` in api/web ⇒ `pm@api` cwd=`/tmp/t547-qa/r2/api`、`pm@web` cwd=`/tmp/t547-qa/r2/web`，workspace `api`/`web`；症状②消失（同仓重复 ensure ⇒「已在运行」rc=0、panes 2→2）。负控（副本删掉 `repo="$(_fleet_phys "$repo")"`）⇒ pane cwd=`…/serverdir`、重复 ensure **rc=1**「与在场会话同 core」。`--card` 分支无缺口（`CARD_REPO` 已是 `nao_phys_path` 结果）。
- **D-3 ✓**：指针改「会话命名与多仓舰队」；INSTALL 改「**卡会话** `core` ≤32（普通角色 id 更短）」——与本轮 diff 逐字一致。
- **连带 1（`cases/24` AC2①：`cd .` → `cd <仓物理路径>`）= 必要连带，不是放宽**：生产串已变（不归一即 AC13 红）；断言仍**整串 diff**（零新增参数 + name/card/`cd` 全钉），`cd` 从 `.` 升级为精确绝对路径 ⇒ 更严。实证：删掉归一的副本跑 `--case 24` ⇒ **恰 1 条红**，diff 明示 `< cd /tmp/nao-t4…/lab24-…` vs `> cd .`；tmux 后端同用例 PASS(78)。
- **连带 2（`herdr-double` 的 `HERDR_DOUBLE_SERVER_CWD` + `path.resolve`）= 不比真 herdr 宽松，反而更接近真机**：真机实测（本轮）server cwd=`…/serverdir` 时 `workspace create --cwd .`（客户端在 web 仓）⇒ pane cwd = **server 目录**，`--cwd /abs` ⇒ 绝对路径原样；替身默认（无旋钮）行为不变（`path.resolve(".")` = 调用方 cwd = 仓，与旧版「`.` 事后按调用方解析」等价），设旋钮才复现失败面；旧替身把相对 `--cwd` 当字面值，恰好**掩盖** O-1。
- **O-2**：本轮未复现（gate 内 case 33 全绿 + 单跑全绿）⇒ 观察项维持（到期 2026-12-05）。
- 结论：**可交用户走查**（用户验收单已按 O-1 修复更新：删掉「pane cwd 落 server 目录」的规避项）。
