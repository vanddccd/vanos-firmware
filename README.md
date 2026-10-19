# VanOs 固件（ESP32-S3 墨水屏阅读器）

read_pico 板（1216×684 墨水屏）固件，用于《文库本 VanOs》。

## 刷机

**整片刷（推荐，第一次刷/对方是别的固件时）**：

```bash
esptool --chip esp32s3 -b 460800 --before default-reset --after hard-reset \
  write-flash --flash-mode dio --flash-freq 80m --flash-size 16MB \
  0x0 merged-binary.bin
```

**只刷应用（对方已经是 VanOs 固件时，快）**：

```bash
esptool --chip esp32s3 -b 460800 --before default-reset --after hard-reset \
  write-flash --flash-mode dio --flash-freq 80m --flash-size 16MB \
  0x10000 vanos-app.bin
```

## SD 卡要求

TF 卡（FAT32）根目录需要：

```
/sdcard/VanOS/fonts/朱雀仿宋.ttf   ← 必须，缺了没字
/sdcard/VanOS/BOOKS/*.epub         ← 书，可空
```

其余目录（`VanOS/`、`BOOKS/`、`EPUB_COVER/`、`fonts/`、`assets/fonts/`）首次启动自动创建。

```
/sdcard/pictures/*.png             ← 透明书封的源图（可选，自己放）
```

`/pictures/` 原本是官方固件的目录，VanOs 从 2026-10-19 起用它做**透明书封**的图源：
阅读菜单「显示 → 启用书封」会列出这个目录下的 `.png`，选一张之后按电源键进睡，
当前屏幕就会和它合成成关机图。书封按**每本书**记住，帧存在 `VanOS/.bkcover/`。

## 文件

| 文件 | 说明 |
|---|---|
| `merged-binary.bin` | 完整镜像，从 0x0 刷（bootloader + 分区表 + app + ota_data） |
| `vanos-app.bin` | 仅应用，从 0x10000 刷 |
