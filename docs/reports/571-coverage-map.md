# T571 用例覆盖映射（旧 cases/28 → v3 覆盖面）

- 更新：2026-11-25 · 分支 `test/571-coverage-map` · 基线 `db43278`（T571 已合并）
- 目的：v3 重写 `cases/28` 后，证明「断言强度不降」。旧文件 1982 行 / **325 条 `t4_assert`**；
  新文件 557 行 / **95 条 `t4_assert`**（另 C1 子进程 28 条 `chk`）。少掉的 230 条按组归口如下。

## 组级映射（旧 325 条）

| 旧组（`/tmp/old28.sh` 行段） | 旧 `t4_assert` | 新覆盖位置 | 处置理由 |
| :-- | --: | :-- | :-- |
| C1 子进程纯函数（62–146，另 21 `chk` + 表循环） | 0 | 新 `cases/28` C1（28 `chk`） | v3 构造/解析/合法名重写；v2 `role(task)` **写入表**随 v3 删除（只读解析保留） |
| C1 父进程正控 + M1–M4（147–208） | 3 | 新 `cases/28` C1 父进程 + **M1–M4** | 4 条变异负控全保留（M4 = 非法 legacy scope 放行） |
| C3 单写点 lint（209–381） | 20 | 新 `cases/28` C3①–⑤（12 条正控 + **14 条负控**） | C3② 名字拼接 / C3④ 放置键 / C3⑤ server 身份读取的变异负控全部补回（判据删掉即必红） |
| C2 tmux golden / 基线 fixture（382–450） | 3 | **退役**（T555 `2026-11-22-herdr-only`） | 基线 fixture 只认 tmux（本版 `NAO_TERMINAL=tmux` ⇒ rc=2），无对照对象；herdr golden 见下 |
| B1 herdr status / golden / 默认值（451–675） | 43 | 新 `cases/28` P2① golden（13 条）+ herdr 元数据（24 条）+ `cases/30/31/32/40/43` | status 四档非在线证据/空 label/缓存/T555 反向断言分属上述用例；golden + 默认值反向断言**本批补回** |
| B2 herdr 放置/在线/就绪/迁移（676–1325） | 101 | `cases/29/30/31/32/33/40/43/44/45`（+ 新 `cases/28` 元数据 24 条） | 同一后端契约的专门用例；v3 只改名字/元数据，不改放置算法 |
| B3 herdr close/cleanup（1326–1982） | 155 | `cases/37/38/15/13/41`（+ 新 `cases/28` close --task 断言） | 忙闲/self/effect/守卫/歧义已在专门用例；v3 只把 task 匹配从名字改为元数据 |

合计：325 条 = 0 + 3 + 20 + 3 + 43 + 101 + 155。

## 本批补回的两项（旧 402–414 / B1①）

新 `cases/28` 的 `P2① herdr golden + 默认值反向断言`（13 条 `t4_assert`）：

1. 显式 `NAO_TERMINAL=herdr` ⇒ `status` rc=0，输出含 herdr 专有头行；golden `4b7f47b2…` 与记录值逐字相等。
2. 未设 `NAO_TERMINAL`（同一夹具）⇒ rc=0 且 **md5 == 显式 herdr golden**（默认值唯一）。
3. 未设 golden **≠ 冻结的旧 tmux golden** `144f3447…`。
4. 反向负控：未设 + `HERDR_*` 全缺 ⇒ rc=3 + 点名 `HERDR_ENV=1 缺失`（不静默回落）。
5. 变异自证 + 先红后绿：副本把默认改回 `tmux` ⇒ 未设 rc≠0 且 md5 ≠ golden；复原后复绿。

## C2 基线 fixture 现状

`tests/t4/fixtures/nao-fleet-baseline-2692b42.sh` **已无任何用例引用**（仅历史注释/报告提及）。
T555 已按 ADR 退役 tmux golden 组；本批不删除历史 fixture（保留取证），但**不再作为判据**。

## 门禁

- `bash tests/t4/run.sh --case 06` → PASS
- `bash tests/t4/run.sh --case 28` → PASS（**95 条 `t4_assert`** + C1 28 `chk`）
- 全量 `npm test`（47 例）→ PASS · SKIP=0 · DEGRADE=0 · NOTE=17（全白名单）
- 演练：golden 记录值改错 ⇒ P2① 必红；默认改回 tmux ⇒ P2① 必红；C3②/④/⑤ 注入违规 ⇒ lint 必红（均固化在 case 28）。
