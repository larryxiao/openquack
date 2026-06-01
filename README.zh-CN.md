<p align="center">
  <img src="docs/images/banner.png" alt="OpenQuack — 开口说，立即输入,隐私优先。录音浮层显示 'Listening' 与实时音量条；菜单栏弹窗显示 'Pasted at cursor' 以及最近一次转写,底部带 Settings / Quit 按钮。">
</p>

<div align="center">

**OpenQuack** *开口说，立即输入。隐私优先。*

macOS 上的语音听写工具。一切都不离开你的设备 —— 音频不传、文本不传，什么都不传。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](docs/INSTALL.md)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)](docs/ROADMAP.md)

</div>

> 🌐 **机器翻译。** 欢迎母语者贡献 —— 提交 PR 或参见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。
> English: [README.md](README.md)

---

> 📢 **新版本 — [v2.0.0-alpha.17](https://github.com/larryxiao/openquack/releases/tag/v2.0.0-alpha.17):** 多语言自动检测现在真的好用了。说中文、粤语、日语，或者中英混着说("这个 PR 居然有 一百 条 comment"),OpenQuack 都能认出来并准确转写,不用手动切语言。([历史版本](https://github.com/larryxiao/openquack/releases))

## 这是什么

OpenQuack 是一个 macOS 菜单栏小程序。按一下快捷键开口说话,再按一下结束 —— 转写文本就出现在光标位置。能打字的地方,都能说话。

语音识别在你的 Mac 上完成。不上云、不要账号、不用注册、零遥测。

## 为什么要做

**本地。** 一切都在你的设备上运行 —— 录音、转写、可选润色。什么都不外传:不传音频、不传文本、零遥测、不用注册。机密内容从设计层面就保持机密。而且因为流程中没有任何 API 调用,所以一直能用 —— 离线、飞机上、企业防火墙后,都不影响。

**快。** Whisper 在 Apple Silicon 上的转写速度大约是说话耗时的五分之一。在 M4 / 16 GB 基准机型上,真实人类语音的词错误率约 ~2.6%。多数情况下比打字更快。长录音尤其快:五分钟的录音,停止后约三秒就转写完成,跟时长基本无关,因为我们在你说话的同时就一边切块转写了。完整测试矩阵见 [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)。

**开源。** MIT 许可证。每一行代码都可审计;每一次改动都在公开进行。你菜单栏里跑的版本,就是这个仓库里的版本。

## 你能得到什么

- **一键听写。** 选个快捷键(默认 ⌃⇧Space)。可设为切换式或按住说话。
- **全本地。** 语音识别在你 Mac 上跑。听写不需要联网 —— 离线、飞机上、隧道里、企业防火墙后,都能用。不用 API key,没有速率限制,不会服务中断。个人或工作场合,听写体验完全一样。
- **多语种,自动检测真的好用。** Whisper 支持 99 种语言。从 v2.0.0-alpha.17 起,自动检测能准确识别中文、粤语、日语、韩语等等,中英混说也没问题,不用手动切语言。想在很短的片段上再稳一点,也可以在设置里固定语言。
- **自动粘贴到光标位置**,适用于任何 app。(也可以回退到剪贴板,自己粘贴。)
- **智能格式化** —— 大写、句末标点、清理 "嗯/呃" 之类的填充词。
- **自定义词典** —— 让它认识你真正在用的专有名词和项目名。
- **静音自动停止。** 你说完了,OpenQuack 自己结束。
- **实时麦克风音量浮层**,看得见它正在听。
- **首次启动快速设置** —— 权限、快捷键,一分钟搞定。
- **极小。** 8 MB 的菜单栏 app,运行时只占约 120 MB 内存(模型计算交给神经网络引擎),加上首次运行时下载的语音模型。
- **开源**, MIT。

## 隐私,一屏说清

1. **什么都不离开你的设备 —— 音频、文本,什么都不传。** 录音和转写完全本地。永远是。
2. **没有数据分析、没有遥测、不用注册。**

完整的隐私契约见 [`docs/VISION.md`](docs/VISION.md#privacy-contract)。

## 即将到来

排队中的功能预览。两者都建立在今天已经发布的听写基础上。

**上下文感知转写。** OpenQuack 会读取你即将粘贴位置周围的文本 —— 光标上方那行、你所在的函数、你正在回复的聊天串 —— 把它作为上下文喂给语音模型。专业术语会根据你正在做的事情自动消歧(在终端里, "cloud code" 会被识别成 "Claude Code",而不是反过来)。需要手动调自定义词典的场景就少了。

**思考模式。** 转写后再加一遍处理,通过一个本地小型 LLM,把你说出来的原话变成你真正会按下发送键的书面句子。剔除冗余、收紧结构、关键词大写正确。默认关闭,一键开启。完全本地 —— Ollama 或 MLX-LM,你选。

时间表和 SPEC 详情见 [`docs/ROADMAP.md`](docs/ROADMAP.md)。

这只鸭子还有更大的计划。整体走向看 [`docs/VISION.md`](docs/VISION.md)。

## 安装

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

或 [下载 DMG](https://github.com/larryxiao/openquack/releases),拖进 Applications 文件夹。首次启动:右键 → **打开** → **打开**(一次性绕过 Gatekeeper)。

macOS 询问时授予 **麦克风** 权限,在 **设置 → 快捷键** 里选一个快捷键(默认 ⌃⇧Space)。

想要图文教程? 看 [`docs/TUTORIAL.md`](docs/TUTORIAL.md) —— 从安装到第一次听写,五分钟。

### 或者让你的 AI agent 来装

把这段贴给 Claude Code、Codex、opencode、Hermes 或类似工具:

```text
Install OpenQuack on this Mac:

  brew tap larryxiao/openquack https://github.com/larryxiao/openquack
  brew install --cask openquack

(Or grab the DMG from https://github.com/larryxiao/openquack/releases
and drag it into /Applications; first open right-click → Open → Open.)

Then launch /Applications/OpenQuack.app, grant Microphone, and pick a
hotkey in Settings → Shortcut. Default ⌃⇧Space.
```

更多选项(卸载、源码构建、首次运行下载了什么):见 [`docs/INSTALL.md`](docs/INSTALL.md)。

## 致谢

OpenQuack 站在了慷慨的开源工作的肩膀上。特别感谢:

- [**OpenAI Whisper**](https://github.com/openai/whisper) —— 让这一切成为可能的语音模型。
- [**WhisperKit**](https://github.com/argmaxinc/WhisperKit) by Argmax —— Whisper 在 Apple Silicon 上的快速原生实现。
- [**KeyboardShortcuts**](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus —— 你每天按下的那套快捷键机制。
- [**voxt**](https://github.com/hehehai/voxt) —— 一个志同道合的项目,我们在技术层面学到了很多。
- [**Typeless**](https://www.typeless.com/) 和 [**Wispr Flow**](https://wisprflow.ai/) —— 闭源应用,但它们证明了语音优先的输入可以多么愉快;我们要做的是同样的体验,以本地、开源的方式。

还有所有提 issue、开 PR、把它推荐给朋友的人:谢谢你们。这只鸭子的每一声叫,都因为你们。

## 贡献

OpenQuack 是 **AI-native 的开源项目** —— 每个 PR 都引用一份 SPEC,原子任务来自路线图,工作流对编程 agent(以及走同一条路的人类)都很友好。

从 [`AGENTS.md`](AGENTS.md) 开始,在 [`docs/ROADMAP.md`](docs/ROADMAP.md) 里挑一个 🔵 任务,开一个 draft PR。

技术细节:[`TUTORIAL`](docs/TUTORIAL.md) · [`DEVELOPMENT`](docs/DEVELOPMENT.md) · [`ARCHITECTURE`](docs/ARCHITECTURE.md) · [`BENCHMARKS`](docs/BENCHMARKS.md) · [`DESIGN`](docs/DESIGN.md) · [`INSTALL`](docs/INSTALL.md) · [`BLOG`](docs/blog/README.md)。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。

(欢迎通过 PR 或 [GitHub Discussions](https://github.com/larryxiao/openquack/discussions) 反馈翻译问题。)
