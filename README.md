# PodPointer

**把 AirPods 充电盒变成 Mac 鼠标。**
转动盒子移动光标，轻敲盒子正面点击。

[English](README.en.md)


> 个人实验项目，与 Apple 无关，也未获其认可。

## 原理

充电盒本身没有可读取的运动传感器，但耳机有；耳机放在盒子里时，会跟着盒子一起动。

```
 开盖、耳机留在盒内 ──IMU──▶ CMHeadphoneMotionManager（约 50 Hz）
                                      │
           角速度 ────────────────────┼──▶ 光标速度（CGEvent）
           加速度尖峰 ────────────────┘──▶ 左键点击
```

* **移动**：用转动的**角速度**控制光标的**速度**（陀螺仪鼠标的思路），不会漂移，也不需要回中。
  左右 = 绕重力方向的转动；上下 = 绕校准得到的俯仰轴的转动。
* **点击**：手指敲击是"先安静、再突然出现、又迅速回落"的加速度尖峰。挥动盒子虽然幅度大，
  但变化平缓且伴随转动，会被忽略。点击位置取敲击把盒子震歪**之前约 100 毫秒**的光标位置。
* **校准**：先拿稳不动，再像点头一样转几下。结果按左右耳分别保存并自动沿用，通常只需做一次。

## 环境要求

* macOS 14 Sonoma 及以上（Mac 上读取耳机运动数据从 macOS 14 开始支持）。
* 支持**空间音频头部追踪**的 AirPods（如 AirPods 第三代及以后、AirPods Pro、AirPods Max）。
  更早的 AirPods 不提供运动数据。
* 编译需要 Xcode 命令行工具（`xcode-select --install`）。

开发和测试环境为 macOS 26.5 + 一副 AirPods。其他支持头部追踪的型号理论上可用，但未经验证，欢迎反馈。

## 安装与使用

### 1. 关闭「自动入耳检测」（必须）

macOS 只有在 AirPods 是当前音频输出设备时才推送运动数据；开着入耳检测时，放在盒里的耳机永远不会被当成"已佩戴"。

*系统设置 › 你的 AirPods › 自动入耳检测* → **关闭**。

这个设置存在耳机上，iPhone 那边也会一起关掉，用完记得打开。

### 2. 编译

```bash
git clone https://github.com/chroya/PodPointer.git && cd PodPointer
scripts/setup-signing.sh   # 可选但推荐，见下文
scripts/build.sh
```

`setup-signing.sh` 会在一个**独立的**钥匙串里生成自签名的代码签名证书（不改动登录钥匙串）。
用它签名后 App 身份固定，重新编译不用再授权「辅助功能」。不运行它的话每次都是临时签名，
每次重新编译后都要重新勾选一次。

### 3. 运行

```bash
scripts/run.sh
```

首次启动系统会请求两项权限：

| 权限 | 用途 |
|---|---|
| **运动与健身** | 读取 AirPods 运动传感器 |
| **辅助功能** | 移动光标和点击（没有它，鼠标事件会被系统静默丢弃） |

菜单栏会出现 **PP**（`PP⚠︎` = 缺权限，`PP●` = 指点中）。

### 4. 使用

1. 打开盒盖，耳机留在盒内。PodPointer 会自动把系统音频输出切到 AirPods（`--no-route` 可关闭）。
2. 仅首次：按屏幕顶部的引导操作——竖起盒子拿稳不动，然后像点头一样（顶部先往后仰、再往前低）来回 3~4 次。
3. 转动盒子移动光标；先停稳，再轻敲盒子正面点击，快速敲两下为双击。

菜单：**重新校准**（⌘R）· **暂停 / 继续**（⌘P）· **打开日志** · **打开辅助功能设置** · **退出**。

## 参数

参数传给 `scripts/run.sh`（或 `open build/PodPointer.app --args …`），都不需要重新编译。
最近一次 `scripts/run.sh` 用的参数会被记住，不带参数启动（比如从访达双击）时自动沿用。

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--gain <px/rad>` | 1400 | 指针速度 |
| `--accel <n>` | 0.8 | 快速转动时的额外加速 |
| `--deadzone <rad/s>` | 0.03 | 低于此角速度视为手抖 |
| `--smooth <0–1>` | 0.35 | 平滑系数，越大越跟手、也越抖 |
| `--invert-x` / `--invert-y` | 关 | 反转某个方向 |
| `--tap <g>` | 0.20 | 敲击最小力度 |
| `--jerk <g>` | 0.20 | 敲击最小突变量 |
| `--decay <0–1>` | 0.7 | 敲击回落速度要求 |
| `--quiet-a <g>` / `--quiet-w <rad/s>` | 0.35 / 1.8 | 敲击前允许的最大晃动 |
| `--no-route` | | 不自动切换音频输出 |
| `--lang en\|zh` | 跟随系统 | 界面语言 |
| `--probe` | | 诊断：只记录传感器数据，不移动光标 |
| `--tap-debug` | | 记录每个被拒绝的敲击候选及原因 |
| `--hud-demo` | | 轮播所有引导状态，并把截图存到 `/tmp/podpointer-hud/` |

## 已知限制

* **必须开着盖子。** 合盖后传感器仍在工作，但 AirPods 大约 15~25 秒后会断开蓝牙；持续播放听不见的音频也无法阻止。
* 使用期间**音频输出会切到 AirPods**。
* **必须关闭自动入耳检测**，这会同时影响 iPhone 上的行为。
* 运动数据约 50 Hz，光标按 120 Hz 插值，做精细操作不如真鼠标。
* 敲击识别基于经验规则：很轻的敲击可能漏掉，剧烈晃动偶尔可能误点，可用 `--tap-debug` 配合上面的参数调整。
* 目前只有左键（单击/双击/三击），还没有右键、拖拽和滚动。

## 常见问题

| 现象 | 检查 |
|---|---|
| 没有运动数据，日志提示 *No Bluetooth output device* | 自动入耳检测没关，或盒盖是合上的 |
| 有数据但光标不动 | 辅助功能权限：删掉旧的 PodPointer 条目，重新添加 `build/PodPointer.app` |
| 上下方向反了 | 重新校准（⌘R），第一下要往后仰；或加 `--invert-y` |
| 敲击漏识别 / 误点 | 加 `--tap-debug` 运行，敲几下，对照日志里的数值调参数 |

日志：`~/Library/Logs/PodPointer.log` · 校准数据：`~/Library/Application Support/PodPointer/calibration.json`。
所有数据都留在本机，PodPointer 不联网。

## 目录结构

```
Sources/
  main.swift              入口
  AppDelegate.swift       菜单栏、引导浮窗接线、--hud-demo
  PointerEngine.swift     运动数据 → 校准 → 光标 / 点击
  TapDetector.swift       敲击识别
  CalibrationStore.swift  按耳机保存俯仰轴
  AudioRoute.swift        CoreAudio：把输出切到 AirPods
  Mouse.swift             CGEvent 输出与辅助功能权限
  HUD.swift               屏幕引导浮窗
  ClickRipple.swift       点击反馈动画
  Config.swift、L10n.swift、Log.swift
scripts/
  build.sh                编译 + 打包 + 签名 → build/PodPointer.app
  run.sh                  启动并跟踪日志
  setup-signing.sh        一次性生成本地签名证书
  test.sh                 运行敲击识别测试
Tests/
  main.swift              敲击识别测试（基于真实日志构造的波形）
```

不需要 Xcode 工程，`swiftc` 直接编译 `Sources/*.swift`。
修改敲击识别后请运行 `scripts/test.sh`。

## 参与贡献

欢迎提 Issue 和 PR，特别是其他 AirPods 型号的测试反馈和更好的敲击识别方案。
反馈问题时请附上 `~/Library/Logs/PodPointer.log` 的相关片段（最好用 `--tap-debug` 或 `--probe` 采集）。

## 商标声明

AirPods 是 Apple Inc. 在美国及其他国家/地区的注册商标。

## 许可证

[MIT](LICENSE)
