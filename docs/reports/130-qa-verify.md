# #130 闸调优（D1 stash 年龄阈值 / D2 `HERDR_*` 单源）—— QA 非作者复核

- 状态：复核完成 · 2026-11-15 · Owner：qa · 对象：分支 `nao/M20261115-gate-tune` @ `1414c37`（门禁 HEAD `9a59a8c`）
- 结论：**AC 全过，GO（末轮 D2⑩ 点检见文末）**；全批 P1=0 / **P2=2**（已修）/ P3=5（PM 提级的 P3①/②/③/⑤ 已修并点检）。
- 只读纪律：临时改动 2 处（lib.sh / cases/09）均还原，md5 前后逐字节一致（`e8c6ce1f…` / `10a477e2…`）；全程未 checkout/switch，未在真实仓造 stash（复核前后 `git stash list`=0，工作区干净）。

## P2（建议本批内修，或明确接受）

**P2-1 阈值前导零 ⇒ `check` 硬失败 rc=1（且合法前导零静默改义）**
- 复现：`NAO_STASH_ROOT=<临时仓，1 条 stash> NAO_STASH_WARN_HOURS=08 bash .agents/scripts/nao-fleet.sh check` ⇒ `rc=1`，输出止于
  `.agents/scripts/nao-fleet.sh: 行 1568: 08: 值对于底数而言过大`（仅 32 行，**无汇总行**）。`0008` 同；`06/007` 侥幸可用。
- 语义陷阱：`010` + 10h stash ⇒ 阈值 `10` 静默、阈值 `010` **warn**，但文案写「阈值 010 小时」（实际按 8h）。
- 根因：`[[ $hours =~ ^[0-9]+$ ]]` 放行前导零，`$(( hours * 3600 ))` 按八进制解释。方向：`hours=$((10#$hours))` 后再算，或正则拒绝前导零（按非法⇒立即 + 点名）；`cases/35` 补 H8/H9（`08` 不崩 / `010`==`10`）。
- 与报告冲突：报告称「非法值 ⇒ 按 0 处理、不崩」，前导零正是未覆盖的输入类。

**P2-2 `%ct` 取不到 ⇒ 零输出，与「无 stash」不可区分（闸门可被永久静默、`-v` 无痕）**
- 复现：PATH 前置 git 包装器，把 `stash list --format=%ct` 打成 `n/a`；同一条 9h stash：真 git `warnN=1`，包装器 `warnN=0`、`rc=0`、`-v` 无任何提示。
- 判断（PM 问「不 warn 是否掩盖真问题」）：**未来时间戳不 warn 是对的**（时钟回拨不可区分，误报会把 #130 病根带回来）；但**取不到 %ct 是能力缺失，可永久且无痕**，属「掩盖真滞留」 ⇒ 建议加一条 `  ·` 降级注记（只进 `-v`，不改 warn/rc），并补 `cases/35` 一条「%ct 不可解析 ⇒ 有降级注记」断言。

## P3（文档/覆盖度，不阻塞）

1. **红数对不上**：报告称删 `HERDR_SOCKET_FILE` ⇒ 4 条红；实测 **6 条**（D2② / D2⑤ / D2⑦×2 / **D2⑧×2**）。复现：`sed -i 's/ HERDR_SOCKET_FILE//' tests/t4/lib.sh && bash tests/t4/run.sh --case 06` ⇒ 6 FAIL；还原复绿。
2. **D2 只有静态面覆盖**：删 `HERDR_ENV`（生产确读它，3 处）⇒ **7 条红全在静态 golden，0 条行为红**（`be_fleet_handles` 在清理之后又注入句柄，渗漏不可观测）。建议补 1 条行为反渗漏断言：父进程给 `HERDR_PANE_ID=<非目标>` + 常规 herdr fixture `close` ⇒ 仍正常回收（丢该名字即红），顺带兜「herdr 新增 HERDR_* 未登记」。
3. **`BE_HERDR_KEEP` 逗号分隔不生效**（注释称「空格/逗号均可」）：实测 `HERDR_PANE_ID,HERDR_ENV` ⇒ 16 行（不豁免）；空格分隔 ⇒ 12 行 ✓。失败方向安全（全清），但实现与注释不符。
4. **AC3h③ 的「拒绝回收」是 8 处共用文案**：建议钉具体理由。实测理由确为自 pane（`判为调用者自身…`，且当轮「跳过状态闸门」）⇒ 非假绿；移除 `BE_HERDR_KEEP` ⇒ AC3h③ 3 条全红（自 pane 被回收）。
5. **`cases/33` 注释「枚举清 HERDR_*」与实际不符**（现为固定 8 名单源）⇒ 未来 herdr 新增 `HERDR_*` 不会被自动清，靠 golden「只增不减」纪律兜；建议改注释或写进风险。

## 已验通过（含复现口径）

**D1 双向 + 边界**（临时 git 仓 + `NAO_STASH_ROOT`，一律 rc=0）
| 场景 | 期望 | 实测 |
|---|---|---|
| 刚造 / 两条 fresh | 0 条 warn、摘要无 `warn=` | ✓ 0 / ✓ 0 |
| 8h 前 | 恰 1 条 + `warn=1` + rc=0 + 文案「最老一条 8 小时前 > 阈值 6 小时」 | ✓ |
| 8h+fresh（多条） | 以最老为准、仍 1 条、报真实条数 2 | ✓ |
| `pop` 后 | warn 消失 | ✓ 1→0 |
| 阈值 9 / 7（8h stash） | 静默 / warn | ✓ |
| 阈值 7 与 7h（边界） | 严格 `>` ⇒ 静默；阈值 6 ⇒ warn | ✓ |
| 阈值 `0` / `abc` / `-1` / 空 | 立即 warn（非法带「取值无效」）/ 默认 6 | ✓ |
| 未来时间戳（+2h，含阈值 0） | 不 warn、不炸 | ✓ |

**D2 独立复算**：`git show 9f028a5:` 四处手写清单（含 cases/09）并集 = 现在 `T4_HERDR_ENV_VARS` 8 个，`diff` 空；单源定义 1 处；`-u HERDR_*` 手写 0 行；副本加 `HERDR_QA_NEW` ⇒ 派生 18 args、调用点零改动 ✓。`BE_HERDR_KEEP` 部分名（`HERDR` / `HERDR_SOCKET` / `HERDR_PANE`）**不误保留**（16 行）✓。全仓扫「故意注入 HERDR_*」：仅 cases/09 经 `fx_fleet`（已豁免）；06/27/28/33 走显式 env 数组或 `be_run`，**无第 4 处被磨掉**。

**门禁**：`check` rc=0 **×2，两次逐字节一致**（`check: OK · roles=7 · files=54 · layout=main-row2`）· `npm run check:agents` rc=0 · `npm run test:t4:full:dual` rc=0（组1 tmux / 组2 herdr 各 34 例全 PASS，`SKIP=0 · DEGRADE=0 · NOTE=9/10`）· `cases/06`（265 断言）/`09`/`28`/`35` 两组均 PASS，golden 未破 · `cases/35` 自带真实仓 stash 前=后=0。敏感值扫描（7 文件）0 命中。

## 末轮点检（HEAD `709b397`，只点三项、未重跑全量）

**1) P2-1 三档 —— GO**（临时仓回填龄 9h / 11h）
- `08` ⇒ rc=0、**有 `check: OK` 汇总行**、warn=1、文案「阈值 8 小时」；`0008` 同；`010` ⇒ rc=0 静默（9h<10h），换成 11h ⇒ warn 且文案「阈值 10 小时」= `10` 逐字一致。三档均 rc=0（旧实现 `08` ⇒ rc=1，PM 已对照确认）。
- 先红后绿：删掉 `10#`（`hours=$((hours))`）⇒ `cases/35` **8 条红**（H8×3 / H9×4 / J7），还原复绿（md5 与 HEAD 逐字节一致）。

**2) P2-2 注记 —— GO（双向）**
- 假 git 把 `%ct` 打成 `n/a` + 11h stash ⇒ rc=0 / 0 warn / `-v` 一行「暂存滞留检查跳过：…不可解析（1 条 stash 仍在）」；**摘要模式仍是 3 行、无注记、无 `warn=`**（与干净态同形，不新增噪声）。
- 反向：无 stash + 假 git ⇒ **无注记**；真 git 同仓对照 ⇒ warn=1 且无注记。

**3) P3② 行为反渗漏 —— ①✓ ②✓ ③✗（已由 D2⑩ 补齐）**
- ① 断言对象 = **被测子进程真实 env**（桩 `env | grep '^HERDR_'`，经真实 `be_run_fleet`）✓。
- ② 删单源 `HERDR_ENV` ⇒ D2⑨ **行为红**（`期望=0 实际=1`，另 7 条静态红）✓。
- ③ 去掉 `BE_FLEET_NO_HANDLES=1` ⇒ **仍 PASS**（PM 预期红）。根因：bare 子壳未初始化 BE 上下文，`be_fleet_handles` 在 `lib-backend.sh:692` 报 `BE_BACKEND: 未绑定的变量` 即 return ⇒ 注入面本就为空，`NO_HANDLES` 在此**不承重**；这也说明「清理→注入」顺序当时无用例覆盖。
- **非空转替代证明**：删 `be_run_fleet` 的 `"${hu[@]}"` 整段 ⇒ D2⑨ 红（`0 vs 8`）⇒ 断言确在测清理本身，③ 的失败是**夹具上下文虚假**而非断言空转。

**SKIP 抖动判定**：`t4_skip` 计数口径下 SKIP 只能来自用例 02/07 的 pi 凭据 / npm registry 路径；本批 7 文件均未触及（改动面全在 `check` 与 t4 夹具清理）。本机 1 次完整 dual `SKIP=0` ⇒ 判**外部依赖瞬时不可达**，非本批引入（1 次为「判」，未做 2 次复跑取证）。

## 末轮点检 2（D2⑩ · HEAD `2931c06`）—— GO

- 基线：`cases/06` **285 PASS**（herdr 组 + `NAO_TEST_TERMINAL=tmux` 组各一次）；`check` rc=0（files=54）。
- 判据在位：① 8 条 `HOSTLEAK-*` **逐条钉值**（非计数）；② 钉实验场具体值（`HERDR_ENV=1` / `SESSION=d2h-fixture-sess` / `SOCKET_PATH` 落 `$T4_CACHE_DIR` 实验根）+ `NAO_TERMINAL=herdr` 且 `not tmux`；③ 无 `BE_BACKEND: 未绑定的变量`。
- 变异四连（各还原复绿，md5 与 HEAD 逐字节一致）：删 `"${hu[@]}"` ⇒ ① **5 红** / ②全绿 / D2⑨红；`be_fleet_handles return 1` ⇒ ② **5 红** / ①全绿；去掉 `BE_BACKEND`（上下文未初始化）⇒ ③ **红** + ② 5 红 / ①绿（③ 承重）；**语义顺序错（`env "${envs[@]}" env "${hu[@]}"`：进程正常起、`BE_RC=0`）⇒ ①绿 / ② 3 红** ⇒ 顺序面在「进程活着」时也能红。
- 父进程给定 `NAO_TERMINAL=tmux` **必要且正确**：实做「父改 herdr + 零注入」⇒ 两条 NAO_TERMINAL 断言**空转绿**。
- **RD 第三次变异：够格但弱** —— 它对应「argv 乱序」这一具体回归，但红因是 `env` 把 `-u` 当命令 ⇒ 子进程没起 ⇒ `BE_RC≠0`（大声失败），不证明「顺序错但进程仍起」会被抓。建议报告降级为「乱序 ⇒ loud-fail」＋ 以上语义顺序变异作顺序面证据（P3，不阻塞）。
