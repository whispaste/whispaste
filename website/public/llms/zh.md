# WhisPaste

> WhisPaste 是一款免费的语音输入应用，采用 MIT 许可证，支持 Windows、Apple Silicon Mac 和 Linux：按下快捷键、开口说话，文字就会出现在当前的文本框中。语音识别在你的电脑上本地运行。

## WhisPaste 能做什么

- 在任意应用中说话时按住全局快捷键，松开即停止；也可以按一下开始、再按一下停止。
- WhisPaste 在你的电脑上转写录音，并把文字复制到剪贴板。开启自动粘贴后，它会把文字插入当前应用的光标处，几乎适用于任何应用。
- 适合在电脑前大量书写的人：邮件、消息、文档、笔记、提示词和代码注释。

## 语音识别

- 两个本地引擎：Whisper（whisper.cpp，99 种语言，多种模型大小）和 Parakeet（约 25 种欧洲语言，即使没有 GPU 也很快）。
- 一次性下载模型后，本地识别可离线使用。
- GPU 不是必需的。在 Apple Silicon 上使用 Metal 加速，在 Windows 和 Linux 上使用 Vulkan；NVIDIA 显卡可选装 CUDA 包。没有 GPU 时，识别在 CPU 上运行。
- 可选的云端识别：通过 OpenAI 或 Deepgram，使用你自己的 API 密钥。
- 在 macOS 26 或更高版本的 Mac 上，还可以选择 Apple 的设备端语音识别作为第三种方案。

## Smart Mode（可选，默认关闭）

- “整理”去除口头禅并修正标点，“精简”缩短文本，“翻译”将其译为德语、英语、西班牙语、法语、葡萄牙语、普通话或俄语。
- 可在本地运行（macOS 和 Windows；Linux 上为实验性），也可通过 OpenAI 使用你自己的 API 密钥。
- 可用自己的指令（最多 500 个字符）保存自定义预设，并在之后将预设应用到较早的录音上，原文会保留。除了 OpenAI，也可以使用本机或局域网中自己的兼容服务器（例如 LM Studio 或 Ollama）。

## 日常功能

- 本地“录音”页面，支持搜索、筛选、自动保存和版本历史；笔记支持标题、图片、清单、阅读视图和专注模式。
- 文本片段：保存的文本块，可通过快捷键或说出的触发词插入；交互式片段会引导你填写模板。
- 文件导入：转写音频（WAV、MP3、FLAC、M4A、AAC、Ogg、Opus）和视频文件（MP4、MOV、MKV、WebM），最大 1 GB、6 小时。也可以直接从文件管理器发送音频文件：在 Mac、Linux 和 Windows 的 Microsoft Store 版本中使用“打开方式”，使用网站上的 Windows 安装程序时右键点击。
- 可选：WhisPaste 在 Windows 和 Linux 上于口述期间暂停音乐和视频；“粘贴后发送”会在粘贴后按下回车（松开快捷键时按住 Alt；Linux 上仅限 X11）。
- “Even out volume automatically”（默认开启）会在识别前提升较轻的语音，不会放大静音或噪声。
- 最多五种用星标收藏的识别语言排在语言菜单最前面，可用快捷键在它们之间切换。
- 词汇表保存人名和专业术语；替换规则纠正常见拼写，WhisPaste 还会根据你的重复纠正给出新建议。
- 配置文件可为特定应用设定语言、语音模型、智能模式、麦克风和输出方式。
- 如果转写失败，音频默认保留 24 小时，即使应用崩溃也不例外，方便你重试。
- 无障碍：设置、笔记和编辑器工具都能用键盘和屏幕阅读器操作；使用单击模式就无需按住按键。

## 隐私

- 使用本地识别时，音频留在你的电脑上，转写后即被丢弃，除非你开启了音频保留。
- 在 macOS 和 Windows 上，WhisPaste 不会自动粘贴到密码框中，文字会保留在剪贴板里。
- 转写文本、笔记、词汇表、语音片段和保留的音频均加密保存，数据密钥存放在系统的密钥存储中（macOS 钥匙串、Windows 数据保护、Linux Secret Service）。你可以将密钥备份为恢复码或文件。
- 无需账户。
- 使用统计和崩溃报告不包含音频、转写内容或历史记录，可在“设置 → 隐私”中关闭。
- 云端功能只会在你使用时，把数据发送给你选择的服务商。

## 平台与配置要求

- Windows 10 或更高版本，Apple Silicon 上的 macOS 13 Ventura 或更高版本（不支持 Intel Mac），Linux x64（AppImage、.deb、tar.gz），需要 Ubuntu 26.04 或更高版本（glibc 2.43）；更旧的 Linux 系统请继续使用 1.4.2 版。
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
