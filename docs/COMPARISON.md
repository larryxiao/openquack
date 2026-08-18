# How OpenQuack compares to other Mac voice tools

A factual comparison meant to help you decide. We don't claim
OpenQuack is "better" — only that the design goals are different and
we want to make those visible. If a row in this doc gets out of date,
[file an issue](https://github.com/larryxiao/openquack/issues/new?template=bug_report.yml)
or open a PR; we'll update.

The single sentence that captures the design difference: **OpenQuack
optimises for fast, faithful raw capture**, especially long-form. If
you're capturing 5-minute thoughts, we're built for that. If you want
the polished output by default and don't mind the wait, the other
tools below are well-built for that.

## At a glance

|  | OpenQuack | Wispr Flow | Superwhisper | MacWhisper | Typeless | Built-in macOS |
|---|---|---|---|---|---|---|
| **License** | MIT (open source) | proprietary | proprietary | proprietary | proprietary | proprietary |
| **Price** | free | subscription | $65/yr or $165 lifetime[^1] | free + Pro tier | subscription | included with macOS |
| **Source available** | yes (full) | no | no | no | no | no |
| **Where transcription runs** | on-device | cloud | on-device | on-device | cloud | on-device |
| **Account / signup needed** | no | yes | no | no | yes | no |
| **OS requirements** | macOS 13+ | macOS + Windows | macOS | macOS | macOS | macOS (built in) |
| **Languages supported** | 99 (via Whisper) | many | many | many (via Whisper) | many | ~30 |
| **Real-time vs file-based** | real-time | real-time | real-time | file-first[^2] | real-time | real-time |
| **Auto-paste at cursor** | yes | yes | yes | optional | yes | yes |
| **LLM-polish step** | optional opt-in | on by default | optional | optional | on by default | n/a |
| **Long-form post-stop wait** | ~constant in clip length[^3] | adds polish latency | varies | n/a (file mode) | adds polish latency | varies |
| **Telemetry / analytics** | none | yes | none disclosed | none disclosed | yes | system-level |
| **Custom hotkey** | yes | yes | yes | yes | yes | yes |

[^1]: Per `gtm/user-pains.md` reference data; verify on the vendor's
      pricing page before quoting in customer-facing material.
[^2]: MacWhisper's primary mode is "drop a file, get a transcript."
      They've added more real-time features over time; check their
      current docs.
[^3]: OpenQuack uses streaming chunked transcription (SPEC-012):
      a 5-minute clip finishes ~2.8s after stop on M4-16GB,
      vs ~34s offline (`bench/out/stream/M4-16GB-paced/report.md`).
      The wait is the trailing chunk, which is essentially constant
      in clip length above ~30s.

## When each tool is the right pick

This is the part where most comparison docs become marketing. We're
trying not to. Each of these tools is well-built for what it
optimises for; pick the one whose tradeoffs match yours.

### OpenQuack — pick if

- You dictate long-form (60+ seconds): journal entries, fleeting
  notes, lecture / meeting fieldnotes, brain-dumping a thought. The
  streaming-chunk architecture means the wait after stop is
  ~constant rather than scaling with clip length.
- Privacy is non-negotiable. Audio never leaves the device unless
  you opt in to a remote endpoint. No account, no telemetry,
  MIT-licensed so you can verify.
- You want polish as a separate concern, not bundled in. The default
  pipeline is raw transcript → regex cleanup → paste. Optional LLM
  polish via Ollama / MLX-LM is opt-in.
- You're comfortable with alpha-quality software and want to
  contribute back (bench rows from your Mac, translations, bug
  reports).

### Wispr Flow — pick if

- You want polished output by default with minimal configuration.
- Cross-platform (Mac + Windows) matters more than offline.
- You're OK with a cloud round-trip and a paid subscription.
- You're dictating mostly short utterances where the polish-step
  latency doesn't break flow.

### Superwhisper — pick if

- You want a polished, paid Mac-native app with a single up-front
  cost rather than a subscription.
- Local processing matters but MIT-licensed source doesn't.
- You want a curated mode-switching system (work / chat / coding
  modes) out of the box.

### MacWhisper — pick if

- Your workflow is "I have a recording file, I want a transcript."
  MacWhisper has been file-first the longest and has the most polish
  for that.
- You want flexibility in choosing Whisper model size on your Mac.

### Typeless — pick if

- You want polished output by default with strong post-processing
  for filler-removal and prose tightening.
- Subscription pricing fits your budget.
- You're dictating short prose where polish latency is invisible.

### Built-in macOS Dictation — pick if

- You don't want to install anything.
- You're dictating short text (under ~60 seconds).
- You don't mind macOS's older command-driven model — newer macOS
  (26+) ships SpeechAnalyzer / "Smart Dictation" which is more
  capable; check Apple's current docs.

## Things this comparison can't tell you

- **How a tool feels in your specific workflow.** Try the free
  options. The dictation-tool fit is highly personal — the gap
  between "this just works" and "this annoys me daily" is small in
  features and big in feel.
- **Which Whisper model size hits your accuracy floor.** Different
  voices, different languages, different accents perform very
  differently on the same model. We publish a bench matrix
  ([`docs/BENCHMARKS.md`](BENCHMARKS.md)); other tools generally do
  not.
- **How a tool handles your specific edge cases.** Citrix
  windows, terminal apps, code-only contexts, multilingual
  code-switching — every tool has gaps. The fastest way to find
  yours is a 30-minute trial in your real apps.
- **Long-term reliability for paid tools.** Subscription apps can
  pivot, change pricing, or shut down; on-device tools can rot if
  unmaintained. Pick based on your tolerance for either failure
  mode.

## We'd value corrections

If a fact above is wrong — pricing changed, a feature was added or
removed, a row needs a citation — open a PR. We'd rather fix this
than be wrong. None of the rows above are about us beating someone;
they're about a visitor having an honest source to decide from.

## Source notes for OpenQuack's claims

- Long-form post-stop wait: `bench/out/stream/M4-16GB-paced/report.md`,
  measured per SPEC-012 streaming transcription
- WER: `docs/BENCHMARKS.md`, M4 / 16 GB host, multi-corpus matrix
- Languages: 99 via the Whisper model family; the Settings picker
  surfaces 9 directly with auto-detect on by default
- Privacy contract: `docs/VISION.md#privacy-contract`
- Source: every line is in this repo; CI runs on every push;
  releases are tagged
