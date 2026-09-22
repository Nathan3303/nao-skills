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

function copyDir(src, dst, force) {
  const entries = readdirSync(src, { withFileTypes: true });
  let copied = 0, skipped = 0, overwritten = 0;
  for (const e of entries) {
    const s = join(src, e.name);
    const d = join(dst, e.name);
    if (existsSync(d)) {
      if (force) {
        rmSync(d, { recursive: true, force: true });
        cpSync(s, d, { recursive: true });
        overwritten++;
      } else {
        skipped++;
      }
    } else {
      cpSync(s, d, { recursive: true });
      copied++;
    }
  }
  return { copied, skipped, overwritten };
}

function install(target, force) {
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
    const r = copyDir(SRC, dst, force);
    log(`合并完成：复制 ${r.copied}，跳过 ${r.skipped}（已存在），覆盖 ${r.overwritten}`);
    if (r.skipped > 0 && !force) {
      warn('同名文件保留项目既有版本（避免覆盖自定义）；需要覆盖加 --force。');
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
  nao-skill install [dir] [--force]   安装/合并 .agents/ 到目标项目（默认当前目录）
  nao-skill update [dir]              升级已有安装：源优先覆盖 + 清理废弃路径 + 保留项目自定义
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
  const rest = args.slice(1);
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--force' || rest[i] === '-f') force = true;
    else if (rest[i] === '--target') target = resolve(rest[++i]);
    else if (!rest[i].startsWith('-')) target = resolve(rest[i]);
    else { warn(`未知参数: ${rest[i]}`); process.exit(2); }
  }
  if (!statIsDir(target)) {
    warn(`目标目录无效: ${target}`);
    process.exit(2);
  }
  install(target, force);
} else if (cmd === 'update' || cmd === 'u') {
  let target = process.cwd();
  const rest = args.slice(1);
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--target') target = resolve(rest[++i]);
    else if (!rest[i].startsWith('-')) target = resolve(rest[i]);
    else { warn(`未知参数: ${rest[i]}`); process.exit(2); }
  }
  if (!statIsDir(target)) {
    warn(`目标目录无效: ${target}`);
    process.exit(2);
  }
  update(target);
} else {
  warn(`未知命令: ${cmd}（可用: install）`);
  process.exit(2);
}
