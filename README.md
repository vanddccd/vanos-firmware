# VanOs 固件（ESP32-S3 墨水屏阅读器）

read_pico 板（1216×684 墨水屏）固件，用于《文库本 VanOs》。

## 当前版本（2026-10-22）

**阅读历史弹窗重做**（阅读菜单底部右半「阅读历史」）

- 九行等权键值表 → 书名 + 大号累计时长 + 进度条 + 两列元数据 + 三个时间戳
- 容器改用与字体弹窗同一份底部抽屉规格（顶栏 72、标题下引线、X 热区 114、把手）。
  顺带修掉一个真 bug：旧版自己画 56 高的顶栏，关闭热区却按 72 算，点第一行右侧会误关
- 行高固定、字号默认，只有放不下的那一项自己缩（缩到 20px 才截断），行高不动
- 三个时间戳用**等宽数字**：字体的数字是比例宽的（`1` 比 `0` 窄），同格式的时间戳
  像素宽度能差一个字，看上去就是「少一个字」

**修复：累计阅读时长恒为 0 秒**

- `catalog_sync_reading()` 与 `history_write()` 各自内联了一份「阅读情况」拷贝逻辑，
  两边都漏了 `read_sec` / `sessions` ⇒ 落盘永远写 0。抽成唯一出入口 `reading_group_copy()`
- 读不满 60 秒就退出会整段丢失（置脏要等攒满一分钟，而 force 落盘过不了脏标记那关）
- 浅睡（书封档 / 睡眠档=浅睡）不调 `on_exit` ⇒ 那条路从不落盘；且醒来那一拍会把
  整段锁屏时间当成阅读时间。新增 `on_lock_flush` 回调 + 单拍增量封顶 5 秒
- 打开次数、章节数也一并修（前者读了滞后的副本，后者按契约在设备上恒为 0）
- 看菜单 / 查目录 / 加签 / 看注脚弹层**不计入**阅读时长

**联网校时不再跳传书页**

- 设置 → 系统 →「联网校时」现在在**设置页内**开选网弹窗（与字体弹窗同一套抽屉规格），
  扫描、选网、输密码、连接、校时全程不离开设置页
- 文本四态：未校对 →（点）→ 校对中 → 校对完成 →800ms→ 上次校对时间（存 NVS，重启可见）
- WiFi 密码输入页抽成公用件 `main/vanos/wifi_keypad.c`，不重复造轮子
- 传书页本身**零改动**（热点 + 连 WiFi 功能不受影响）

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
