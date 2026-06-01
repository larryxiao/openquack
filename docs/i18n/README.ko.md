<p align="center">
  <img src="../images/banner.png" alt="OpenQuack — 말하면. 입력된다. 비공개로. 녹음 오버레이에 'Listening' 과 실시간 음량 미터, 메뉴바 팝오버에 'Pasted at cursor' 와 최근 받아쓰기 결과, 푸터에 Settings / Quit 버튼이 표시된다.">
</p>

<div align="center">

**OpenQuack** *말하면. 입력된다. 비공개로.*

macOS 용 음성 받아쓰기. 무엇도 기기를 떠나지 않는다 —— 오디오도, 텍스트도, 아무것도.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](../INSTALL.md)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)](../ROADMAP.md)

</div>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../../README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <strong>한국어</strong> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a>
</p>

> 🌐 **기계 번역입니다.** 원어민의 기여를 환영합니다 —— PR 을 열어주시거나 [`CONTRIBUTING.md`](../../CONTRIBUTING.md) 를 참고하세요.

---

> 📢 **새 소식 — [v2.0.0-alpha.9](https://github.com/larryxiao/openquack/releases/tag/v2.0.0-alpha.9):** 긴 음성도 빠르게 받아쓰기. 그리고 새로워진 외관. 마음에 들었으면 좋겠어요!

## 이게 뭔가요

OpenQuack 은 macOS 메뉴바에 사는 작은 앱이에요. 단축키를 누르고 말한 뒤 다시 누르면 —— 받아쓰기 결과가 커서 위치에 나타납니다. 타이핑이 가능한 곳이라면, 어디서든 말할 수 있어요.

음성 인식은 Mac 안에서 처리돼요. 클라우드도, 계정도, 가입도, 텔레메트리도 없어요.

## 왜 만들었나

**로컬.** 모든 게 기기 위에서 돌아가요 —— 녹음, 받아쓰기, 선택적 다듬기까지. 아무것도 외부로 나가지 않아요: 오디오, 텍스트, 텔레메트리, 가입, 전부 없음. 기밀 작업은 설계 단계부터 기밀로 유지돼요. 그리고 흐름 안에 API 호출이 없으니 계속 작동해요 —— 오프라인에서도, 비행기 안에서도, 사내 방화벽 뒤에서도.

**빠릅니다.** Apple Silicon 위의 Whisper 는 말한 시간의 약 1/5 만에 받아쓰기를 끝내요. 베이스라인 M4 / 16 GB 에서 실제 사람 음성에 대한 단어 오류율은 약 ~2.6%. 대부분의 경우 타이핑보다 빠릅니다. 전체 벤치 매트릭스는 [`docs/BENCHMARKS.md`](../BENCHMARKS.md) 참고.

**오픈.** MIT 라이선스. 모든 줄이 감사 가능하고, 모든 변경은 공개로 일어납니다. 메뉴바에서 도는 버전이 곧 이 저장소의 버전이에요.

## 받게 되는 것

- **단축키 하나로 받아쓰기.** 단축키 선택 (기본값 ⌃⇧Space). 토글 또는 푸시 투 토크.
- **모두 로컬.** 음성 인식은 Mac 에서 돌아요. 받아쓰기에 인터넷이 필요 없어요 —— 오프라인, 비행기, 터널 안, 사내 방화벽 뒤에서도 작동. API 키 없음, 속도 제한 없음, 서비스 장애 없음. 개인이든 업무 환경이든 동일한 받아쓰기.
- **다국어.** Whisper 는 99 개 언어를 처리해요 —— 영어, 중국어, 일본어, 한국어, 스페인어, 프랑스어, 독일어, 이탈리아어, 포르투갈어가 설정에 바로 있고, 자동 감지가 기본 켜짐.
- **커서 위치에 자동 붙여넣기**, 어떤 앱에서든. (직접 붙여넣고 싶다면 클립보드로 폴백.)
- **스마트 포맷팅** —— 대문자화, 문장 끝 구두점, "음/어" 같은 군말 정리.
- **사용자 사전** —— 실제로 쓰는 고유명사와 프로젝트명을 가르쳐 둘 수 있어요.
- **무음 시 자동 정지.** 말이 끝나면 OpenQuack 이 알아서 마무리.
- **실시간 마이크 레벨 오버레이**, 듣고 있다는 게 눈에 보여요.
- **첫 실행 빠른 설정** —— 권한, 단축키, 1 분이면 끝.
- **작아요.** 8 MB 짜리 메뉴바 앱, 그리고 첫 실행 때 받는 음성 모델.
- **오픈소스**, MIT.

## 프라이버시, 한 화면에

1. **무엇도 기기를 떠나지 않아요 —— 오디오, 텍스트, 아무것도.** 녹음과 받아쓰기는 완전히 로컬. 언제나.
2. **분석 없음, 텔레메트리 없음, 가입 없음.**

전체 프라이버시 계약은 [`docs/VISION.md`](../VISION.md#privacy-contract) 에 있어요.

## 다음에 올 것

대기 중인 기능 미리보기. 둘 다 오늘 출시된 받아쓰기 토대 위에 올라갑니다.

**문맥 인식 받아쓰기.** OpenQuack 이 곧 붙여넣을 위치 주변의 텍스트를 읽어요 —— 커서 위 줄, 지금 들어와 있는 함수, 답장 중인 채팅 스레드 —— 그리고 그것을 음성 모델에 컨텍스트로 넘겨요. 도메인 용어가 실제로 하고 있는 일에 따라 자동으로 풀려요 (터미널에 있을 때 "cloud code" 가 "Claude Code" 로 잡히지, 그 반대가 아니라요). 사용자 사전을 만질 일이 줄어듭니다.

**씽킹 모드.** 받아쓰기 후 한 번 더, 작은 로컬 LLM 을 거쳐서, 말로 뱉은 원문을 실제로 보내기 버튼을 누를 수 있는 글로 바꿔줘요. 군말 잘라내고, 구조 다듬고, 중요한 단어에 알맞은 대문자. 기본은 꺼짐, 토글 한 번으로 켜짐. 완전 로컬 —— Ollama 또는 MLX-LM, 원하는 쪽으로.

일정과 SPEC 상세는 [`docs/ROADMAP.md`](../ROADMAP.md).

이 오리는 더 큰 계획이 있어요. 향하는 곳: [`docs/VISION.md`](../VISION.md).

## 설치

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

또는 [DMG 다운로드](https://github.com/larryxiao/openquack/releases) 후 Applications 에 드래그. 첫 실행: 우클릭 → **열기** → **열기** (Gatekeeper 일회성 우회).

macOS 가 물어보면 **마이크** 권한을 주고, **설정 → 단축키** 에서 단축키를 골라요 (기본값 ⌃⇧Space).

가이드 투어가 필요하다면? [`docs/TUTORIAL.md`](../TUTORIAL.md) 참고 —— 설치부터 첫 받아쓰기까지 5 분.

### 또는 AI 에이전트에게 시키기

이걸 Claude Code, Codex, opencode, Hermes 등에 붙여넣으세요:

```text
Install OpenQuack on this Mac:

  brew tap larryxiao/openquack https://github.com/larryxiao/openquack
  brew install --cask openquack

(Or grab the DMG from https://github.com/larryxiao/openquack/releases
and drag it into /Applications; first open right-click → Open → Open.)

Then launch /Applications/OpenQuack.app, grant Microphone, and pick a
hotkey in Settings → Shortcut. Default ⌃⇧Space.
```

추가 옵션 (제거, 소스 빌드, 첫 실행 시 받는 것): [`docs/INSTALL.md`](../INSTALL.md).

## 감사의 말

OpenQuack 은 너그러운 오픈소스 작업의 어깨 위에 서 있습니다. 큰 감사를 전합니다:

- [**OpenAI Whisper**](https://github.com/openai/whisper) —— 이 모든 것을 가능하게 한 음성 모델.
- [**WhisperKit**](https://github.com/argmaxinc/WhisperKit) by Argmax —— Apple Silicon 위에서 빠르고 네이티브로 도는 Whisper.
- [**KeyboardShortcuts**](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus —— 매일 누르는 단축키 메커니즘.
- [**voxt**](https://github.com/hehehai/voxt) —— 같은 결의 프로젝트, 기술적인 면에서 많이 배웠어요.
- [**Typeless**](https://www.typeless.com/) 와 [**Wispr Flow**](https://wisprflow.ai/) —— 클로즈드 소스이지만, 음성 우선 입력이 얼마나 기분 좋은지 증명해준 앱들; 같은 감각을 로컬에서, 오픈으로 목표하고 있어요.

그리고 이슈를 올려주신 분들, PR 을 보내주신 분들, 친구에게 알려주신 모든 분들에게: 감사합니다. 이 오리가 꽥거리는 건 여러분 덕분이에요.

## 기여

OpenQuack 은 **AI 네이티브 오픈소스** —— 모든 PR 이 SPEC 을 인용하고, 원자적 작업은 로드맵에서 옵니다. 워크플로는 코딩 에이전트에게도 (같은 길을 가는 사람에게도) 친화적이에요.

[`AGENTS.md`](../../AGENTS.md) 에서 시작해서, [`docs/ROADMAP.md`](../ROADMAP.md) 에서 🔵 작업을 골라, 드래프트 PR 을 열어주세요.

내부:[`TUTORIAL`](../TUTORIAL.md) · [`DEVELOPMENT`](../DEVELOPMENT.md) · [`ARCHITECTURE`](../ARCHITECTURE.md) · [`BENCHMARKS`](../BENCHMARKS.md) · [`DESIGN`](../DESIGN.md) · [`INSTALL`](../INSTALL.md) · [`BLOG`](../blog/README.md).

## 라이선스

MIT —— [LICENSE](../../LICENSE) 참고.

(번역 피드백은 PR 또는 [GitHub Discussions](https://github.com/larryxiao/openquack/discussions) 로 환영합니다.)
