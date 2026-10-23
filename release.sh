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
cp "$LANDING/index.html" "$LANDING/changelog.html" "$LANDING/manifest-full.json" "$LANDING/_headers" "$DIST"/
cp "$LANDING/merged-binary.bin" "$LANDING/朱雀仿宋.ttf" "$DIST"/
cp -R "$LANDING/assets" "$DIST"/
( cd "$DIST" && npx --yes wrangler pages deploy . --project-name=vanos --branch=master --commit-dirty=true )
