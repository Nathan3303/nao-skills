# 143 QA 独立验收：门禁分层（快档 ≤2 分钟 · 全量留 PR/发布前）

- 任务 T549 · 分支 `nao/T549-test-tiering` @ `9435e76` · 2026-11-18 · 环境：本机 herdr pane（默认后端）+ tmux 回退 · 交付时工作区干净
- **结论：可合并（GO）** —— AC1–AC10 全过；额外两处风险均不阻断（各留 1 条观察）。只报不修。

## AC 逐条终判

- **AC1 通过** — 三次连跑 `npm run test:fast`：**69 / 92 / 92s**（p90=92s · max=92s ≤120s；另 `run.sh --fast -t` 例内合计 85.588s）。未偷跳断言：白名单 14 例逐例 `[PASS]` 数与全量跑次**严格相等**（例例 OK，合计 **498 = 498**）。
  - 冷跑口径：无 sudo（不能 drop page cache）⇒ 「冷」= 新 shell + 无残留 T4 缓存；三次连跑中最快一次紧接 693s 全量跑（页缓存最热）⇒ 数字未因冷启动被美化。
- **AC2 通过** — `docs/reports/143-profile.md` 已有 per-case 表 + top5（20=121.2s… 合计 44.6%）+ 分类结论；`-t` 每例一行 + 末尾合计（本次 14 行 / 85.588s）；默认输出零 `[TIMING]`（全量跑次 0 行，格式未破）。
- **AC3 通过** — 干净树全量 `npm test`：**rc=0 · 2202 PASS · 34 例（32 跑 + 12/25 TMUX-ONLY）· SKIP=0 DEGRADE=0 NOTE=9 · 693s**，与 profile 基线 2202 **差值 0**。`package.json` 的 `test` 行与分层前**逐字相同**（diff 仅新增 `test:fast` 一行；`test:t4:full*` 未动）。
- **AC4 通过（自跑 strace，不采信 RD 表）** — 成功 execve 归因：
  - `--case 31`：84 次执行**替身** `tests/t4/fixtures/herdr-double/herdr`（其中 `setsid … server` 1 次，仍是替身）· 真 herdr 0 · 真 pi 0
  - `--case 14` / `--case 10`：真 pi 0 · 真 herdr 0（只有 node/bash 与 PATH 探测失败的 ENOENT）
  - `--case 01`（加测）：真 pi 恰 1 次 `pi --version`；真 herdr 恰 1 次 `herdr --session nao-skills api schema`（pane 环境继承的客户端查询，argv 无 `server`）
  - ⇒ 「零真 pi 会话进程 + 零真 herdr server」成立。
- **AC5 通过** — 跳过声明在**默认输出**（不是 -v 才有）：`跳过 20 例（真机类/重档）：02 06 07 …`，汇总另印 `快档：白名单已跑 14 例 · 跳过 20 例`；`-v` 展开 20 行（编号 + 标题 + 类别），起跑即打印。
- **AC6 通过** — 改 `AGENTS.md:18`「默认 herdr」→「默认 tmux」⇒ `--fast` **rc=1**，恰 **case 34 FAIL（8 项断言）**，其余 13 例 PASS，点名端前提声明一致性；还原后 `git diff` 空。
- **AC7 通过** — `NAO_TEST_TERMINAL=tmux npm run test:fast` **rc=0 · 80s · 483 PASS**（herdr 侧 498；差 15 = case 31 在 tmux 走 `backend-gate`，汇总 NOTE=31:backend-gate）。
- **AC8 通过** — `AGENTS.md:19` / `tests/README.md` 与实现逐字一致：`test:fast` = `test:agents` + `run.sh --fast`（14 例 ≈95s）· `npm test` = 全量 34 例 · 发布前置 `test:t4:full`。
- **AC9 通过** — 自造例（`CASE_IDS` 增 `99` + 标题）⇒ `--fast` **硬错**「快档分类缺失用例 99 …（AC9：禁止静默漏测）」rc=1、一例不跑；`--list --fast` 同 rc=1；删掉即恢复（run.sh 与 HEAD 逐字节同）。互斥：`--fast --case 01` rc=1 · `T4_REQUIRE_FULL=1 … --fast` rc=1；`--list --fast` 恰 14 行。
- **AC10 通过** — 6 例豁免注释在位（01/03/04/05/08/17：`豁免：check 的 pi --version ~40ms 探针，非会话进程`），并由 AC4 的 strace 独立证「真 pi 调用只有 `--version`」。
  - 观察：注释只在 `run.sh` 的 `FAST_CASES` 单点（用例脚本内无）—— 与「白名单单点定义」一致，不阻断。

## 额外两处风险

- **① case 31 纳入是否合规 — 合规（建议保留 + 1 条观察）**：实测 **11.795s**（判据③ ≤15s，余量 21%）· 84 次替身 execve（52 次 `api snapshot` 轮询）· 真 pi 0 / 真 server 0 ⇒ ①②③ 全满足；代价 16 条断言（快档 3.2%，含 herdr「集成缺失 fail loud」契约）。观察：它是白名单里唯一被 profile §三 归入「替身重档」的例，且只在 herdr 后端产真断言（tmux 下仅 1 条 gate note）⇒ 慢机上 15s 余量不大，建议随 Stage 2（替身常驻化）复核，本批不改。
- **② 快档会否被误用于 CI/发布 — 不会**：`.github/workflows/` 只有 `pages.yml`（文档站点，无测试作业）；发布前置 `.agents/skills/github-flow.md` → `run-dual.sh` → `npm run test:t4:full`（`T4_REQUIRE_FULL=1`）未改；`--fast` 与 `T4_REQUIRE_FULL=1` 互斥已复验；`.github/` 与 `.agents/` 内 `--fast` 0 命中；`prepack` 仍只 `test:agents`（本批未动，既有口径）。

## 已知漏检 A3 的独立复验（重点）

改单源 `MIN_PI_VERSION` 1.4.0→1.3.0（文档不动）⇒ `--fast` **rc=0（仍绿 · 92s · 498 PASS）**；同树 `--case 06` **rc=1**，`E2-1①/②/③` 全红并点名 `intercom-protocol.md:36 / README.md / docs/INSTALL.md 声明 1.4.0 ≠ 单源 1.3.0`。⇒ A3（该一致性断言只在 06，被单价挡在快档外）**成立**；06 实测 **58s** > 15s，与 PRD 2026-11-18 的接受口径一致。

## 收尾

- 变异/探针全部还原：`git status` 空 · HEAD `9435e76`；删除自建 4 个保留缓存（全量、首次快档 + 两处失败证据）；无 `herdr-double`/probe 残留；`herdr server` 只有用户既有 2 个（11-17 启动，非测试产生）。
- 证据：`/tmp/qa143/{full,fast1,fast2,fast3,fast-tv,fast-tmux,mut-*}.log` 与 `st{01,10,14,31}.exec`（临时目录，不随仓）。
- 本报告未提交（边界：不 push）：建议随任务 PR 一并入库。
