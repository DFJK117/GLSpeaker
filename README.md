# GLSpeaker

声音可视化播放器（Haxe + Lime 重写版）。**全 OpenGL 渲染**（喇叭鼓动 / 果冻缩放 / 圆形频谱全走 GPU shader），**FFT 跑在后台线程**（hxcpp 原生线程），无粒子、无波浪线条。

> 本项目是对一个 Android 声光可视化 App（yzrilyzr.blplayer）的重写：保留"喇叭鼓动 + 果冻缩放 + 频谱"核心视觉，删除粒子与波浪线条，新增「仅增益图形不增益音频」开关。

## 特性

- **纯 OpenGL 渲染**：两个 shader 管线（平色 + 纹理），果冻缩放在顶点着色器完成，零 CPU 光栅化
- **多线程**：桌面版用 `sys.thread.Thread` + 互斥队列，FFT/压缩器在后台线程跑
- **压缩器面板**：增益(0.5x~4x)、阈值(-60~0dB)、比率(1:1~20:1)
- **仅增益图形不增益音频**：开启后增益只放大可视化反应，不动播放音量
- **音频来源**：桌面 = 把音乐文件拖到 exe 上 / 放进 `music/` 文件夹 / 控制台输入路径；Web = 文件选择框
- **未加载文件时**自动播放"演示信号"（扫频 + 节拍包络），打开就有画面

## 快捷键

| 键 | 功能 |
|---|---|
| 空格 | 播放 / 暂停 |
| ← / → | 上一首 / 下一首（music 文件夹歌单） |
| O | 打开文件（桌面=控制台输入路径；Web=文件框） |

## 构建

```bash
haxelib install lime 7.9.0 --always
haxelib install hxcpp 4.2.1 --always

# Windows 原生 exe（需要 MSVC）
haxelib run lime build windows -release

# Web 版（无需任何编译器，也是 CI 的类型检查手段）
haxelib run lime build html5
```

产物在 `export/windows/bin/`（exe）与 `export/html5/bin/`（网页）。

也可直接用本仓库的 GitHub Actions（`.github/workflows/build.yml`）：push 即自动产出 Windows exe 与 Web 版 artifact。

## 字体图集

UI 文字使用预烤图集（`assets/font_atlas.png` + `font_atlas.json`），由 `tools/gen_font_atlas.py` 生成（Python + PIL，微软雅黑）。修改 UI 文案后重新生成：

```bash
python tools/gen_font_atlas.py
```

## 与原版（Android）的对应

| 原版 | 本项目 |
|---|---|
| `MainView.onDraw` 分层绘制 | `gl/GLRenderer` 四个 GL Pass |
| `RMSDrawable`（喇叭鼓动，边缘双柱） | Pass3 边缘 RMS 柱 |
| `boomdelet.vec` 中心 logo + 低频缩放 | Pass2 GL 喇叭图标 + 顶点着色器果冻缩放 |
| `FFTBarDrawable`（圆形频谱，Complex FFT） | Pass2 圆形频谱 + `dsp/FFT`（radix-2，后台线程） |
| `ParticleDrawable` / `RollingDrawable` | **按需求移除** |
| `Pcm$Compressor` | `dsp/Compressor`（作用于分析信号） |

## License

MIT
