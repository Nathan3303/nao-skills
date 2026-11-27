# v0.37.0

- 状态：待核验 · 更新：2026-11-27 · Owner：pm

## 本次更新

**项目改名了：`nao-skills` → `nao-fleet`，npm 包名同步变成 `nao-fleet`（去掉了 `@nathan33` 前缀）**，安装命令更短。这一版还换了站点图标、给首页那条演示动画加了渐隐收边。

## ✨ 更好用了

- **安装命令变短**：从 `pi install -l npm:@nathan33/nao-skill` 变成 `pi install -l npm:nao-fleet`
- **站点图标重做**：标签页里换成一枚终端提示符图标，16 像素下也能一眼认出来
- **首页那条演示动画收边了**：底边不再是一条硬切线，画面自然融进页面

## ⚠️ 请留意（升级需要动作）

- **包名变了**：旧包 `@nathan33/nao-skill` 不再更新（已标记迁移指向新包）。升级请把项目里的 pin 换成 `nao-fleet`：
  `pi install -l npm:nao-fleet@0.37.0`
- **文档站地址变了**：`nathan3303.github.io/nao-fleet/`（旧地址不再跳转，收藏夹请更新）
- **两条兼容别名保留一个版本**：环境变量 `NAO_FLEET` 优先、`NAO_SKILLS` 仍可用；安装器命令 `nao-fleet` 优先、`nao-skill` 仍可用。下个版本起移除旧名。
- **想继续用旧的终端（tmux）后端**：只有旧包有那条路 —— `pi install -l npm:@nathan33/nao-skill@≤0.27.x`；新包 `nao-fleet` 从 0.37.0 起没有 tmux 后端。

## 🐛 修好了

- **本地开发时看不到站点图标**：图标引用以前只在构建期注入，本地预览里标签页一直空白；现在开发与构建同源。
- **演示动画的细边框看不见**：上一版给卡片加的 1px 描边被图片本身盖住了，等于没有；现在边框画在图片之上，并且跟着底边一起淡出。

## 技术细节（可略过）

- 任务：T594（改名，45 文件）· T590（favicon 重设计 + dev 注入单一来源）· T587 追加（mask 74%→100% + `::after` 环 + 纯装饰无障碍改判）
- 兼容层：`NAO_FLEET` 优先 / `NAO_SKILLS` 别名；`bin` 双键同指一文件（`nao-fleet` / `nao-skill`）；`check` 新增 `check_env_alias` 断言（单点 + 优先序 + shim 序）
- 门禁：`check: OK · roles=7 · files=71`；全量 46 例 → 45 PASS / 1 环境红（真机就绪门 `case 32`，基线同红，另案 #245）
- 仓库改名后 GitHub 会 301 重定向旧 URL；**GitHub Pages 不跳转**，旧子路径 404
- 文档示例 pin 与首发版本强绑定：本版统一 `0.37.0`；跨包世系（旧包 ≤0.27.x 才有 tmux 后端）已写入 README / INSTALL / 站点
- 回退：`git revert` 对应合并提交；若需回到旧包，pin 回 `@nathan33/nao-skill@0.36.0`
