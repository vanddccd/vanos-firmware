#!/bin/sh
# 用法: ./flash.sh [PORT]       整片刷
#       ./flash.sh [PORT] app   只刷应用
PORT="${1:-/dev/cu.usbmodem101}"
[ "$2" = "app" ] || { esptool --chip esp32s3 -b 460800 --before default-reset --after hard-reset \
  write-flash --flash-mode dio --flash-freq 80m --flash-size 16MB 0x0 merged-binary.bin; exit 0; }
esptool --chip esp32s3 -b 460800 --before default-reset --after hard-reset \
  write-flash --flash-mode dio --flash-freq 80m --flash-size 16MB 0x10000 vanos-app.bin
