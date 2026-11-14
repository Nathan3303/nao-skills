# #121 QA 独立验证：t4 启动期陈旧缓存回收（维护型 M20261114-t4-cache）

- 状态：**PM 已裁定（2026-11-14）⇒ 本批退回 RD 修，暂不合并**（见 §八）· Owner：qa（不采信 RD 自证：夹具、变异、边界探针全部自建）
- 指针：Issue [#121](https://github.com/Nathan3303/nao-skills/issues/121)（唯一规格源）· 实现报告 `docs/reports/121-impl.md` · 被验对象 `fix/121-t4-stale-cache` @ `6b71942`（RD `3dfc8da` + PM 台账 `6b71942`）
- 定位：`codegraph` 无本批符号（新增 shell 函数不在索引语料）⇒ `grep -n` + `sed` 行段读 `tests/t4/lib.sh`、`tests/t4/cases/14-*.sh`、`tests/t4/run.sh`（红线注明回退原因：shell/文档非索引主体）

## 结论（首屏）

- **AC1/AC2/AC3/AC5/AC6 通过；AC4 在「非规范路径拼写」下有反例 ⇒ 现状建议先修 P1 再合并（NO-GO 待裁定，不自行改码）。**
- 门禁（独立）：`bash tests/t4/run.sh --case 14` rc=0 · **46 PASS / 0 FAIL**（与 PM 抽跑一致）；`npm test` rc=0 · **9m26s** · 32 例（共享 20 + 专有 10 + tmux-only 2）· SKIP=0 / DEGRADE=0 / NOTE=9 全白名单 / PENDING=0。tmux 组按 PM 口径采信 RD，未重跑（无风险理由见 §七）。
- 变异自做 2 次（丢时效 / 丢活进程）断言均**即时变红**，还原后 `lib.sh` md5 `e3d2163c…` 一致、`git status` 干净。
- 缺陷：**P1 一条**（归属守卫失效，违反 AC4 与本次 README 承诺）· **P2 一条**（活进程判据漏判，含 4 个症状）· **P3 四条**（不影响本批门禁）。两者同根因：判据用「原始字符串相等」比对未归一化路径。

## 一、独立夹具（不复用 `cases/14` 的 `probe.sh` 形态）

- 形态：不落盘探针文件，直接 `env -i … TMPDIR=<夹具> bash -c 'source lib.sh'` 走真实启动期路径；私有 `TMPDIR` 隔离，零依赖 tmux/tsx/registry。夹具脚本 `/tmp/qa121/harness.sh`（34 断言）· 缺陷最小复现 `/tmp/qa121/repro.sh`（6 条，`repro.log`）。
- 结果：AC1 正控（8h 无进程 ⇒ 清 + 打印「已清 1 个」+ 前缀）✔ · AC2 负控①（1h ⇒ 不清，跨轮仍不清）✔ · AC3 负控②（env `T4_CACHE_DIR` 或**仅 cwd** 命中 ⇒ 不清；释放后下一轮即清）✔ · 未来时间戳 `touch -d '+1 hour'` ⇒ 不清 ✔ · 同名普通文件 / 非 `nao-t4.*` 形态 / 父目录软链候选 ⇒ 不碰 ✔ · `T4_KEEP_CACHE=1` 整段跳过且无虚报 ✔ · `T4_CACHE_NO_CREATE=1`（preflight 路径）零副作用 ✔ · 并发两轮同时回收 rc 均 0 且全清（隔离 4/4 轮）✔ · 并发真跑 `lib.sh` 的批次持有该目录 ⇒ 不清 ✔。

## 二、变异自做（夹具自证「断言不假绿」）

- M1 丢时效判据（`stale+=(…)` 恒真）：`--case 14` rc=1，红 ㉒ / ㉔ / ㉗（1h 目录被误删）。
- M2 丢活进程判据（删 `grep -qxF` 分支）：rc=1，红 ㉓ / ㉔ / ㉖（活目录被误删）。
- 还原：`cp` 回滚后 md5 `e3d2163ce49108426ecfa2f9cb5a2daa` = 原值；`git status --short` 空（零残留改动）。

## 三、AC4 语义零变（机械证据）

- `git diff 5503536..HEAD -- tests/t4/run.sh tests/t4/lib-backend.sh` = **0 行**（起跑 sweep / 孤儿回收零改动）。
- `t4_cache_cleanup` 函数体 base↔HEAD 逐行比对（`5503536:lib.sh` vs HEAD）：**除删除语句外差异 0 行**；BR 判据集合逐个一致（BR3 · BR7 · BR4①–⑤ · BR9 按序全在），唯一代码差异 = `rm -rf -- "$dir" 2>/dev/null` 收进单点 `_t4_rm_cache_dir`（`2>/dev/null` 随之内移，stdout/退出码语义等价）。
- 删除面唯一性：`tests/t4` 下 `rm -rf -- "$var"` 形态仍**恰 1 处**（`lib.sh:51`），`run.sh` 无真 `rm`、无 glob 删除（⑲⑳ 静态契约 46 断言内全绿）。

## 四、范围裁定（有无夹带）

- `--numstat 5503536..HEAD` = 5 文件 +197/−10：实现 3 文件（`tests/t4/lib.sh` +74/−1 · `cases/14` +63 · `tests/README.md` +2/−1）+ RD 报告 `docs/reports/121-impl.md` +50 + PM 台账 `docs/tasks-state.md` 1/1（**仅** PM 自己的 `6b71942` 提交，`git log -- docs/tasks-state.md` 可证）。
- 禁改区：`bin/` **0 行**、`.agents/` **0 行**；纯 shell、无新增外部依赖（只多用既有 coreutils `stat` + `/proc`）、无后台进程。**未发现夹带。**

## 五、缺陷与风险（每项带复现）

- **P1 归属守卫失效：用户传入的目录在非规范拼写下被回收删除**（违反 AC4「用户传入目录不删」+ 本次 `tests/README.md` 自写承诺）
  - 现象：`T4_CACHE_DIR=<dir>/`（bash 补全的尾斜杠，或相对路径）时，`[ "$dir" = "${T4_CACHE_DIR:-}" ]` 字符串不等 ⇒ 该目录（若 mtime >6h）在**启动期被自己删掉**，用户为看 `case-<id>.log` 特意保留的失败缓存丢失。
  - 复现：`mkdir -p /tmp/x/nao-t4.mine; touch -d '8 hours ago' /tmp/x/nao-t4.mine; TMPDIR=/tmp/x T4_CACHE_DIR=/tmp/x/nao-t4.mine/ bash -c 'source tests/t4/lib.sh'` ⇒ 目录消失（`repro.sh` R4/R5）。
  - 建议：比对前对「候选 / 用户值」统一归一（`realpath -m` 或 `cd && pwd -P`），并补两条断言（尾斜杠、相对路径的用户目录不删）。
- **P2 活进程判据漏判（4 个症状，同一根因：字符串相等而非归一化 + 前缀匹配）**
  - (a) 活进程 env `T4_CACHE_DIR=<dir>/`（尾斜杠）⇒ 目录被删；(b) env 为相对路径 ⇒ 被删；(c) `TMPDIR` 经软链时仅 cwd 命中 ⇒ cwd `readlink` 是真实路径，与被扫候选拼写不同 ⇒ 被删；(d) env 指向缓存目录的**子目录** ⇒ 父目录被删。后果：删掉另一批**正在使用**的缓存（该批中途丢夹具/日志）。复现：`repro.sh` R1/R2/R3/R6（每条附「活进程仍在跑」前置）。
  - 建议：对候选、env 值、cwd 值统一归一后按「等于或为该目录前缀」比对；补 4 条负控断言。
- **P3-1** `_t4_cache_roots_in_use` 里 `[ -r "$d/environ" ] || continue` 先跳过，使 **cwd 判据依赖 environ 可读性**（environ 不可读的进程 cwd 永不参与判定）；建议 cwd 检查独立于 environ。
- **P3-2** 回收行写 stdout，真清过会出现在 `run.sh` 汇总前（本次全量 rc=0、无解析影响，`run.sh` 只按行首标记 + rc 计分）；CI 对输出做逐字比对时有噪声风险。
- **P3-3** `T4_STALE_CACHE_HOURS=0` 通过整数校验但语义≈全清（`now-mtime > 0`）；建议拒绝 0 或写明下限。
- **P3-4** 成本：存在陈旧候选时每次 `source lib.sh` ≈ **900ms**（10 候选 / 569 进程实测），无候选 47ms；32 例首轮最多 +30s，仅遗留期发生。

## 六、未做 / 采信

- tmux 后端组未重跑（PM 口径；本批改动只在 `tests/t4/lib.sh` 的启动期路径，与后端无关，且全量 herdr rc=0）；`check` rc=0 采信 PM（机制文件零改动，`bin/` `.agents/` numstat=0 已复核）。

## 七、回执

- `done(full)`：AC1–AC3/AC5/AC6 通过，AC4 有 P1 反例待裁定；本报告随任务 PR 提交（`wip(121): qa 复核报告`，仅本路径暂存）。

## 八、PM 裁定（2026-11-14，退回 RD 修，不合并）

- **P1 + P2 = 本批必改**（同一条根因：原始字符串相等 ⇒ 归一化 + 等于/前缀比对）。修完再派 QA 点检同四形态（尾斜杠 / 相对路径 / 软链 `TMPDIR` / 子目录）+ 一条「归一后仍不误删活目录」的正向证据。
- **P3-1（cwd 判据被 `[ -r environ ] || continue` 连带跳过）= 本批改**：判据解耦，cwd 分支不依赖 environ 可读。
- **P3-3（`T4_STALE_CACHE_HOURS=0`）≈ 全清 = 本批改**：0 视为非法阈值 ⇒ 跳过（与现有「非法阈值不猜」一致）+ 补一条断言。
- **P3-2（回收行写 stdout）= 接受**：与现有 info 口径一致，无解析依赖。
- **P3-4（有候选时启动 ≈900ms）= 接受**：仅在存在 >6h 候选时扫 `/proc`，稳态 47ms，记录在案。
- 报告载体：随任务 PR 走，不另开 QA 分支。

- 修订：2026-11-14 初版
