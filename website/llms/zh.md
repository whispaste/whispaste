# WhisPaste

> WhisPaste 是一款适用于 Windows、Apple Silicon Mac 和 Linux 的听写应用：按下快捷键、开口说话，文字就会出现在你正在输入的文本框中。语音识别在你的电脑上本地运行，无需账户。它以 MIT 许可证开源，在 GitHub 上免费提供；Microsoft Store 和 Mac App Store 版本为一次性购买，没有订阅；购买不会解锁任何功能。

## WhisPaste 能做什么

- 在任意应用中说话时按住全局快捷键，松开即停止；也可以按一下开始、再按一下停止。
- WhisPaste 在你的电脑上转写录音，并把文字复制到剪贴板。开启自动粘贴后，它会把文字插入当前应用的光标处，几乎适用于任何应用。
- 适合在电脑前大量书写的人：邮件、消息、文档、笔记、提示词和代码注释。

## WhisPaste 在基础之上还提供什么

本地运行、无需账户、可免费使用是基础。在此之上，WhisPaste 还提供：

- 自带现成模式的智能模式：在粘贴前清理、缩短，或翻译成七种语言之一。想改选中的文字，只要说出要怎么改。
- 智能模式使用本地文本模型，你需要时由 WhisPaste 自行下载，不必另装软件（Linux 上为实验功能）。也可以改用自己的 OpenAI 密钥。
- 录音、笔记和文本块在同一个编辑器里，工具栏、快捷键和自动保存都一样。
- 带替换规则的词典，会根据你的修改建议新的替换。
- 历史、笔记、词典、文本块和保留的录音都用你设备自己的数据密钥加密保存。
- 上架 Microsoft Store 和 Mac App Store：在 Windows 上安装时不会出现 SmartScreen 警告，并通过商店在后台更新；在 Mac 上通过 App Store 安装和更新。一次性购买，无需订阅；购买用于支持后续开发。

## 语音识别

- 两个本地引擎：Whisper（whisper.cpp，99 种语言，多种模型大小）和 Parakeet（约 25 种欧洲语言，即使没有 GPU 也很快）。
- 一次性下载模型后，本地识别可离线使用。
- GPU 不是必需的。在 Apple Silicon 上使用 Metal 加速，在 Windows 和 Linux 上使用 Vulkan；NVIDIA 显卡可选装 CUDA 包。没有 GPU 时，识别在 CPU 上运行。
- 可选的云端识别：通过 OpenAI 或 Deepgram，使用你自己的 API 密钥。
- 在 macOS 26 或更高版本的 Mac 上，还可以选择 Apple 的设备端语音识别作为第三种方案。

## Smart Mode（可选，默认关闭）

- “整理”去除口头禅并修正标点，“精简”缩短文本，“翻译”将其译为德语、英语、西班牙语、法语、葡萄牙语、普通话或俄语。
- 可在本地运行（macOS 和 Windows；Linux 上为实验性），也可通过 OpenAI 使用你自己的 API 密钥。
- 可用自己的指令（最多 500 个字符）保存自定义预设，并在之后将预设应用到较早的录音上，原文会保留。除了 OpenAI，也可以使用本机或局域网中自己的兼容服务器（例如 Ollama、LM Studio、llama.cpp 或 KoboldCpp）。

## 日常功能

- 本地“录音”页面，支持搜索、筛选、自动保存和版本历史；笔记支持标题、图片、清单、阅读视图和专注模式。
- 文本片段：保存的文本块，可通过快捷键或说出的触发词插入；交互式片段会引导你填写模板。
- 文件导入：转写音频（WAV、MP3、FLAC、M4A、AAC、Ogg、Opus）和视频文件（MP4、MOV、MKV、WebM），最大 1 GB、6 小时。也可以直接从文件管理器发送音频文件：在 Mac、Linux 和 Windows 的 Microsoft Store 版本中使用“打开方式”，使用网站上的 Windows 安装程序时右键点击。
- 可选：WhisPaste 在 Windows 和 Linux 上于口述期间暂停音乐和视频；“粘贴后发送”会在粘贴后按下回车（松开快捷键时按住 Alt；Linux 上仅限 X11）。
- “Even out volume automatically”（默认开启）会在识别前提升较轻的语音，不会放大静音或噪声。
- 最多五种用星标收藏的识别语言排在语言菜单最前面，可用快捷键在它们之间切换。
- 词汇表保存人名和专业术语；替换规则纠正常见拼写，WhisPaste 还会根据你的重复纠正给出新建议。
- 配置文件可为特定应用设定语言、语音模型、智能模式、麦克风和输出方式。
- 修改选中内容（可选，默认关闭）：在受支持的应用中选中文字，按下对应的快捷键并说出要改什么，例如“更短”或“翻译”；智能模式会改写选中的内容。
- 如果转写失败，音频默认保留 24 小时，即使应用崩溃也不例外，方便你重试。
- 无障碍：设置、笔记和编辑器工具都能用键盘和屏幕阅读器操作；使用单击模式就无需按住按键。

## 隐私

- 使用本地识别时，音频留在你的电脑上，转写后即被丢弃，除非你开启了音频保留。
- 在 Windows 和 GitHub 版 macOS 应用中，WhisPaste 不会自动粘贴到密码框中，文字会保留在剪贴板里。
- 转写文本、笔记、词汇表、语音片段和保留的音频均加密保存，数据密钥存放在系统的密钥存储中（macOS 钥匙串、Windows 数据保护、Linux Secret Service）。你可以将密钥备份为恢复码或文件。
- 无需账户。
- 匿名使用统计和崩溃报告默认开启。它们不包含音频、转写内容或历史记录，可在“设置 → 隐私”中分别关闭。
- 云端功能只会在你使用时，把数据发送给你选择的服务商。

## 平台与配置要求

- Windows 10 或更高版本，Apple Silicon 上的 macOS 13 Ventura 或更高版本（不支持 Intel Mac），Linux x64（AppImage、.deb、tar.gz），需要 Ubuntu 26.04 或更高版本（glibc 2.43）；更旧的 Linux 系统请继续使用 1.4.2 版。
- Linux 版支持 X11 和 Wayland。在 Wayland 下，全局快捷键由桌面环境绑定（GNOME 和 KDE 通过快捷键门户，或使用运行 `whispaste --toggle` 的自定义快捷键）；单键快捷键、双击和“粘贴后发送”等少数附加功能需要 X11。Linux 上的自动粘贴需要一次性授权（uinput 键盘或桌面门户）；未授权时，文字会保留在剪贴板中。
- 建议：至少 8 GB 内存和 64 位处理器。
- 仅限桌面；没有 iOS 或 Android 版本。

## 如何获取 WhisPaste 以及费用

- 在 GitHub 上免费获取完整应用（MIT 许可证）：Windows 安装程序（WhisPaste-Setup.exe）或便携版 ZIP、macOS DMG、Linux AppImage、.deb 和 tar.gz。包管理器：Windows 上的 winget（`SilvioLindstedt.WhisPaste`）和 Scoop，macOS 上的 Homebrew。你也可以从源代码自行构建。
- Microsoft Store（Windows）和 Mac App Store（macOS）：一次性购买，没有订阅。当前价格以商店显示为准。
- 商店版本的额外便利：在 Windows 上，安装时不会出现 GitHub 未签名安装程序可能触发的 SmartScreen 警告，并通过 Microsoft Store 自动更新；在 macOS 上，通过 App Store 安装和更新。购买费用用于支持后续开发。
- 购买不会解锁任何功能；免费版本始终完整，没有任何功能锁定或时间限制。Windows 和 macOS 的 GitHub 版本会检查新版本，只有在你确认后才安装更新；在 Linux 上，WhisPaste 只会提示有新版本并提供链接，需要你手动安装。
- 各版本的区别：适用于较新 NVIDIA 显卡的可选 CUDA 包仅在 GitHub 版本（Windows 和 Linux）中提供，Microsoft Store 版本不提供；两者都支持通过 Vulkan 进行 GPU 加速。Mac App Store 版本运行在 Apple 的应用沙盒中：无法从你在其他应用中所做的更正中学习，不能识别密码框，没有 AppleScript 粘贴备用方式，也没有修复 macOS 权限的工具；GitHub 版本具备以上全部功能。Mac App Store 目前提供的仍是较旧的版本，音频和视频文件导入将随下一次商店更新到来。
- 由于 Apple 会审核每次更新，新版本在 Mac App Store 上线的时间可能晚于 GitHub。
- 没有订阅，也无需账户。如果你选择云服务商（OpenAI 或 Deepgram），其使用费用会通过你自己的 API 密钥直接向你收取。

## WhisPaste 与系统自带听写的区别

- Windows 自带的语音输入（Win+H）使用 Microsoft 的在线语音识别，需要联网。WhisPaste 在你的电脑上识别语音，一次性下载模型后即可离线使用。
- macOS 自带的听写只使用 Apple 的语音识别。在 WhisPaste 中，你可以选择 Whisper、Parakeet、Apple 设备端识别（macOS 26 或更高版本）或使用自己密钥的云服务商。
- 许多 Linux 桌面环境根本没有听写功能。WhisPaste 也为 Linux 提供听写功能，Wayland 下的限制见上文。
- 系统自带听写会边说边输入。WhisPaste 在你说完后插入完整文字，将其保存在可搜索的“录音”区域，应用你的词典和文本片段，可以用智能模式整理文字，还能转写音频和视频文件。

## 链接

- [网站](https://whispaste.de/zh/)
- [下载](https://whispaste.de/zh/download/)
- [隐私政策](https://whispaste.de/zh/privacy/)
- [更新日志](https://whispaste.de/zh/changelog/)
- [GitHub 上的源代码](https://github.com/whispaste/whispaste)
- [Microsoft Store](https://apps.microsoft.com/detail/9p22jvkrq2v0)
- [Mac App Store](https://apps.apple.com/app/id6795319409)
- [GitHub 上的最新版本](https://github.com/whispaste/whispaste/releases/latest)
