# M20261014-pi-ext-update 遗留项台账

- 编号：M20261014-pi-ext-update · 类型：维护型（工具环境依赖）· 触发：2026-10-14 `pi update --extensions`
- 环境：`~/.pi/agent/npm`（pi 用户级扩展根，非本仓源码）
- 回滚手段：`/tmp/pi-npm-lock-backup-20261014.json`（md5 `296f0954…`，改动前快照）

## 一、动作与验证

- **动作 1**：`npm install-scripts approve esbuild` → **rc=0**，`added esbuild@0.28.2`（`tsx@4.23.15` 的构建依赖已就位）。
- **动作 2**：`npm audit fix` → **rc=0**（非 `--force`）。
- **验证**：原 4 项告警**全部消除**——`zod` 4.6.5 → **4.6.7**（`<4.6.6` 区间外）· `ip-address` 10.7.3 → **10.7.5** · `fast-uri` 3.1.8 → **3.1.9**。
- **installed 树核对**：`npm ls --depth=0` 仍为 4 个直接依赖（`pi-ask-me@0.1.1` / `pi-intercom@0.18.1` / `pi-subagents@0.83.0` / `pi-web-access@0.45.0`），无增减。

## 二、动作后的新事实（不是回归，是暴露）

- `npm audit` 现报 **13 项（12 high / 1 moderate）**，与改动前的 4 项**不同源**：改动前 `pi-ask-me@0.1.1` 依赖的 `@mariozechner/pi-coding-agent@0.55.4` 子树**并未真正安装**；本次重解析写入 **221 条** `package-lock` 条目（新增 `@anthropic-ai/sdk@0.73.0`、`@aws-sdk/*` 等），该子树落盘后其漏洞才可见。
- **12 high 的关键路径**：`pi-ask-me@0.1.1` → `@mariozechner/pi-coding-agent@0.55.4` → `@mistralai/mistralai@1.10.0` → `zod@3.25.76`（**no fix available**）。上游 `pi-ask-me` 最新版**仍是 0.1.1**，无升级路径。
- **1 moderate**：`@earendil-works/pi-coding-agent`（`fixAvailable: true`，但需跨 major，未被非 `--force` 的 `audit fix` 收录）。
- 其余 high（`undici` / `basic-ftp` / `extract-zip` / `get-uri` / `proxy-agent` / `pac-proxy-agent`）同属上述旧 SDK 子树。

## 三、遗留项与出口

- **F1 `pi-ask-me` 旧 SDK 子树（12 high）**：出口 = **接受**（用户 2026-10-14 拍板）· 理由：本地开发环境、无网络暴露面，旧 SDK 仅在扩展进程内被调用；卸载会同时失去 ask-me 提问通道（与「拍板一律 ask-me」约束冲突）· 到期 **2026-11-14** 重评；重评触发条件 = 上游 `pi-ask-me` 升版 / 任一 high 变可利用面。
- **F2 `@earendil-works/pi-coding-agent` moderate**：出口 = **接受**（改动需跨 major，`pi-intercom` 侧兼容未知）；到期 2026-11-14；触发条件 = `pi-intercom` 升版时同步评估。
- **F3 旧 SDK 未装却是"假安全"**：出口 = **关闭**，教训已记入本台账（audit 数字须配「树是否完整」一起读）。

## 四、复盘（L0）

- 结论：本次 4 项已清零、esbuild 已批准；副作用暴露上游旧依赖树 12 high，属**新增已知项**而非回归。
- 机制含义：这正是「`exit 0` 不构成完成」的实例——若不追 audit 与 install-scripts，本台账与 F1/F2 都不会存在。
