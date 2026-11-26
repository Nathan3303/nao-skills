# T572 实施报告：门面契约中性化（Step 2）

- 分支 `feat/572-facade-neutral` · 基线 `c65292e`（T571 + 覆盖映射已合并）
- ADR：`docs/adr/2026-11-25-term-facade-neutral-contract.md` 决策二
- 覆盖基线：`docs/reports/571-coverage-map.md`

## 逐件

1. **`term_snapshot` 5 列**：`<name>\t<status>\t<cwd>\t<handle>\t<task>`；`status ∈ alive|working|idle|unknown`；
   `cwd` = 归属 cwd；`handle` 不透明；`task` 无则 `-`；无身份整行省略；失败 rc=1 + 零 stdout。
   后端私有 13 列事实保留在 `_term_*_facts`（`_term_facts` 每命令缓存），业务层不可见。
2. **`term_ws_label_rows`**：`<space_ref>\t<label>`；空 label 省略；后端不可用 rc=0 + 零行。
3. **放置面**：`term_place_begin/end/rows/ws_for_label` 替换 `prime/reset`；`ensure` 改用
   `term_place_rows` 业务缓存 + `term_place_ws_for_label`；业务层 0 处 `_TERM_PLACE_*`。
   T569 caller-space 复用仍在 app 后端内部。
4. **`term_liveness`**：签名/4 字段不变；实现改读 `_term_facts`（不再从公共 5 列反推）；
   `term_session_name` 语义写死为诊断句柄（不改）。
5. **`check.sh:585`**：改走 `term_api_schema`；app 前提走 `term_check_premise`（check 内 0 处 `_term_herdr_exec` / `_term_app_*`）。
6. **静态闸 + 用例**：`t4_scan_business_backend_words` 扫描 7 个业务模块（注释/字符串先剔除），
   case06 双向负控 + 删词演练；case28 5 列契约/golden/元数据；30/31/32/33/40/43/44/45 重跑。

## 函数清单

Step 1 后 185 → **200**：
- 删 8：`term_place_prime/reset` · `_term_backend_snapshot` · `_term_herdr_snapshot` · `_term_app_snapshot` · `_term_herdr_place_prime/reset` · `_term_app_place_prime`
- 增 23：`term_place_begin/end/rows/ws_for_label`（4）· `term_api_schema`/`term_check_premise`（2）·
  `_term_backend_facts/project5`/`_term_facts`（3）· `_term_herdr_facts/project5/place_begin/end/rows/ws_for_label`（6）·
  `_term_app_facts/project5/place_begin/end/rows/ws_for_label`（6）· `_ensure_place_load`（1）· `_term_place_ws_fields`（1）
- `cases/06` 三向计数同步为 200。

## 与 571 覆盖映射的对照

- C1/C2/B1/B2/B3 组仍由原用例承重；本批只改**消费快照/放置**的断言：
  - `cases/28`：快照阅读改为 5 列语义（status/task/cwd），golden 与默认值反向断言保留；app/herdr 元数据断言不变。
  - `cases/30/31/32/33/40/43`：依赖 `term_snapshot` 的地方改为 5 列（cwd/handle/task），断言条数不减；
    S13「他仓同名」不再承诺 `ws=<label>`（5 列契约不再暴露 workspace），只保留计数（case40 原断言只查子串）。
  - `cases/44/45`：app 端前提静态断言改点名 `term_check_premise`（门面），不放宽 warn-only。
  - `cases/06`：函数数 200 + T572 静态闸/演练。
- 删除的断言只有「Step 2 契约不再暴露的后端形状」：`workspace_id` 列读取、`pane_id` 作为业务句柄名；替换为 `space_ref`/`handle` 中性面。

## 失败演练（case06 T572 块，均固化）

1. `term_snapshot` 内投影调用替换为 `_term_backend_facts`（5 列退回 13 列）⇒ 投影判据 0 命中（真件 1）。
2. 业务模块注入 `pane_id` ⇒ 静态闸必红；删判据里的 `pane_id` 词 ⇒ 同一违规不再命中（判据承重）。
3. 恢复 `check.sh` 直连 `_term_herdr_exec` ⇒ 静态闸必红；真件 0 处直连、schema 走 `term_api_schema`。
4. 删静态闸函数 ⇒ `type` 存在性断言必红；删任一禁止词 ⇒ token 存在性断言必红。

## 临时文件

`_TERM_SNAP_PATH` / `_TERM_FACT_PATH` 均进 EXIT trap；另保留 `find -mmin +120` 清扫（异常退出残留）。

## 门禁

- `check` rc=0 · roles=7 · files=67
- 全量 `npm test`（47 例，干净 TUI 宿主）：PASS=47 · FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=17（全白名单）
- 目标用例单跑：06/28/30/31/32/33/40/43/44/45 全 PASS。
