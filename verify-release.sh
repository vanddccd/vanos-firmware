#!/bin/bash
# 发布后自检：把 ota.json 声明的每个文件，在「线上 Cloudflare」「GitHub bin/master」
#                  「本地 landing 目录」三方各核一遍 size + sha256，任一不符即失败。
#
# 只读脚本：不写任何文件、不 deploy、不碰 index.html / merged-binary.bin 的内容
#          （只校验它们线上可访问，绝不修改）。
#
# 用法：
#   ./verify-release.sh            # 全量校验（需联网，约 6~10 MB 下载）
#   ./verify-release.sh --quick    # 只查元数据和 GitHub，不下载大文件
set -u

BASE="${BASE:-https://vanos.pages.dev}"
LANDING="${LANDING:-/Users/van/Desktop/esp32/landing}"
WT="${WT:-/Users/van/Desktop/esp32/vanos-firmware-release}"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0; pass=0
ok()  { pass=$((pass+1)); printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  \033[31m✗\033[0m %s\n' "$*"; }
sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

echo "== 0. 环境 =="
echo "  线上   : $BASE"
echo "  landing: $LANDING"
echo "  git    : $WT"
[ -d "$LANDING" ] || { echo "landing 目录不存在：$LANDING"; exit 2; }
[ -d "$WT/.git" ] || [ -f "$WT/.git" ] || { echo "worktree 不存在：$WT"; exit 2; }
git -C "$WT" fetch bin -q 2>/dev/null || echo "  (git fetch 失败，用本地 ref)"

echo
echo "== 1. 线上 ota.json =="
if ! curl -fsS --max-time 25 "$BASE/ota.json" -o "$TMP/ota.json"; then
  echo "  拿不到 $BASE/ota.json"; exit 2
fi
cat "$TMP/ota.json"
python3 - "$TMP/ota.json" > "$TMP/manifest.tsv" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print('\t'.join([m['version'], m['app'], str(m['size']), m['sha256']]))
for h in m.get('history', []):
    print('\t'.join([h['version'], h['app'], str(h['size']), h['sha256']]))
PY

# 声明版本 == ota.json 版本自检
DECL_VER=$(head -1 "$TMP/manifest.tsv" | cut -f1)
echo "  声明最新版本：$DECL_VER"

echo
echo "== 2. 逐文件三方校验 =="
while IFS=$'\t' read -r ver f size sha; do
  [ -n "${ver:-}" ] || continue
  echo "-- $ver  ($f)"
  [ "$QUICK" = "1" ] && { ok "quick 模式跳过下载"; continue; }
  if ! curl -fsS --max-time 240 "$BASE/$f" -o "$TMP/$(basename "$f")"; then
    bad "$f 线上不可下载"; continue
  fi
  rs=$(wc -c < "$TMP/$(basename "$f")" | tr -d ' ')
  rh=$(sha_of "$TMP/$(basename "$f")")
  [ "$rs" = "$size" ] && ok "线上 size=$rs" || bad "线上 size=$rs ≠ ota.json $size"
  [ "$rh" = "$sha" ] && ok "线上 sha=${rh:0:16}…" || bad "线上 sha=$rh ≠ ota.json $sha"

  if git -C "$WT" cat-file -e "bin/master:$f" 2>/dev/null; then
    gh=$(git -C "$WT" cat-file -p "bin/master:$f" | shasum -a 256 | awk '{print $1}')
    [ "$gh" = "$sha" ] && ok "GitHub sha 一致" || bad "GitHub sha=${gh:0:16}… ≠ $sha"
  else
    bad "GitHub bin/master 上没有 $f"
  fi

  if [ -f "$LANDING/$f" ]; then
    ls_=$(wc -c < "$LANDING/$f" | tr -d ' ')
    lh=$(sha_of "$LANDING/$f")
    if [ "$lh" = "$sha" ]; then
      ok "landing 副本一致"
    else
      bad "landing 副本陈旧：size=$ls_ sha=${lh:0:16}…（下次手工 deploy 会推旧文件）"
    fi
  else
    bad "landing 里没有 $f"
  fi
done < "$TMP/manifest.tsv"

echo
echo "== 3. 受保护文件（只读核对，不修改）=="
for f in index.html merged-binary.bin; do
  if curl -fsSI --max-time 15 "$BASE/$f" >/dev/null 2>&1; then
    ok "$f 线上可访问"
  else
    bad "$f 线上不可访问"
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32m发布自检通过：%d 项，0 失败\033[0m\n' "$pass"
  exit 0
else
  printf '\033[31m发布自检失败：%d 项通过，%d 项失败\033[0m\n' "$pass" "$fail"
  exit 1
fi
