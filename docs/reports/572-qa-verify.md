# T571 + T572 合并后全量验证（批次第一轮）

- 状态：**放行（产品面）· 附 1 条测试夹具缺陷 D1（P2，不阻断本次发布）**
- 日期：2026-11-26 · Owner：qa · 执行方式：**唯一测试执行者**（用户 2026-11-26 拍板，角色卡 v18）
- 验证对象（均已合并进 main，HEAD = `a59d1c3`）：
  - Step 1 `db43278` 命名契约 v3（会话名只含角色 + 身份还原 + 元数据面）
  - Step 1 覆盖补齐 `c65292e`（`cases/28` 补回 herdr golden + C3 变异负控）
  - Step 2 `13676a2` 门面契约中性化（快照 5 列 + 放置面四函数 + 业务层静态闸 + `check.sh` 门面化）
- 覆盖基线：`docs/reports/571-coverage-map.md`（判「断言强度不降」）
- 实现回执：`docs/reports/572-impl-rd-infra.md` · ADR `docs/adr/2026-11-25-term-facade-neutral-contract.md`
- 缺陷台账：`docs/reports/572-defects.md`（D1）

## TL;DR（四段结论）

1. **跑了什么**：`bash .agents/scripts/nao-fleet.sh check` / `tsc` / `npm test`（全量 47 例）/ `npm run test:t4:full`（发布前置）/ 18 例逐任务目标用例单跑 / 孤儿扫描与清理。
2. **实测数字**：`check` rc=0（roles=7 · files=67）· `npm test` rc=0（47 例 PASS · `[PASS]`=2843 · FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=18 全白名单）· `test:t4:full` rc=0（同数字，`NOTE白名单=18`）· 18 例目标用例全 PASS（合计 `[PASS]`=1466）· 起跑前孤儿 93 server + 13 cache 目录已清 0，成功跑次新增 2（D1）也已清 0。
3. **未覆盖**：桌面 app 视觉/UI 呈现（本批无 UI 呈现变更，不适用）；`npm publish` 落地核验（发布动作，不在本批）；tmux 面（ADR 已退役，结构性不可达）。**无因能力缺失而跳过的用例**（SKIP=0/DEGRADE=0）。
4. **放行／不放行**：**放行**（v0.33.0 发布门禁满足）；**已知残留 D1** = `cases/44` 每跑一次泄漏 2 个真 `herdr-core` 进程（测试夹具缺陷，非产品行为），已登记 P2，建议本批或下批修（1 行 + 1 条 effect 断言）。

## 一、环境与命令（逐字）

环境锚点：`NAO_SKILLS=/home/nathan/Projects/nao-skills` · `pi 1.6.0` · `herdr 0.9.5` · `node v24.22.3` · `hc 0.1.22` · 后端 herdr（TUI）。

全部命令在**干净宿主环境**下执行（app 终端里的四件污染变量显式剔除）：

```bash
env -u HC_TERMINAL_SOCKET -u HC_TERMINAL_ID -u HC_SCOPE -u NAO_TERMINAL \
    HERDR_ENV=1 HERDR_SESSION=nao-skills \
    HERDR_SOCKET_PATH=$HOME/.config/herdr/sessions/nao-skills/herdr.sock <命令>
```

按序执行：

```bash
bash .agents/scripts/nao-fleet.sh check
npm test
npm run test:t4:full
bash tests/t4/run.sh --case NN        # NN ∈ 06 09 20 22 23 24 28 29 30 31 32 33 37 39 40 43 44 45
bash tests/t4/run.sh --list | tail -n +2 | wc -l
grep -c '\[PASS\]' <全量输出>          # 断言数口径（tests/README「取数命令四条」）
find "$NAO_SKILLS/.agents" -type f | wc -l
```

长跑用「后台 + 完成信号」执行（**不靠固定 sleep**）：进程退出码写文件、日志末尾 `RESULT:` 行为判据，条件轮询到信号即返回；用例内部就绪判定本来就是 `50×100ms` 上限 `5s` 的有界轮询（`tests/README.md`）。

## 二、实测数字（口径 + 输出）

- `check`：rc=0 · 输出 `check: OK · roles=7 · files=67` · `find .agents -type f | wc -l` = **67**（同口径一致）。
- `npm test`：rc=0 · **47 例**（`--list` 47）· 逐例 `PASS=47 / FAIL=0` · `[PASS]` 行 **2843** · `FAIL` 行 **0** · `SKIP=0 · DEGRADE=0 · NOTE=18（白名单命中 18）`。
- `npm run test:t4:full`（发布前置，`T4_ALLOW_MISSING=0 T4_REQUIRE_FULL=1`）：rc=0 · 47 例全 PASS · `[PASS]`=**2843** · FAIL=0 · `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=18 · NOTE白名单=18）`。
- 两次全量 `[PASS]` 计数**逐字相同（2843）** = 确定性（同一台机、同一 HEAD）。
- 目标用例单跑（rc 全 0；`[PASS]` 为单例断言数）：06=360 · 09=36 · 20=109 · 22=62 · 23=104 · 24=78 · 28=101 · 29=18 · 30=21 · 31=18 · 32=79 · 33=68 · 37=32 · 39=78 · 40=53 · 43=63 · 44=99 · 45=87 → 合计 **1466**。
- 覆盖强度（对照 `571-coverage-map.md`）：`cases/28` 静态 `t4_assert` = **95**、C1 `chk` = **28**，与映射文档逐字一致；运行时 `[PASS]`=101。批次前后全仓静态断言 **2618 → 2401**（Δ −217 = `cases/28` −230 + `cases/06` +12 + `cases/33` +1），减少部分即映射文档归口到 `cases/29/30/31/32/33/37/38/40/43/44/45` 的同契约覆盖。
- 承重性抽查（`cases/28`，非仅计数）：herdr golden `md5=4b7f47b28a141521ec262b2d727348f8` == 记录值（`P2①` 绿）；未设 `NAO_TERMINAL` 与显式 `=herdr` **同源**（默认值唯一）；≠ 冻结的旧 tmux golden `144f3447…`；「默认改回 tmux」变异 ⇒ 必红、复原复绿（先红后绿）；C3①–⑤ 正控 + 14 条负控 + M1–M4 四向变异均在跑次内执行。
- Step 2 关键面（`cases/06` 360 条断言内）：函数数 **200** 三向守恒（清单/顶层并集/总数）· T572 静态闸 9 类禁止词 + 注入负控 + 删词演练（判据承重）· 5 列退回 13 列演练 · `check.sh` 0 处直连 `_term_herdr_exec`、schema 走 `term_api_schema`。
- 孤儿扫描（收尾）：起跑前本机遗留 **93** 个监听 `/tmp/nao-t4.*` 的 `herdr-core` 进程 + **13** 个 cache 目录（属此前被中断/历史跑次，最大单目录 84M）；清理后 **0**。本次成功跑次**仍新增 2 个**（`cases/44` 泄漏，见 D1），已清理；最终监听 **0** / cache 目录 **0**。用户 `~/.config/herdr` 的 `herdr` 会话全程未被触碰（前后均在）。
- 工作区：`git status --porcelain` = `?? .pi/`（会话元数据，与本批无关）；`git stash list` = 0；测试未改真件（变异只在 `$T4_CACHE_DIR` 副本上做）。

## 三、批次 × 目标用例矩阵

- **Step 1 `db43278`（命名 v3 + 元数据 + 身份还原）**：06 · 09 · 20 · 22 · 23 · 24 · 28 · 30 · 31 · 32 · 33 · 37 · 39 · 43 —— 全 PASS。要点：构造器拒 task（多传即 fail loud）/ `role[2-9]` 槽位 / sidecar 原子写与孤儿清理 / app 双标签 `nao.name`+`nao.task` / `close --task` 元数据匹配（0 命中=未运行、>1=不猜）/ 旧形只读兼容（`role(task)` 不复活为写入面）。
- **Step 1 覆盖补齐 `c65292e`**：06 · 28 —— 全 PASS（golden 13 条 + C3②/④/⑤ 变异负控已回位，见上节 md5/负控证据）。
- **Step 2 `13676a2`（门面中性化）**：06 · 22 · 28 · 29 · 30 · 31 · 32 · 33 · 40 · 43 · 44 · 45 —— 全 PASS。要点：`term_snapshot` 5 列语义（status/cwd/handle/task，无身份整行省略）/ 放置面四函数（业务层 0 处 `_TERM_PLACE_*`）/ 业务层静态闸 0 命中 + 注入必红 / `check` 前提走门面 / 真机整轮 herdr（33）与 app 后端（44/45）不退化。
- 合并矩阵（去重后 18 例）与全量 47 例**无冲突**：全量跑次包含全部目标例，单跑用于逐任务归因（不重复造桩、不一步一测）。

## 四、未覆盖项与理由（无则显式写「无」）

1. **桌面 app 的视觉/UI 呈现**：本批无 UI 呈现变更（机制/终端 CLI 与门面契约），不适用；`cases/44/45` 覆盖 app 后端的**行为**（放置/读回/回滚/就绪/回收）与真 `hc` 私有 core 往返，不含视觉验收。
2. **`npm publish` 与 registry 落地核验**：属发布动作（用户执行），不在测试批次；发布时按 AGENTS.md「npm 发布成功判据」直连 registry 核验 integrity。
3. **tmux 后端面**：ADR `2026-11-22-herdr-only` 已退役，结构性不可达（`NAO_TERMINAL=tmux` ⇒ rc=2 已有 fail-loud 断言）。
4. **`cases/44` ⑪ 真 hc 收尾的 effect 断言**：当前只有「尽力 stop」没有 effect 判据 ⇒ D1 逃逸。属**已知缺陷**（已登记），不作为本批放行依据。

除上述外：**无**因能力缺失而跳过的用例（SKIP=0 / DEGRADE=0，`test:t4:full` 亦为 0）。

## 五、缺陷（详见 `docs/reports/572-defects.md`）

- **D1（P2 · 一般 · New）**：`tests/t4/cases/44-app-backend.sh:379` 用 `hc server kill` 收尾真 hc 私有 core，但 `hc 0.1.22` 的 `server` 子命令只有 `start/stop/status/restart` ⇒ `kill` 返回 `{\"error\":{\"kind\":\"usage\",\"message\":\"unrecognized subcommand 'kill'\"}}` rc=2，被 `|| true` 吞掉；**每跑一次 `cases/44` 泄漏 2 个 `herdr-core` 进程**（serve + holder），2/2 复现。同探针内 `hc server stop` ⇒ `{\"stopped\":true}` rc=0、监听归 0。建议修法：`kill`→`stop`，并补一条「stop 后该 `XDG_RUNTIME_DIR` 下监听 socket 数 == 0」的 effect 断言（判 effect 不看 rc）。

## 六、放行结论

- **放行**：`check` + `npm test` + `test:t4:full` 三门禁全 rc=0，SKIP=0 / DEGRADE=0 / NOTE 全白名单；Step 1 / 覆盖补齐 / Step 2 的目标用例全 PASS；`cases/28` 断言强度与 571 映射一致。
- **已知残留**：D1（测试夹具泄漏，P2）。不阻断 v0.33.0 发布（产品行为无关），但会随每次跑测试累积进程（本次实测历史累积 93 个），建议在同批或下一批修掉。
- **不代替合并权**：本报告只给质量结论；PR 由 RD 在 PM 验收后合并（本次不合并）。
