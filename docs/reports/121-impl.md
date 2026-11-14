# t4 启动期陈旧缓存回收（#121 · M20261114-t4-cache）实现报告

- 状态：待验收（二轮修已交付，待 QA 点检）· 更新：2026-11-14 · Owner：rd-infra
- 指针：Issue [#121](https://github.com/Nathan3303/nao-skills/issues/121) · QA 复核 `docs/reports/121-qa-verify.md` · 上游口径 `docs/tasks-state.md`（PM 维护）· 用例 `tests/t4/cases/14-cache-lifecycle.sh`

## 结论（TL;DR）

- 目标：堵「SIGKILL ⇒ EXIT trap 不执行 + 起跑 sweep 只在下次运行」的空档，避免硬掐残留（实测单次 32M / 63 条）长期躺着。
- 做法：`source tests/t4/lib.sh` 时（run.sh 与各用例同一条路，**无第二处调用点**）回收 `$T4_CACHE_PARENT/nao-t4.*` 中「超过 6h **且** 无活进程关联」的目录；真清过才打印一行（条数 + 路径前缀）。
- 结果：AC1–AC10 全过；双后端 `npm test` rc=0（herdr 30 PASS + 2 TMUX-ONLY / tmux 32 PASS）；`check` rc=0 ×2 且输出逐字一致；`cases/14` 71 断言全 PASS。
- 影响：只动 `tests/`（lib.sh / cases/14 / README）+ 本报告；`bin/`、`.agents/` 零改动，未碰 `docs/tasks-state.md`。
- 待办：QA 点检通过 + PM 授权后由我执行 squash 合并（本批不单独发版）。

## 改动

- `tests/t4/lib.sh`：新增 `t4_reclaim_stale_caches`（启动期回收）+ `_t4_cache_roots_in_use`（活进程判据）+ `_t4_realpath`（路径归一单点）+ 删除单点 `_t4_rm_cache_dir`；`t4_cache_cleanup` 的删除语句改为复用该单点（行为不变）。
- `tests/t4/cases/14-cache-lifecycle.sh`：新增 ㉑–㊵ 共 44 条断言（首轮 19 + 二轮 25）。
- `tests/README.md`：「夹具缓存纪律」补口径一条 + 用例 14 行描述。
- 边界：仅一层 `nao-t4.*`、是目录、非软链、**非本次使用的 `$T4_CACHE_DIR`**（用户传入的陈旧目录也不删）；未来时间戳不清；`stat`/`realpath` 缺失或阈值非法只 WARN/跳过，不猜。

## 判据与证据（AC）

- AC1 正控：8h + 无进程 ⇒ 启动期被清。证据：㉑（`source lib.sh` 后目录消失）。
- AC2 负控①：1h + 无进程 ⇒ 不清。证据：㉒、㉗（跨轮仍保留）。
- AC3 负控②：8h + 活进程（`T4_CACHE_DIR=<dir> sleep`）⇒ 不清。证据：㉓；㉗ 证明「释放活进程后下一轮即被清」。
- AC4 语义零变（机械证据见下节）。
- AC5 门禁：`check` rc=0 ×2（`diff` 空）· 默认 herdr `npm test` rc=0（30 PASS + 2 TMUX-ONLY · SKIP=0 / DEGRADE=0 / NOTE=9 全白名单 / PENDING=0）· `NAO_TERMINAL=tmux npm test` rc=0（32 PASS，SKIP=0 / DEGRADE=0 / NOTE=9）。
- AC5 先红后绿：首轮断言 5 红（㉑ / ㉔×2 / ㉗×2）；二轮断言 13 红（见下节）；修后 71 断言全绿。
- AC6 约束：纯 shell、零新增外部依赖（只多用已有 coreutils `stat`/`realpath` + `/proc`）、无后台守护、无重构；未动 `bin/`、`.agents/`。

## 二轮修（QA NO-GO：P1/P2 同根因 ⇒ AC7–AC10）

- 根因：归属守卫与活进程判据都用「原始字符串相等」⇒ 尾斜杠 / 相对路径 / 软链拼写 / env 指向子目录均误判（QA P1 + P2 四症状）。
- AC7 归属守卫：两侧先 `realpath -m` 归一（`_t4_realpath` 单点）再判等 ⇒ 三种拼写的用户目录都不删（㉚ 尾斜杠 / ㉛ 相对路径 / ㉜ 软链拼写）。
- AC8 活进程判据：归一后按「**等于 或 在其下**」比对（env 指向缓存子目录也算在用），四个症状各一条（㉝ env 尾斜杠 / ㉞ env 相对 / ㉟ 软链 `TMPDIR` 仅 cwd 命中 / ㊱ env 子目录）；env 相对值按**该进程自己的 cwd** 解析。
- AC9 判据解耦：`_t4_cache_roots_in_use` 的 cwd 分支**先于** `[ -r "$d/environ" ]` 门（旧写法先跳过 environ ⇒ cwd 永不参与）。证据：㊲ 静态顺序断言（cwd 行 5 < environ 门行 11）。
- AC10 阈值：`T4_STALE_CACHE_HOURS=0`（≈全清）与非整数一律视为非法 ⇒ 跳过；证据：㊳ 目录保留 + 无回收输出。
- 先红后绿（二轮）：未修实现时 13 红 —— ㉚×2 · ㉛×2 · ㉜×2 · ㉝ · ㉞ · ㉟ · ㊱ · ㊲ · ㊳×2；修后 71 断言 PASS。
- QA 复现脚本 `/tmp/qa121/repro.sh` 六条（R1–R6）现在全部输出「安全：未删」。
- 失败演练（二轮，还原后 `lib.sh` md5 `36abec7b…` 复绿）：M4 删 env 前缀判据 ⇒ ㊱ 红；M5 归一退化为恒等 ⇒ ㉜/㉟ 红（软链拼写必须真归一）；M6 把 environ 门提回 cwd 之前 ⇒ ㊲ 红。
- 诚实边界：归属守卫与活进程判据**互为兜底** —— 单把归属守卫退回原串判等（M3）不翻红，因为活进程判据归一后同样保护用户目录（本进程 env 持有 `T4_CACHE_DIR`）；二者同时不归一（M5）才暴露。不为凑「单判据证据」改测试。

## AC4「未变」的机械证据

- 起跑 sweep（孤儿）：`git diff 5503536..HEAD -- tests/t4/run.sh tests/t4/lib-backend.sh` = **0 行**；herdr 侧 `cases/27` 全绿（sweep ①–⑥）。
- `EXIT` trap：唯一代码改动是把 `rm -rf -- "$dir"` 换成共用单点 `_t4_rm_cache_dir "$dir"`（1 行，语义等价）；断言 ①–⑨（成功清 / 失败保留+rc 保真 / 用户目录不删 / 导出洞 / 前缀 / 软链）逐条不变全绿。
- `T4_KEEP_CACHE=1`：③④ 未改；新增 ㉖ 只**扩展**为「回收也整段跳过」（逃生口=一条都不删）。
- 用户传入目录：⑤⑥ 未改；㉕（首轮）+ ㉚/㉛/㉜（二轮三种拼写）覆盖「陈旧 + 非规范拼写也不删，内容保留」。
- 静态契约 ⑲⑳ 仍为 `1|1|0|1` / `1|1|0|0`（定义单点、删除语句在 `tests/t4` 下仍唯一且只在 lib.sh）。

## 边界与风险

- 活进程判据基于 `/proc`（Linux；本套用例早已依赖，非新依赖）。只有「env 命中候选或其下」与「cwd 落在候选下」两种关联；其它机器/用户的无进程遗留目录 6h 后会被清（期望行为，且限 `nao-t4.*` 形态）。
- 阈值 `T4_STALE_CACHE_HOURS`（默认 6，env-only；0/非整数 ⇒ 跳过）：测试用 `touch -d` 造 8h/1h，不依赖改阈值。
- 成本（QA P3-4 接受）：稳态 `source lib.sh` 62–67ms（本机 633 进程）；存在 10 条 8h 候选时**首轮**约 1.7s（`/proc` 全扫），清完即回落 —— 每批只发生一次（第一个 `source` 清空后，后续用例走稳态）。
- 实测存量：改动前后 `/tmp/nao-t4.*` 均为 0 ⇒ 本批是「防下次」，起跑零输出。

## 回退

- `git revert 3dfc8da 5099225 <二轮 sha>` 即可；无状态、无迁移、无配置项残留（`T4_STALE_CACHE_HOURS` 不设即默认）。

- 修订：2026-11-14 二轮修（QA P1/P2/P3-1/P3-3 ⇒ AC7–AC10；先红后绿 + 三次变异演练）
