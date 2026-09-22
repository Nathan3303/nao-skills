#!/usr/bin/env node
/**
 * nao-skill — nao 多角色 AI 开发舰队安装器
 *
 * 用法
 *   nao-skill install [dir] [--force]  把 .agents/ 能力安装到目标项目（默认当前目录）
 *   nao-skill --version               版本
 *   nao-skill --help                  帮助
 *
 * 行为
 *   - 目标项目无 .agents/ → 完整复制
 *   - 已有 .agents/       → 合并：同名条目保留项目既有（--force 则备份后覆盖）
 *   - 无 AGENTS.md        → 由模板生成（项目级上下文，PM 维护）
 *   - 已有 AGENTS.md      → 提示按 PM 卡 §七 合并规则手动追加，不自动覆盖
 *
 * 使用（安装后）
 *   bash .agents/scripts/nao-fleet.sh check / ensure arch rd-fe ...
 *   角色卡经 fleet 拉起时 --append-system-prompt 注入；checklists 按需读取
 */
import { execFileSync } from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
  rmSync,
  statSync,
} from 'node:fs';
import { join, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const PKG = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const SRC = fileURLToPath(new URL('../.agents', import.meta.url));
const TEMPLATE_AGENTS = fileURLToPath(new URL('../.agents/templates/AGENTS.md.example', import.meta.url));

// 已知废弃路径（相对项目根）：旧版遗留，update 时备份后移除
const OBSOLETE = ['.agents/skills/checklists'];
// 安装版本标记（install/update 写入，供下次检测升级）
const VERSION_FILE = '.agents/.nao-version';

const log = (...a) => console.log('[nao-skill]', ...a);
const warn = (...a) => console.error('[nao-skill]', ...a);

function syncTree(src, dst, { mode, force, verbose }) {
  // 递归文件级同步：mode='install'（保守）| 'update'（源优先）
  // 源文件 → 目标无：copy；同内容：same（跳过）；不同内容：install 默认 keep（--force 覆盖）/ update 总是 overwrite
  // 目标独有：不动（项目自定义保留）
  const stats = { copied: 0, overwritten: 0, same: 0, kept: 0 };
  const base = dst;
  const rel = (p) => p.replace(base + '/', '');
  const walk = (s, d) => {
    if (!existsSync(d)) mkdirSync(d, { recursive: true });
    for (const e of readdirSync(s, { withFileTypes: true })) {
      const sp = join(s, e.name);
      const dp = join(d, e.name);
      if (e.isDirectory()) { walk(sp, dp); continue; }
      if (!existsSync(dp)) {
        cpSync(sp, dp);
        stats.copied++;
        if (verbose) log(`  copy      ${rel(dp)}`);
      } else if (readFileSync(sp).equals(readFileSync(dp))) {
        stats.same++;
        if (verbose) log(`  same      ${rel(dp)}`);
      } else if (mode === 'update' || force) {
        rmSync(dp, { force: true });
        cpSync(sp, dp);
        stats.overwritten++;
        if (verbose) log(`  overwrite ${rel(dp)}`);
      } else {
        stats.kept++;
        if (verbose) log(`  keep      ${rel(dp)}（内容不同，--force 覆盖）`);
      }
    }
  };
  walk(src, dst);
  return stats;
}

// 已知 pi 插件（nao 舰队生态），name → npm 包
const PI_PLUGINS = {
  intercom:   { pkg: 'pi-intercom',            desc: '多会话协作（舰队机制核心依赖）' },
  'ask-me':   { pkg: 'pi-ask-me',              desc: '提问/访谈工具' },
  subagents:  { pkg: 'pi-subagents',           desc: '子代理委派' },
  'web-access': { pkg: 'pi-web-access',        desc: '网页访问' },
  codegraph:  { pkg: '@sean_pedersen/pi-codegraph', desc: 'CodeGraph 代码定位（pi 集成）' },
};

function piSettingsPath() {
  return join(process.env.HOME || process.env.USERPROFILE || '', '.pi', 'agent', 'settings.json');
}

function readPackages() {
  try {
    const d = JSON.parse(readFileSync(piSettingsPath(), 'utf8'));
    return Array.isArray(d.packages) ? d.packages : [];
  } catch {
    return [];
  }
}

function installedPlugins() {
  const pkgs = readPackages();
  const out = {};
  for (const [name, { pkg }] of Object.entries(PI_PLUGINS)) {
    out[name] = pkgs.includes(`npm:${pkg}`) || pkgs.includes(pkg);
  }
  return out;
}

function pluginsList() {
  const installed = installedPlugins();
  log(`pi 插件状态（settings: ${piSettingsPath()}）`);
  for (const [name, { pkg, desc }] of Object.entries(PI_PLUGINS)) {
    console.log(`  ${installed[name] ? '✓' : '·'} ${name.padEnd(11)} ${pkg.padEnd(26)} ${desc}${installed[name] ? '' : '（缺失）'}`);
  }
  console.log('\n安装: nao-skill plugins install <name...> | plugins install-all');
}

function pluginsInstall(names, all = false) {
  const targets = all ? Object.keys(PI_PLUGINS) : names;
  const todo = [];
  for (const n of targets) {
    const p = PI_PLUGINS[n];
    if (!p) { warn(`未知插件: ${n}（可用: ${Object.keys(PI_PLUGINS).join(', ')}）`); continue; }
    if (installedPlugins()[n]) { log(`已安装: ${n}`); continue; }
    todo.push([n, p]);
  }
  if (!todo.length) { log('全部插件已就绪。'); return; }
  for (const [n, p] of todo) {
    log(`安装 ${n} → pi install npm:${p.pkg} ...`);
    try {
      execFileSync('pi', ['install', `npm:${p.pkg}`], { stdio: 'inherit' });
      log(`✓ ${n} 安装完成（重启 pi 会话后生效）`);
    } catch (e) {
      warn(`✗ ${n} 安装失败: ${e.message}（确认 pi 已安装且在 PATH）`);
    }
  }
}

function install(target, force, verbose) {
  if (!existsSync(SRC)) {
    warn(`包内 .agents 缺失：${SRC}（发布物损坏？）`);
    process.exit(1);
  }
  const dst = join(target, '.agents');
  if (!existsSync(dst)) {
    mkdirSync(dst, { recursive: true });
    cpSync(SRC, dst, { recursive: true });
    log(`已完整安装 .agents/ → ${dst}`);
  } else {
    const r = syncTree(SRC, dst, { mode: 'install', force, verbose });
    log(`合并完成：复制 ${r.copied}，覆盖 ${r.overwritten}，相同跳过 ${r.same}，保留项目版 ${r.kept}`);
    if (r.kept > 0 && !force) {
      warn('内容不同的文件保留项目既有（避免覆盖自定义）；--force 覆盖，或 update 模式源优先。');
    }
  }

  // 版本标记 + 升级/废弃检测
  const prev = readInstalledVersion(target);
  writeFileSync(join(target, VERSION_FILE), PKG.version);
  if (prev && prev !== PKG.version) {
    warn(`检测到旧版安装（v${prev} → v${PKG.version}）：建议运行 nao-skill update 升级机制文件。`);
  }
  for (const p of detectObsolete(target)) {
    warn(`发现废弃路径 ${p}（旧版遗留，可能导致 skill 冲突）：建议运行 nao-skill update 清理。`);
  }

  const agentsMd = join(target, 'AGENTS.md');
  if (!existsSync(agentsMd)) {
    let tpl = readFileSync(TEMPLATE_AGENTS, 'utf8');
    tpl = tpl.replaceAll('<项目名>', basename(resolve(target)));
    writeFileSync(agentsMd, tpl);
    log('已生成 AGENTS.md（项目级上下文，PM 维护；保持精简 <120 行）。');
  } else {
    warn('AGENTS.md 已存在：按 PM 卡 §七 合并规则手动追加「nao 舰队接入」区块，勿覆盖原文。');
  }

  log('');
  log('✔ 安装完成。下一步：');
  log('  bash .agents/scripts/nao-fleet.sh check                       # 体检');
  log('  bash .agents/scripts/nao-fleet.sh status                      # 在线状态');
  log('  bash .agents/scripts/nao-fleet.sh ensure arch rd-fe rd-be qa  # 拉起舰队');
  log('  角色卡：.agents/prompts/ · 技能：.agents/skills/ · 交付清单：.agents/checklists/');
}

function update(target) {
  // 源优先升级：机制文件以包为权威（项目定制应放 AGENTS.md，不在机制文件里改）
  const dst = join(target, '.agents');
  if (!existsSync(dst)) {
    log('目标无 .agents/，直接完整安装。');
    return install(target, false);
  }
  let overwritten = 0;
  for (const e of readdirSync(SRC)) {
    const s = join(SRC, e);
    const d = join(dst, e);
    rmSync(d, { recursive: true, force: true });
    cpSync(s, d, { recursive: true });
    overwritten++;
  }
  // 清理已知废弃路径（先备份到 .agents/.nao-obsolete/）
  for (const p of OBSOLETE) {
    const full = join(target, p);
    if (existsSync(full)) {
      const bakDir = join(dst, '.nao-obsolete');
      mkdirSync(bakDir, { recursive: true });
      cpSync(full, join(bakDir, `${basename(p)}-${Date.now()}`), { recursive: true });
      rmSync(full, { recursive: true, force: true });
      log(`废弃路径已备份并移除: ${p}（备份于 .agents/.nao-obsolete/）`);
    }
  }
  // 项目自定义文件保留（源没有的不动）
  writeFileSync(join(target, VERSION_FILE), PKG.version);
  log(`✔ 升级完成：机制文件以 v${PKG.version} 为准，项目自定义已保留。`);
}

function readInstalledVersion(target) {
  try { return readFileSync(join(target, VERSION_FILE), 'utf8').trim(); } catch { return null; }
}

function detectObsolete(target) {
  return OBSOLETE.filter((p) => existsSync(join(target, p)));
}

function help() {
  console.log(`nao-skill v${PKG.version} — nao 多角色 AI 开发舰队安装器

用法:
  nao-skill install [dir] [--force] [-v]   安装/合并 .agents/ 到目标项目（默认当前目录；-v 显示每文件过程）
  nao-skill install --plugins [-v]         项目接入时顺带安装 pi 舰队插件
  nao-skill update [dir] [-v]              升级已有安装：源优先覆盖 + 清理废弃路径 + 保留项目自定义
  nao-skill plugins list              列出已知 pi 插件与安装状态
  nao-skill plugins install <名...>   安装指定插件（intercom/ask-me/subagents/web-access/codegraph）
  nao-skill plugins install-all       安装全部舰队插件
  nao-skill --version                 显示版本
  nao-skill --help                    显示本帮助

安装内容: 角色卡(prompts/) · 技能(skills/) · 交付清单(checklists/) · 协作协议(common/) ·
          roles.yaml · 工具链(scripts/) · 模板(templates/) · AGENTS.md 生成/合并提示

说明: 目标项目已有同名文件时默认保留（--force 覆盖）；AGENTS.md 已存在时按合并规则手动追加。
`);
}

function statIsDir(p) {
  try { return statSync(p).isDirectory(); } catch { return false; }
}

const args = process.argv.slice(2);
const cmd = args[0];

if (cmd === '--version' || cmd === '-v' || cmd === 'version') {
  console.log(PKG.version);
} else if (cmd === '--help' || cmd === '-h' || cmd === 'help' || !cmd) {
  help();
} else if (cmd === 'install' || cmd === 'i') {
  let target = process.cwd();
  let force = false;
  let withPlugins = false;
  let verbose = false;
  const rest = args.slice(1);
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--force' || rest[i] === '-f') force = true;
    else if (rest[i] === '--plugins') withPlugins = true;
    else if (rest[i] === '--verbose' || rest[i] === '-v') verbose = true;
    else if (rest[i] === '--target') target = resolve(rest[++i]);
    else if (!rest[i].startsWith('-')) target = resolve(rest[i]);
    else { warn(`未知参数: ${rest[i]}`); process.exit(2); }
  }
  if (!statIsDir(target)) {
    warn(`目标目录无效: ${target}`);
    process.exit(2);
  }
  install(target, force, verbose);
  if (withPlugins) pluginsInstall([], true);
} else if (cmd === 'plugins' || cmd === 'plugin') {
  const sub = args[1];
  const rest = args.slice(2);
  if (sub === 'list' || sub === 'ls' || !sub) {
    pluginsList();
  } else if (sub === 'install' || sub === 'add') {
    pluginsInstall(rest);
  } else if (sub === 'install-all' || sub === 'installAll') {
    pluginsInstall([], true);
  } else {
    warn(`未知插件命令: ${sub}（可用: list / install / install-all）`);
    process.exit(2);
  }
} else if (cmd === 'update' || cmd === 'u') {
  let target = process.cwd();
  let verbose = false;
  const rest = args.slice(1);
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--verbose' || rest[i] === '-v') verbose = true;
    else if (rest[i] === '--target') target = resolve(rest[++i]);
    else if (!rest[i].startsWith('-')) target = resolve(rest[i]);
    else { warn(`未知参数: ${rest[i]}`); process.exit(2); }
  }
  if (!statIsDir(target)) {
    warn(`目标目录无效: ${target}`);
    process.exit(2);
  }
  update(target, verbose);
} else {
  warn(`未知命令: ${cmd}（可用: install, update, plugins）`);
  process.exit(2);
}
