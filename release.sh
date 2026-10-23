#!/bin/sh
# 一键发布：提交 + 推 master + 同步线刷 manifest + 部署线刷页面到 Cloudflare Pages
# One-shot release: commit, push master, sync the web-flasher manifest, then
# deploy the flasher page to Cloudflare Pages (same URL every time).
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
cp "$LANDING/index.html" "$LANDING"/manifest-*.json "$DIST"/
cp -R "$LANDING/assets" "$DIST"/
( cd "$DIST" && npx --yes wrangler pages deploy . --project-name=vanos --branch=master --commit-dirty=true )
