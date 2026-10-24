#!/bin/sh
# 一键发布：提交 + 推 master + 把固件搬进落地页 + 部署到 Cloudflare Pages
# One-shot release: commit, push master, refresh the self-contained flasher
# page (bin/ttf/engine all local), then deploy it to Cloudflare Pages.
set -e
cd "$(dirname "$0")"
MSG="${1:-固件 $(date +%F)}"

git add -A
if git diff --cached --quiet; then
  echo "没有待提交的改动"
else
  git commit -m "$MSG"
fi
git push origin HEAD:master

LANDING="${LANDING:-$(cd .. && pwd)/esp32/landing}"
if [ -f "$LANDING/sync-manifests.py" ]; then
  ( cd "$LANDING" && python3 sync-manifests.py )
else
  echo "! 没找到 $LANDING/sync-manifests.py，manifest 未同步" >&2
  exit 1
fi

DIST="$(mktemp -d)"
trap 'rm -rf "$DIST"' EXIT
cp "$LANDING/index.html" "$LANDING/manifest-full.json" "$LANDING/_headers" "$DIST"/
cp "$LANDING/merged-binary.bin" "$LANDING/朱雀仿宋.ttf" "$DIST"/
cp -R "$LANDING/assets" "$DIST"/

# OTA 载荷与清单：设备只下这个 2.7MB 的 app 镜像，不碰整片 merge。
# OTA payload and manifest: devices download this 2.7 MB app image, not the full merge.
APP_BIN="${APP_BIN:-$(pwd)/vanos-app.bin}"
if [ ! -f "$APP_BIN" ]; then
  echo "! 缺少 $APP_BIN：先编好 build/VanOS.bin 再 cp 成 vanos-app.bin" >&2
  exit 1
fi
cp "$APP_BIN" "$DIST/vanos-app.bin"
python3 - "$APP_BIN" "$DIST/ota.json" <<'PY'
import hashlib, json, struct, sys

src, dst = sys.argv[1], sys.argv[2]
blob = open(src, 'rb').read()
magic = struct.unpack_from('<I', blob, 0x20)[0]
if magic != 0xABCD5432:
    sys.exit('不是 ESP 应用镜像：magic=0x%08x' % magic)
version = blob[0x30:0x50].split(b'\0')[0].decode('ascii', 'replace')
digest = hashlib.sha256(blob).hexdigest()
manifest = {
    'product': 'vanos',
    'channel': 'stable',
    'version': version,
    'app': 'vanos-app.bin',
    'size': len(blob),
    'sha256': digest,
    'notes': '',
}
with open(dst, 'w', encoding='utf-8') as out:
    json.dump(manifest, out, ensure_ascii=False, indent=1)
print('ota.json  version=%s  size=%d  sha256=%s' % (version, len(blob), digest[:8]))
PY
# 在 landing 目录里部署：Functions（functions/）从这里打包，静态文件用临时目录快照
( cd "$LANDING" && npx --yes wrangler@3 pages deploy "$DIST" --project-name=vanos --branch=master --commit-dirty=true )
