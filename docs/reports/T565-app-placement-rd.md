# T565 / Issue #175 —— app 后端「放置验证失败」根因与修复（rd-infra）

> 关联：PRD `docs/prds/175-app-placement.md`（PM）· 派单 T565 · 分支 `fix/175-app-placement`（起点 `main@1567991`）
> 范围：`.agents/scripts/nao-fleet.sh` + `tests/t4/**`（新增 `cases/45-app-placement.sh`、扩 `fixtures/hc-double`）

## 一、现象（用户实机，PM 已核，本文不重复取证）

`NAO_TERMINAL=app ensure pm` ⇒

```
放置验证失败：终端 t10 不在目标 tab 的 root 树里（space=sp89c3534f… tab=tb3c2b28…）⇒ 回滚（kill → rm）
```

同机 `herdr-app status` rc=0（窗口在跑）、`check -v` 全绿但 app 端前提只校验了 pi 版本、回滚干净无孤儿。

## 二、根因（两条，都成立，互不替代）

### B（主因）：app 收养是异步的，代码却「写完立刻验」

厂方 app 的内嵌文档（`strings /usr/bin/herdr-app`，原文，本机 v0.1.16）说得很清楚：

- 「A terminal with those labels shows up there… Adoption also enables core keep.」
- 「When a core change is needed, `terminal.keep` / `terminal.park` acknowledge with `pending: true`,
  then apply after the machine replies; failures show a toast.」
- 「An id Herdr doesn't know becomes a new space or tab (unnamed: Herdr's names).」

即：写 `herdr.space`/`herdr.tab` 只是**请求**，app 侧走 pending → 由 core 回复后才落库。
T562 的实现是「`hc run` 返回后**一次** `doc.get` 定生死」⇒ 窗口在跑但落库还没完成时必然读到「终端不在目标 tab」，
于是回滚（而回滚本身是对的，判定时刻错了）。

### A（次因）：沿用了「陈旧标签」里的 space id，放置前不校验它是否还在 doc 里

`_term_app_place_prime` 旧逻辑：doc 里查不到某终端的 space id 时，**拿该终端的 cwd 兜底**把它塞回
`sid_folder` ⇒ 这个「app 重启后已不存在」的 id 被当成「本仓的 space」复用。而 app 不认识的 id 由 app
**自己新建**（厂方文档上一行），请求的旧 id 就无处可去 ⇒ 同样是「终端不在目标 tab」，且现象与 B 长得一样。

> 结论：只加轮询不够（会从「立刻假失败」变成「5s 后照样假失败并沿用脏 id」）；只校验 doc 也不够
> （异步落库仍会假失败）。两处一起改才闭合。

## 三、改动

`.agents/scripts/nao-fleet.sh`（app 臂内，全部经唯一入口 `_term_app_exec`）：

1. **AC1 放置前校验 doc**：`_TERM_APP_DOC_SPACES` 由 `doc.get` 的 S 行独占填充；
   `sid_folder` 不再从终端标签兜底；不在 doc 的 space id 只做一件事 —— 一条 warn（`陈旧放置标签…`），
   然后由 `_term_app_mint_fresh_space` 现算一个 **doc 里不可能有的** id 交给 app 创建。
   退役 `_term_app_mint_space`（= hash(repo)，跨重启稳定 ⇒ 重启后拿到的仍是旧 id，与 AC1 冲突）。
2. **AC2 有限轮询**：`_term_app_poll_place`，默认 **10 次 × 0.5s**（`NAO_APP_ADOPT_TRIES` /
   `NAO_APP_ADOPT_INTERVAL` 可覆盖；非法值回落默认并 warn；0 轮被拒），轮询期间**只读 doc**，
   `hc run` 全程只发一次。
3. **AC3 分类报因**：`_term_app_verify_place` 记录 `no-space` / `no-tab` / `no-term` / `doc-fail`，
   回滚前分三句说清：目标 space 不存在（app 重启后 id 会变化）· 目标 tab 不存在 · 收养超时
   （带**实际** N×间隔）。
4. **AC4 check 前提 warn-only**：`_term_app_check_premise` 不再提前 return、缺项一律累加并补一行
   「仅提示，**不计入 rc**」；`cmd_check` 两处调用点都 `|| true`。新增 `_term_app_context`：
   **在 app 终端内但 `NAO_TERMINAL` 未设**（用户实机形态）时也体检 app 端前提（herdr-app 在 PATH /
   status rc=0 / doc 可读），且不改「生效后端」那行（不谎报）。

`tests/t4/**`：

- 新增 `cases/45-app-placement.sh`（7 组断言，见下）；`run.sh` 登记（替身重档）。
- `fixtures/hc-double/hc` 新增四个观测面旋钮：`stale_ids`（app 不认的 id ⇒ 自己新建，真 app 行为）、
  `adopt_delay=N` / `adopt_never`（tab 已建、终端未挂进 root 树的 pending 态）、`space_refuse`。
- `cases/06` 的默认值探针白名单 += `45`（该例确实需要「app 终端内 NAO_TERMINAL 未设」这条未设路径）。

## 四、先红后绿（同一夹具，两侧日志）

复现台：`/tmp/t565/repro.sh <nao-fleet.sh>`（预置「陈旧 space 标签 + app 不认该 id」夹具，跑 `ensure rd-fe`）。

| 侧 | 脚本 | 结果 | 日志 |
| --- | --- | --- | --- |
| 红 | `main@1567991` 的 `nao-fleet.sh` | rc=1，`放置验证失败：终端 t2 不在目标 tab 的 root 树里（space=spstale… tab=…）⇒ 回滚（kill → rm）` | `/tmp/t565/red-repro.log` |
| 绿 | 工作区修后脚本 | rc=0，`陈旧放置标签…⇒ 不沿用该 id` + `[app] 已拉起 rd-fe`，新终端 `space=spefdd8e…`（≠ 陈旧 id） | `/tmp/t565/green-repro.log` |

红侧那句与用户实机**同句同形**（只有终端号/ID 不同），可判定复现的不是「别的失败」。

## 五、AC 逐条证据（`cases/45` 断言 → 命令输出）

- **AC1**：① 「目标 space 在 doc ⇒ 复用 doc 的 id」+「space 数仍为 1」；② 「陈旧 id 不再沿用 ⇒ rc=0」
  「终端不用陈旧 space id」「陈旧 warn 恰 1 行」「终端确实落在 doc 的 tab 树里」。
- **AC2**：④ 「收养延迟 2 次读回（默认 10×0.5s）⇒ rc=0」+「`hc run` 恰 1 次」+「终端在目标 tab 树里」；
  负控「`NAO_APP_ADOPT_TRIES=1` ⇒ 同一夹具必红」。
- **AC3**：③ 「目标 space 不存在」+「app 重启后」+「不出现收养超时」（两句不同）；
  ⑤ 「收养超时」+「报错带实际参数 3×0.1s」+「不出现目标 space 不存在」+ kill→rm 顺序 + 无孤儿。
- **AC4**：⑥ 摘要 `warn=1` 且 rc=0（不计入 rc）；`check -v` 点名「窗口未在运行」+「仅提示，不计入 rc」；
  窗口在跑时**无**该项（判据不空转）；`hc` 不在 PATH 有一行指路；app 终端内 `NAO_TERMINAL` 未设也体检；
  非 app 环境零新增输出（负控）。
- **AC5/先红后绿**：见上表 + ⑦ 两向变异自证。

## 六、断言射程自证（变异必须红）

`cases/45 ⑦` 现场生成两份变异副本（锚点必须**恰 1 次**命中，否则断言红）：

1. 把 `! _term_app_doc_has_space "$sp"` 改成 `false`（拆掉 AC1 文档校验）⇒ ②场景必红，且报错里带着**陈旧 id**
   （`space=spstale…`）—— 证明「陈旧 id 不沿用」这条判据是它单独抓的。
2. 把 `_term_app_poll_place …` 换成单次 `_term_app_verify_place …`（拆掉轮询）⇒ 收养延迟夹具必红
   （「收养超时」）—— 证明 ④ 的绿不是别的原因救的场。

## 七、门禁（本机实数）

- `bash .agents/scripts/nao-fleet.sh check` ⇒ rc=0（`roles=7 · files=53`）
- `bash tests/t4/run.sh --case 45` ⇒ `RESULT: PASS`（0 FAIL / SKIP=0 / DEGRADE=0 / NOTE=0）
- 相邻面：`--case 44`（app 后端全量）、`--case 06`（契约/默认值探针）、`--case 28`（命名 golden）、
  `--case 34`（端前提 warn）、`--case 43`、`--case 41`、`--case 22/23/29/33` ⇒ 全 PASS
- `bash tests/t4/run.sh --fast` ⇒ rc=0（快档 14 例；未覆盖面按 run.sh 自述：含 45）
- `codegraph sync` ⇒ Already up to date

> 全量 `npm test`（39 例）按派单留在 PM 合并前跑；本回执不宣称全绿。

## 八、风险 / 边界（显式）

1. **真 app 的 UI 效果仍属人工验收**（与 T562 同口径）：替身只模拟观测面（doc/labels/时序）。
   本机 `hc`/`herdr-app` 在位，但把终端建进用户桌面窗口不可自动化 ⇒ 未在真机复跑该场景。
2. **默认 5s 上限**（10×0.5s）是折中：慢机 / 远程 core 可用 `NAO_APP_ADOPT_TRIES` 放宽；
   超时仍然是回滚 + 分类报因（不会静默成功）。
3. **陈旧标签不会被清理**：只「不沿用」。旧 space 里的残留终端与空 space 仍留在 app 布局里（用户可见），
   本批不动别人的布局（避免误删用户在用的空间）。如需要，另立清理项。
4. `docs/**` 除本报告外未改（PM 边界）；`README.md` / `package.json` / `.agents/prompts/**` 未碰。
