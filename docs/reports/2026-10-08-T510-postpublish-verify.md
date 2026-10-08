# 发布后核验：v0.12.1 + v0.13.0（2026-10-08 · PM 执行）

> 触发：T509/T510 发布（用户执行 npm publish）→ PM 发布后核验
> 结论：**通过**（两版产物与本地 tag 逐字节一致 · 真实安装可用 · 两处修复行为已实测）
> 边界：1 项新增记录（D7，见 §5），非缺陷

## 1. registry 终态

| 项 | 值 |
| :--- | :--- |
| `dist-tags.latest` | **`0.13.0`** ✓（未回退） |
| versions（尾部） | `0.12.0` · **`0.12.1`** · **`0.13.0`** |
| 0.12.1 `dist.shasum` / `fileCount` | `d1e47f1477ff14115481e10617ea7702c9723f80` / **48** |
| 0.13.0 `dist.shasum` / `fileCount` | `86521f93d16c7c7333aace84d8594b9c902d162e` / **48** |

**产物一致性**：本地在对应 tag 检出点 `npm pack` 后 sha1 与 registry 声称值**逐字节相同**（0.12.1 `d1e47f14…` · 0.13.0 `86521f93…`）；包内 **0 处** `tests/` 或 `docs/` 泄漏；包内 `pi.skills` = 2 条（`nao-fleet` + `frontend-design`），`version` = 0.13.0。

> 过程观察：发布采用 npm 异步窗口（`PUT 202` + 「being processed」），期间出现过 `0.12.1` 已可见而 `0.13.0` 仍 404 的中间态；终态正确。**顺序无碍**（最终 latest = 0.13.0）。

## 2. 真实安装（0.13.0）

| 步骤 | 结果 |
| :--- | :--- |
| `pi install -l --approve npm:@nathan33/nao-skill@0.13.0`（/tmp 临时项目） | **rc=0** · `added 1 package` |
| `.pi/settings.json` | `{"packages":["npm:@nathan33/nao-skill@0.13.0"]}` ✓ |
| 物化 | `.pi/npm/node_modules/@nathan33/nao-skill/` 就位（含 `bin/`）✓ |
| `nao-skill init` | 写入 `.agents/scripts/nao-fleet.sh`（仅 shim）✓ |
| `bash .agents/scripts/nao-fleet.sh check` | **rc=0 · `roles=6 · files=43 · layout=main-row2`** ✓ |

## 3. 两处修复的行为实测（发布版）

| 验证项 | 结果 |
| :--- | :--- |
| **0.12.1 别名修复** | `nao-fleet.sh ensure --task VERIFY arch` → **rc=0**，输出「已拉起 **arch-designer**-VERIFY2」⇒ `arch` → `arch-designer` 解析正确（修复前为「未知角色」）✓ |
| 0.12.1 `check` 别名守卫 | 临时项目 `check` rc=0（守卫逐条校验别名可解析）✓ |
| **0.13.0 F4（minimal 零 shim）** | 合成 minimal 型夹具（`.agents/prompts/*` + 中性 README，全仓机制引用 0）`migrate` → **未创建 shim**，输出「未发现 nao 脚本/引用 → 判定为纯文档迁移，未写 shim（可用 `--shim` 强制）」✓ |
| 0.13.0 F3（标记移除） | 该夹具迁移后 **`.agents/.nao-migrated` 不存在** ✓ · `.nao-version` = `0.13.0` · `.nao-obsolete/<stamp>/` 备份就位 ✓ |
| 0.13.0 F4 开关互斥 | `migrate --shim --no-shim` → **rc=2** + 「`--shim` 与 `--no-shim` 互斥」✓ |
| 0.12.1 `close` 跨仓/派生回收 | 本机 /tmp 环境**无法验证**（见 §5 D7）；**真实证据**：T509/T510 期间 5 个派生会话经修复后的 `close` 正常回收（`已回收 …（tmux pane %28/%29/%45/%46/%47）`）✓ |

## 4. 未做的项（如实披露）

- **会话级 skill 注册数**（`pi` 启动后 skill 注册恰 2、collision 0）未做实测：需要交互式会话 + 信任目录；本轮以「包内 `pi.skills` = 2 条文件声明 + `check` rc=0」作为等价证据。
- CI 侧未涉及（本仓无 CI 门禁配置依赖 `check`）。

## 5. 新增已知边界（D7 · 非缺陷）

| # | 边界 | 说明 |
| :--- | :--- | :--- |
| D7 | **未信任目录下 `ensure` 会停在 pi 的「Trust project folder?」提示** ⇒ 该会话既未在 intercom 名册注册、也未设置终端标题 ⇒ `close --task … <别名>` 报「未运行（无需回收）」**rc=0**，而 pane 实际存活（需人工 `tmux kill-pane` 或先信任目录） | 核验中在 `/tmp/t5proj` 复现；真实作业目录（已信任）不受影响。`close` 的权威在线判定 = intercom 名册，故该行为符合既定语义；若将来要让 `close` 覆盖「pane 存活但未注册」，属**新需求**（另开单） |
