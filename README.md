# VanOs 固件（ESP32-S3 墨水屏阅读器）

read_pico 板（1216×684 墨水屏）固件，用于《文库本 VanOs》。

## 当前版本（2026-10-20）

- 传书页 / 选择 WiFi / 密码页改版：纸页式无框列表、`←` 与全站统一、标题行整行可点返回、网络按信号强度排序、上下滑动翻页（局部刷）、「重新扫描」容器级热区且扫描完成才刷新
- **联网校时**：设置 → 系统 →「联网校时」（复用已保存 WiFi 连 STA + SNTP，写 PMU RTC）
- 发布版**静默日志**（默认 WARN，串口不刷屏）
- 修复：书封流式解码 gamma 未初始化导致纯黑；清空记录同时清书签与书封缓存；休眠书封过渡改为黑→白→渲染

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
