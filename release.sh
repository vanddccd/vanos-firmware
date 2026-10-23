#!/bin/sh
# 一键发布：提交 + 推送（master/main 两个分支）+ 同步线刷页面的 manifest
# One-shot release: commit, push both branches, then re-point the web flasher
# manifests at the new commit so no CDN/browser cache can serve the old bin.
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
git push origin HEAD:main
LANDING="${LANDING:-$(cd .. && pwd)/esp32/landing}"
if [ -f "$LANDING/sync-manifests.py" ]; then
  cd "$LANDING" && python3 sync-manifests.py
else
  echo "! 没找到 $LANDING/sync-manifests.py，manifest 未同步" >&2
fi
