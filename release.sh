#!/bin/sh
# 一键发布：提交 + 推 master + 把固件搬进落地页 + 部署到 Cloudflare Pages
# One-shot release: commit, push master, refresh the self-contained flasher
# page (bin/ttf/engine all local), then deploy it to Cloudflare Pages.
set -e
cd "$(dirname "$0")"
MSG="${1:-固件 $(date +%F)}"

# 版本递增守卫：设备"要不要更新"只比版本号，SHA256 只校验传输完整性、从不参与决策
# （ota_update.c 的 vanos_manifest_version_newer）。所以同一版本号的新构建发出去之后，
# 所有已经升到该版本的设备都会显示「已是最新」，修复永远到不了任何一台机器，而且
# 整个过程没有任何报错 —— 这个坑必须由脚本挡住，不能靠人记得改 PROJECT_VER。
# Version bump guard: the device decides on the version string alone; the sha256 only
# proves the transfer was intact. Publishing a new build under an unchanged version
# therefore reaches nobody, silently. That has to be caught here, not by memory.
APP_BIN="${APP_BIN:-$(pwd)/vanos-app.bin}"
if [ -f "$APP_BIN" ]; then
  BUILD_VER="$(python3 - "$APP_BIN" <<'PYVER'
import struct, sys
blob = open(sys.argv[1], 'rb').read()
if struct.unpack_from('<I', blob, 0x20)[0] != 0xABCD5432:
    sys.exit('不是 ESP 应用镜像')
sys.stdout.write(blob[0x30:0x50].split(b'\0')[0].decode('ascii', 'replace'))
PYVER
)"
  PUBLISHED_VER="$(curl -fsS --max-time 8 https://vanos.pages.dev/ota.json 2>/dev/null \
    | python3 -c 'import json,sys;print(json.load(sys.stdin).get("version",""))' 2>/dev/null || true)"
  if [ -n "$PUBLISHED_VER" ] && [ "$PUBLISHED_VER" = "$BUILD_VER" ] && [ "${FORCE_SAME_VERSION:-0}" != "1" ]; then
    echo "! 拒绝发布：版本号没变（$BUILD_VER）。" >&2
    echo "  设备只比版本号，同号新构建发出去等于没发（所有设备都报「已是最新」）。" >&2
    echo "  先改 CMakeLists.txt 里的 set(PROJECT_VER ...) 末段再重编；确要强推用 FORCE_SAME_VERSION=1。" >&2
    exit 1
  fi
  echo "版本 $BUILD_VER（线上 ${PUBLISHED_VER:-读不到}）"
fi

git add -A
if git diff --cached --quiet; then
  echo "没有待提交的改动"
else
  git commit -m "$MSG"
fi
git push bin HEAD:master

LANDING="${LANDING:-$(cd .. && pwd)/landing}"
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
python3 - "$APP_BIN" "$DIST/ota.json" "$LANDING" <<'PY'
import glob, hashlib, json, os, re, shutil, struct, sys

src, dst, hold = sys.argv[1], sys.argv[2], sys.argv[3]
dist = os.path.dirname(os.path.abspath(dst))

blob = open(src, 'rb').read()
magic = struct.unpack_from('<I', blob, 0x20)[0]
if magic != 0xABCD5432:
    sys.exit('不是 ESP 应用镜像：magic=0x%08x' % magic)
version = blob[0x30:0x50].split(b'\0')[0].decode('ascii', 'replace')
digest = hashlib.sha256(blob).hexdigest()

# 每一版都留一份带版本号的副本。删掉它等于把这个版本从回退列表里退役。
# 存档必须落在 landing：$DIST 是 mktemp -d，下次发布就是空目录，累积不起来。
# Keep one copy per version, in landing: $DIST is a mktemp dir and would be empty
# next run, so history could never accumulate (and the deploy would drop the old
# payloads from the site, turning every history URL into a 404).
keep = os.path.join(hold, 'vanos-app-%s.bin' % version)
if not os.path.exists(keep) or hashlib.sha256(open(keep, 'rb').read()).hexdigest() != digest:
    open(keep, 'wb').write(blob)

# landing 里的存档要一起进本次部署快照，否则线上还是只有当前这一份。
# Every archived payload rides along in this deployment snapshot.
for f in glob.glob(os.path.join(hold, 'vanos-app-*.bin')):
    shutil.copy2(f, dist)

def vkey(v):
    return tuple(int(x) for x in v.split('.')) if re.fullmatch(r'\d+(\.\d+){3}', v) else (0, 0, 0, 0)

hist = []
for f in glob.glob(os.path.join(hold, 'vanos-app-*.bin')):
    b = open(f, 'rb').read()
    if len(b) < 0x50 or struct.unpack_from('<I', b, 0x20)[0] != 0xABCD5432:
        continue
    v = b[0x30:0x50].split(b'\0')[0].decode('ascii', 'replace')
    if v == version:
        continue
    # 只收比当前更旧的：服务器上可能还躺着更高版本的存档（试过又退回来的），
    # 把新的塞进 history 会让设备去「回退」到一个更新的构建。
    # Only keep older builds: a newer archive may still sit on the server, and
    # listing it under history would "roll back" onto something newer.
    if vkey(v) >= vkey(version):
        continue
    hist.append({'version': v, 'app': os.path.basename(f), 'size': len(b),
                 'sha256': hashlib.sha256(b).hexdigest()})
hist.sort(key=lambda e: vkey(e['version']), reverse=True)
# 与固件端 VANOS_MANIFEST_MAX_HISTORY 对齐，多了会被静默丢弃。
# Match VANOS_MANIFEST_MAX_HISTORY in the firmware; extra entries are dropped.
hist = hist[:5]

# notes 在 history 之前、history 放最后：固件端的字段提取是 strstr 整个 body 的，
# history 排在前面会让 history[0] 冒充顶层 version / app / size / sha256。
# history goes last: the firmware extracts fields with strstr over the whole body,
# so an earlier history block would shadow the top-level fields.
manifest = {
    'product': 'vanos',
    'channel': 'stable',
    'version': version,
    'app': 'vanos-app.bin',
    'size': len(blob),
    'sha256': digest,
    'notes': '',
    'history': hist,
}
with open(dst, 'w', encoding='utf-8') as out:
    json.dump(manifest, out, ensure_ascii=False, indent=1)
print('ota.json  version=%s  size=%d  sha256=%s  history=%d'
      % (version, len(blob), digest[:8], len(hist)))
for h in hist:
    print('  hist %s  %s  %d' % (h['version'], h['app'], h['size']))
PY
# landing 是持久目录、$DIST 是 mktemp：清单也要在 landing 留一份，否则下次
# 手工从 landing 部署会把线上清单覆盖回旧版本。
# Keep the manifest in landing too: $DIST is throwaway, and a manual deploy from
# landing would otherwise push the old manifest back to the site.
cp "$DIST/ota.json" "$LANDING/ota.json"
# 在 landing 目录里部署：Functions（functions/）从这里打包，静态文件用临时目录快照
( cd "$LANDING" && npx --yes wrangler@3 pages deploy "$DIST" --project-name=vanos --branch=master --commit-dirty=true )
