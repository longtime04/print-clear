# 印得清 PrintClear

身份证、户口本排版打印工具：导入照片原图 → 抠图裁剪 → 排到一张 A4 上 → 导出打印，全程原图质量。

全程由 Muse 制作。

## 功能

- **导入**：从相册拿原图，不压缩；原图数据留着，可随时另存到相册。
- **抠图（两种都要）**
  - 证件抠边：自动认出证件边缘，拖四个角微调，透视拉正。
  - 人像去背景：只认得出人像，背景变透明，打印默认白底。
- **改尺寸**：身份证 85.6×54mm、一寸 25×35mm、二寸 35×49mm、户口本整页、A5、自定义；等比填满不拉伸。
- **素材库（历史库）**：裁好的图文先存进来（按打印尺寸存），随时加到排版页上；点名字改名，可删除。
- **排版（1.0.1 改版）**：一张 A4 上放多个不同的图文混排——从素材库加、加文字；拖动改位置，右下角拉大拉小，宽高毫米数也能直接改；自动排版按大小归类、一行一行摆满，排完还能手动改。同一素材加多次就能印多张。
- **导出打印**：PNG（300 DPI）、PDF（A4，图片原分辨率嵌入）、AirPrint 直接打印。
- **原图质量保证**：导入不压缩、裁剪动的是原始像素、导出 300 DPI；原图分辨率不够印到目标尺寸时会提醒。

## 隐私

全程离线，不联网、不上传，照片不出手机。身份证、户口本这类证件照只在本地处理。

## 安装

未签名 IPA（GitHub Actions 编出）+ 企业签自签安装：

1. 在 [Releases](../../releases) 或 Actions 产物里下载 `PrintClear-1.0.0-unsigned.ipa`
2. 用全能签等工具自签后安装
3. 首次打开允许访问相册（导入照片、保存原图）

要求 iOS 26.0+（iPhone / iPad，iOS 27 可用）。

## 构建

推到 `main` 即触发 GitHub Actions（macos-26 + Xcode 26.6），编出未签名 IPA：

```bash
xcodebuild archive -project PrintClear.xcodeproj -scheme PrintClear \
  -destination 'generic/platform=iOS' \
  -archivePath build/PrintClear.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## 许可证

自写代码，保留所有权利。
