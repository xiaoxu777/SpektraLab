# FilmLab

[English](README.md) · **简体中文**

FilmLab 是 ericxu 做的 Mac 胶片暗房。打开一张 RAW，选一种胶片和相纸，得到一张按物理模型冲印出来的照片；
再加上片边、日期或水印，按要发去的地方导出。

## 能做什么

- **五个模式：** 图库 · 冲洗 · 二级调色 · 个性化 · 导出。**普通 | 专业** 切换：普通只留常用选择，专业给出全部控件。
- **光谱模拟，不是 LUT。** 光线穿过胶片和相纸的染料层，带颗粒、光晕和放大机滤色，全尺寸约一秒出图。
- **胶片本身。** 片边：135、半格、XPan、Super 8、645 到 6×17，扫描质感 干净 / 自然 / 明显；日期后背；
  文字、手写或 PNG 水印；手写签名。
- **按用途导出。** 微信朋友圈、Instagram、微博、小红书、发给朋友、保存到电脑，各按平台保留的尺寸导出；
  能在手机样子里预览，可加白边或黑边。
- **导入**：从存储卡和文件夹一次导入多张，目录留在你自己的 Mac 上。
- **简体中文、繁體中文、日本語、English。**

## 编译

需要 Apple 芯片、macOS 14 或更新，Xcode 27 或更新并装好 Metal 工具链
（`xcodebuild -downloadComponent MetalToolchain`）。

```bash
app/SpektraLab/tools/build_engine_mac.sh      # 引擎和资源：第一次，以及 engine/ 有改动之后
cd app/SpektraLab
python3 gen_project.py                        # 按源码生成 Xcode 工程
zsh tools/filmlab_build.sh                    # 编译 Release 版
zsh tools/install_filmlab.sh                  # 装到 /Applications（会关掉正在运行的 FilmLab）
zsh tools/filmlab_dmg.sh                      # 可选：打包 DMG
```

## 致谢

FilmLab 建立在两个项目之上，感谢它们：

- **[SpektraLab](https://github.com/JamesQiu2005/SpektraLab)**，作者 JamesQiu2005（Hanze Qiu），
  GPL-3.0-or-later。FilmLab 从 SpektraLab 修改而来；引擎、目录和 App 的很多部分是 SpektraLab 的成果。
- **[spektrafilm](https://github.com/andreavolpato/spektrafilm)**，作者 Andrea Volpato，GPL-3.0-or-later。
  胶片模拟、实测的胶片和相纸数据、冲印和扫描模型来自 spektrafilm；这些数据和由它烘焙的 LUT 采用 CC BY-SA 4.0。

FilmLab 与这两个项目没有隶属关系，也未获它们背书。

## 许可

GPL-3.0-or-later（`license/LICENSE`）。spektrafilm 的数据、LUT 及其直接衍生物为 CC BY-SA 4.0
（`license/SPEKTRAFILM_LICENSE.txt`）。FilmLab 来自哪里、改了什么，见 `license/NOTICE.md`；
其他组件（metal-cpp、spklib、LibRaw）及其许可也列在那里。
