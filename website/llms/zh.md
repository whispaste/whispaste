# WhisPaste

> WhisPaste 是一款免费的语音输入应用，采用 MIT 许可证，支持 Windows、Apple Silicon Mac 和 Linux：按下快捷键、开口说话，文字就会出现在当前的文本框中。语音识别在你的电脑上本地运行。

## WhisPaste 能做什么

- 在任意应用中按下全局快捷键，说话，再按一次（或说话时一直按住）。
- WhisPaste 在你的电脑上转写录音，并把文字复制到剪贴板。开启自动粘贴后，它会把文字插入当前应用的光标处，几乎适用于任何应用。
- 适合在电脑前大量书写的人：邮件、消息、文档、笔记、提示词和代码注释。

## 语音识别

- 两个本地引擎：Whisper（whisper.cpp，99 种语言，多种模型大小）和 Parakeet（约 25 种欧洲语言，即使没有 GPU 也很快）。
- 一次性下载模型后，本地识别可离线使用。
- GPU 不是必需的。在 Apple Silicon 上使用 Metal 加速，在 Windows 和 Linux 上使用 Vulkan；NVIDIA 显卡可选装 CUDA 包。没有 GPU 时，识别在 CPU 上运行。
- 可选的云端识别：通过 OpenAI 或 Deepgram，使用你自己的 API 密钥。

## Smart Mode（可选，默认关闭）

- “整理”去除口头禅并修正标点，“精简”缩短文本，“翻译”将其译为德语、英语、西班牙语、法语、葡萄牙语、普通话或俄语。
- 可在本地运行（macOS 和 Windows；Linux 上为实验性），也可通过 OpenAI 使用你自己的 API 密钥。

## 日常功能

- 本地转写历史和独立的快速笔记。
- 文本片段：保存的文本块，可通过快捷键或说出的触发词插入；交互式片段会引导你填写模板。
- 文件导入：转写已有的音频文件。

## 隐私

- 使用本地识别时，音频留在你的电脑上，转写后即被丢弃，除非你开启了音频保留。
- 无需账户。
- 使用统计和崩溃报告不包含音频、转写内容或历史记录，可在“设置 → 隐私”中关闭。
- 云端功能只会在你使用时，把数据发送给你选择的服务商。

## 平台与配置要求

- Windows 10 或更高版本，Apple Silicon 上的 macOS 12 Monterey 或更高版本（不支持 Intel Mac），Linux x64（AppImage、.deb、tar.gz）。
- 建议：至少 8 GB 内存和 64 位处理器。
- 仅限桌面；没有 iOS 或 Android 版本。

## 价格与许可证

- 完整应用在 GitHub 上以 MIT 许可证免费提供。
- Microsoft Store 和 Mac App Store 中的付费版本提供相同的核心功能，并通过商店更新。
- 无需订阅。可选的云服务商可能会对其使用收费。

## 链接

- [网站](https://whispaste.de/zh/)
- [下载](https://whispaste.de/zh/download/)
- [隐私政策](https://whispaste.de/zh/privacy/)
- [更新日志](https://whispaste.de/zh/changelog/)
- [GitHub 上的源代码](https://github.com/whispaste/whispaste)
