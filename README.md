# FilmLab

**English** · [简体中文](README.zh-CN.md)

FilmLab is a film darkroom for the Mac, by ericxu. Open a RAW, pick a film and a paper, and get a
physically modelled print, then finish it with a film edge, a date back or a watermark and export it
for where it is going.

## What it does

- **Five modes:** 图库 Library · 冲洗 Develop · 二级调色 Grade · 个性化 Personalize · 导出 Export.
  **普通 | 专业** (Simple | Pro) switches between a short set of choices and every control.
- **Spectral film and paper, not a LUT.** Light is traced through the film's dye layers and the
  paper's, with grain, halation and the enlarger's filter pack, at full resolution in about a second.
- **The film itself.** Film edges in 135, half frame, XPan, Super 8, 645 to 6×17, with a clean,
  natural or strong scan finish; date back; text, handwritten or PNG watermarks; a signature pad.
- **Export by purpose.** 微信朋友圈, Instagram, 微博, 小红书, 发给朋友 or 保存到电脑, each at the
  size that platform keeps, with a phone preview of the post and an optional white or black border.
- **Import** from cards and folders, several at once, into catalogs that stay on your Mac.
- **简体中文, 繁體中文, 日本語 and English.**

## Build

macOS 14 or later on Apple silicon, Xcode 27 or later with its Metal toolchain
(`xcodebuild -downloadComponent MetalToolchain`).

```bash
app/SpektraLab/tools/build_engine_mac.sh      # the engine and its resources, once and after any change under engine/
cd app/SpektraLab
python3 gen_project.py                        # the Xcode project, generated from the source tree
zsh tools/filmlab_build.sh                    # the Release app
zsh tools/install_filmlab.sh                  # copies it to /Applications (quits a running FilmLab)
zsh tools/filmlab_dmg.sh                      # optional: a DMG
```

## Credits

FilmLab stands on two projects, with thanks:

- **[SpektraLab](https://github.com/JamesQiu2005/SpektraLab)** by JamesQiu2005 (Hanze Qiu),
  GPL-3.0-or-later. FilmLab began as a modified version of SpektraLab; its engine, its
  catalog and much of its app are SpektraLab's work.
- **[spektrafilm](https://github.com/andreavolpato/spektrafilm)** by Andrea Volpato,
  GPL-3.0-or-later. The film simulation, the measured film and paper profiles and the print and
  scan model are spektrafilm's. The profiles and the LUTs baked from them are CC BY-SA 4.0.

FilmLab is not affiliated with or endorsed by either project.

## Licence

GPL-3.0-or-later (`license/LICENSE`). The spektrafilm profiles, the LUTs and their direct
derivatives are CC BY-SA 4.0 (`license/SPEKTRAFILM_LICENSE.txt`). What FilmLab is derived from and
what it changed: `license/NOTICE.md`. Other components (metal-cpp, spklib, LibRaw) are listed there
with their licences.
