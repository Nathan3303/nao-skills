# t4 启动期陈旧缓存回收（#121 · M20261114-t4-cache）实现报告

- 状态：待验收 · 更新：2026-11-14 · Owner：rd-infra
- 指针：Issue [#121](https://github.com/Nathan3303/nao-skills/issues/121) · 上游口径 `docs/tasks-state.md`（PM 维护）· 用例 `tests/t4/cases/14-cache-lifecycle.sh`

## 结论（TL;DR）

- 目标：堵「SIGKILL ⇒ EXIT trap 不执行 + 起跑 sweep 只在下次运行」的空档，避免硬掐残留（实测单次 32M / 63 条）长期躺着。
- 做法：`source tests/t4/lib.sh` 时（run.sh 与各用例同一条路，**无第二处调用点**）回收 `$T4_CACHE_PARENT/nao-t4.*` 中「超过 6h **且** 无活进程关联」的目录；真清过才打印一行（条数 + 路径前缀）。
- 结果：AC1–AC6 全过；双后端 `npm test` rc=0（herdr 30 PASS + 2 TMUX-ONLY / tmux 32 PASS）；`check` rc=0 ×2 且输出逐字一致。
- 影响：只动 `tests/`（lib.sh / cases/14 / README）+ 本报告；`bin/`、`.agents/` 零改动，未碰 `docs/tasks-state.md`。
- 待办：PM 验收后由我执行 squash 合并；合并后随任务 PR 归档（本批不单独发版）。

## 改动

- `tests/t4/lib.sh`：新增 `t4_reclaim_stale_caches`（启动期回收）+ `_t4_cache_roots_in_use`（活进程判据：进程 env 的 `T4_CACHE_DIR=<dir>` 或 cwd 落在该目录下，只读 `/proc`）+ 删除单点 `_t4_rm_cache_dir`；`t4_cache_cleanup` 的删除语句改为复用该单点（行为不变）。
- `tests/t4/cases/14-cache-lifecycle.sh`：新增 ㉑–㉙ 共 19 条断言（双向判据 + 可观测 + 逃生口 + 跨轮 + 幂等）。
- `tests/README.md`：「夹具缓存纪律」补 1 条口径 + 用例 14 行描述。
- 边界：仅一层 `nao-t4.*`、是目录、非软链、**非本次使用的 `$T4_CACHE_DIR`**（用户传入的陈旧目录也不删）；未来时间戳不清；`stat` 缺失只 WARN 不猜。

## 判据与证据（AC）

- AC1 正控：8h + 无进程 ⇒ 启动期被清。证据：`cases/14` ㉑（探针 `source lib.sh` 后目录消失）。
- AC2 负控①：1h + 无进程 ⇒ 不清。证据：㉒、㉗（跨轮仍保留）。
- AC3 负控②：8h + 活进程（`T4_CACHE_DIR=<dir> sleep`）⇒ 不清。证据：㉓；㉗ 证明「释放活进程后下一轮即被清」（保留只因活进程）。
- AC4 语义零变（机械证据见下节）。
- AC5 门禁：`check` rc=0 ×2（`diff` 空）· 默认 herdr `npm test` rc=0（SKIP=0 / DEGRADE=0 / NOTE=9 全白名单 / PENDING=0 · 共享 20 + 专有 10 + tmux-only 2 = 32）· `NAO_TERMINAL=tmux npm test` rc=0（32 PASS，SKIP=0 / DEGRADE=0）。
- AC5 先红后绿：先写断言（回收未实现）⇒ 5 红（㉑ / ㉔×2 / ㉗×2）；实现后 `cases/14` 46 断言全绿。
- 失败演练（防「断言假绿」）：变异 A 丢时效判据 ⇒ ㉒/㉔/㉗ 红（1h 目录被误删）；变异 B 丢活进程判据 ⇒ ㉓/㉔/㉖ 红（活目录被误删）；还原后 `lib.sh` md5 `e3d2163c…` 复绿。
- AC6 约束：纯 shell、零新增外部依赖（只用已有 coreutils + `/proc`）、无后台守护、无重构；未动 `bin/`、`.agents/`。

## AC4「未变」的机械证据

- 起跑 sweep（孤儿）：`git diff 5503536..HEAD -- tests/t4/run.sh tests/t4/lib-backend.sh` = **0 行**；herdr 侧 `cases/27` 全绿（sweep ①–⑥）。
- `EXIT` trap：唯一代码改动是把 `rm -rf -- "$dir"` 换成共用单点 `_t4_rm_cache_dir "$dir"`（1 行，语义等价）；断言 ①–⑨（成功清 / 失败保留+rc 保真 / 用户目录不删 / 导出洞 / 前缀 / 软链）逐条不变全绿。
- `T4_KEEP_CACHE=1`：③④ 未改；新增 ㉖ 只**扩展**为「回收也整段跳过」（逃生口=一条都不删），已写入 `tests/README.md`。
- 用户传入目录：⑤⑥ 未改；新增 ㉕ 覆盖「用户传入的 8h 陈旧目录 + 内容也不删」。
- 静态契约 ⑳ 仍为 `1|1|0|0`（删除语句在 `tests/t4` 下仍唯一，且仍只在 lib.sh；run.sh 无 `rm`）。

## 边界与风险

- 活进程判据基于 `/proc`（Linux；本套用例早已依赖，非新依赖）。仅 `env T4_CACHE_DIR` 或 cwd 命中才算关联；别的机器/别的用户写的无进程遗留目录 6h 后会被清（这正是期望，且只限 `nao-t4.*` 形态）。
- 阈值 `T4_STALE_CACHE_HOURS`（默认 6，env-only）：测试用 `touch -d` 造 8h/1h，不依赖改阈值。
- 实测存量：改动前后 `/tmp/nao-t4.*` 均为 0 ⇒ 本批是「防下次」，起跑零输出（无噪声）。

## 回退

- `git revert 3dfc8da`（+ 本报告提交）即可；无状态、无迁移、无配置项残留（`T4_STALE_CACHE_HOURS` 不设即默认）。

- 修订：2026-11-14 初版（交付待验收）
