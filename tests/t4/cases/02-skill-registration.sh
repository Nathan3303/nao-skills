#!/usr/bin/env bash
# 用例 02 —— 设计一致性：注册 skill 数 == 2 且无 collision 诊断（PRD AC1 尾部 / AC6 / D3）
#
# 静态：package.json pi manifest 按文件声明恰 2 个 skill，无 pi.prompts（BR2）
# 动态：真 pi 启动（--mode json）后，nao 包贡献的注册 skill 恰 2 个，
#       名称为 {nao-fleet, frontend-design}，且无 collision 诊断（D3 去重成立）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm

# ---------------------------------------------------------------- 静态契约
info_tsv="$(node -e '
const fs=require("fs"),path=require("path");
const root=process.argv[1];
const pkg=JSON.parse(fs.readFileSync(path.join(root,"package.json"),"utf8"));
const pi=pkg.pi||{};
console.log("has_pi=" + (pkg.pi?1:0));
console.log("has_prompts=" + (pi.prompts===undefined?0:1));
const arr=Array.isArray(pi.skills)?pi.skills:[];
console.log("declared=" + arr.length);
for(const p of arr){
  const abs=path.resolve(root,p);
  const ex=fs.existsSync(abs)?1:0;
  let name="",dl="";
  if(ex){const t=fs.readFileSync(abs,"utf8");const m=t.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    if(m){const a=m[1].match(/^name:\s*(.+)$/m);const b=m[1].match(/^description:\s*(.+)$/m);name=a?a[1].trim():"";dl=b?b[1].trim().length:0;}}
  console.log(`skill=${p}\texists=${ex}\tname=${name}\tdesclen=${dl}`);
}
' "$T4_ROOT" 2>&1)"

if [ -z "$info_tsv" ]; then t4_blocked "无法解析 package.json pi manifest"; fi

has_pi="$(printf '%s\n' "$info_tsv" | sed -n 's/^has_pi=//p')"
has_prompts="$(printf '%s\n' "$info_tsv" | sed -n 's/^has_prompts=//p')"
declared="$(printf '%s\n' "$info_tsv" | sed -n 's/^declared=//p')"

t4_assert_eq "1" "$has_pi" "package.json 含 pi manifest"
t4_assert_eq "2" "$declared" "pi.skills 按文件声明恰 2 个（D3）"
t4_assert_eq "0" "$has_prompts" "未声明 pi.prompts（BR2：角色卡保持常驻注入）"

declared_names="$(printf '%s\n' "$info_tsv" | sed -n 's/.*\tname=\(.*\)\tdesclen=.*/\1/p' | sort | tr '\n' ' ')"
t4_info "声明 skill: $declared_names"
t4_assert_contains "$declared_names" "nao-fleet" "声明含 nao-fleet"
t4_assert_contains "$declared_names" "frontend-design" "声明含 frontend-design"

n_exists="$(printf '%s\n' "$info_tsv" | grep -c 'exists=1' || true)"
t4_assert_eq "2" "$n_exists" "2 个声明路径均存在"
n_empty="$(printf '%s\n' "$info_tsv" | sed -n 's/.*\tdesclen=\([0-9]*\).*/\1/p' | grep -c '^0$' || true)"
t4_assert_eq "0" "$n_empty" "每个 SKILL.md 含非空 description"

# 单一事实来源：frontend-design 在包内 .agents/skills/ 下（D3 去重目标）
t4_assert_file "$T4_ROOT/.agents/skills/frontend-design/SKILL.md" "单一来源: 包内 .agents/skills/frontend-design/SKILL.md"

# ---------------------------------------------------------------- 动态（真 pi）
if ! command -v pi >/dev/null 2>&1; then
  t4_skip "pi CLI 不可用，无法执行动态注册检查"
fi

fx="$(t4_fixture)"
t4_materialize "$fx"
if t4_cli_supports init; then t4_run_init "$fx" >/dev/null 2>&1; fi

of="$T4_CACHE_DIR/pi-reg.jsonl"; ef="$T4_CACHE_DIR/pi-reg.err"
( cd "$fx" && timeout 120 pi --mode json --approve --no-session --no-mcp -p ok ) >"$of" 2>"$ef"
pi_rc=$?
t4_info "pi rc=$pi_rc · stdout=$(wc -c <"$of")B"

if grep -q "No API key" "$ef" 2>/dev/null; then
  t4_note "pi 无可用凭据（No API key），动态注册检查 SKIP；静态契约仍已校验"
else
  reg_tsv="$(node -e '
const fs=require("fs");
const lines=fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/);
for(const l of lines){ if(!l.trim()) continue; let o; try{o=JSON.parse(l)}catch(e){continue;}
  if(o.type==="message_start" && o.message && o.message.role==="system"){
    const s=(o.message.sections||{}).skills||"";
    const re=/<name>([^<]*)<\/name>\s*<description>[\s\S]*?<\/description>\s*<location>([^<]*)<\/location>/g;
    let m; while((m=re.exec(s))) console.log(m[1]+"\t"+m[2]);
    process.exit(0);
  }
}
' "$of" 2>/dev/null)"

  if [ -z "$reg_tsv" ]; then
    t4_bad "pi 未在 system prompt 输出 <available_skills>（skills 段缺失）"
  else
    pkg_scope="$(printf '%s/.pi/npm/node_modules/%s/' "$fx" "$PKG_NAME")"
    nao_tsv="$(printf '%s\n' "$reg_tsv" | grep -F "$pkg_scope" || true)"
    nao_names="$(printf '%s\n' "$nao_tsv" | cut -f1 | sort | tr '\n' ' ')"
    nao_count="$(printf '%s\n' "$nao_tsv" | grep -c . || true)"
    proj_tsv="$(printf '%s\n' "$reg_tsv" | grep -F "$fx/.agents/skills/" || true)"
    t4_info "nao 包注册: $nao_names"
    t4_assert_eq "2" "$nao_count" "nao 包注册 skill 数 == 2（AC1）"
    t4_assert_contains "$nao_names" "nao-fleet" "注册含 nao-fleet"
    t4_assert_contains "$nao_names" "frontend-design" "注册含 frontend-design"
    t4_assert_eq "" "$proj_tsv" "项目 .agents/skills 未注册任何 skill（无重复来源）"
  fi

  # collision 诊断：pi 的形态是 `name "<x>" collision` / {"type":"collision"}（T1 §3）
  coll="$(grep -oE 'name "[^"]+" collision' "$of" "$ef" 2>/dev/null | sort -u || true)"
  t4_assert_eq "" "$coll" "无 skill collision 诊断"
fi

t4_exit
