# 实现记录 · T594 仓库改名（PM 摘录自 RD 回执与 PR #263）

- 任务：**T594** · Issue [#262](https://github.com/Nathan3303/nao-fleet/issues/262) · PR [#263](https://github.com/Nathan3303/nao-fleet/pull/263)（squash `794c570`）
- 角色：`rd-infra` 实现 · `qa` 独立复核（GO，含三处变异负控与脱网复跑）· PM 验收

## 改动面

50 文件 **+522/−427**：包名与仓址、CI base、全仓文本（40 文件 / 617 处）、env 与 bin 两个兼容层、`cases/{07,17,20,24}` 跟改、示例 pin 订正。

## 关键判据（QA 独立复核，生产形态 env）

- 全量：46 例 · **45 PASS / 1 FAIL**（仅 case 32 环境红，`origin/main` 同红 / #245）· SKIP=0 · DEGRADE=0 · NOTE=18 · PASS 行 2697
- **锚点主名**：基线 PASS → 主名/别名互换 ⇒ `case 17/20/24` 全红且点名 → **只删别名片段（保留主名）⇒ 全绿**（证明断的是主名而非整行等值）→ 撤销复绿
- **`case 07` 零网络**：脱网 env 下 `--case 07` rc=0 且 `^SKIP:` 命中 0；`T4_REQUIRE_FULL=1` 单跑 rc=0；`Installed npm:nao-fleet@file:/tmp/…tgz`
- **双 env 对照**：`NAO_FLEET` 与 `NAO_SKILLS` 各跑 `check` ⇒ md5 相同；优先序反转 ⇒ 必红
- **历史未改写**：`docs/tasks-archive.md` +256/−256，剥掉四个名字 token 后逐字相同，sha / Issue / PR 多重集不变
- **冻结目录**：`docs/{prds,reports,adr,designs,research,releases}` 0 行 diff

## 三处值得留档的坑（本批发现）

1. **扩展里有一份锚点行副本**：`.agents/extensions/nao-role-agents.mjs` 的 `buildAnchorLine` 自带一份，只改 `ensure.sh` 仍红 —— 同一事实两处派生。
2. **脱网装包的正确形态**：`pi install -l --approve "npm:<pkg>@file:<tgz>"`；裸 tgz 路径或 `file:` 前缀都**不物化**。
3. **文档 pin 指向不存在的版本**：机械替换把示例改成 `nao-fleet@0.30.0`（新包从 0.37.0 起）⇒ README 第一步就装不上，任何测试都不会红。

## 发布

- 0.37.0（MINOR）：改名 + env/bin 别名 + 站点图标与首页动画收边（T590 / T587 追加）
- `npm publish nao-fleet` 由用户执行（无 scope 包名先到先得）；PM 按唯一判据核验后回填
