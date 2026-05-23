# Using OpenQuack with Claude Code

Claude Code (the CLI) takes long, intent-rich prompts well. Typing
those prompts is the bottleneck. Speaking them through OpenQuack
removes it.

This guide is for people who already use Claude Code. If you're new
to it, install via `npm install -g @anthropic-ai/claude-code` and run
`claude` in any directory; the documentation lives at
[claude.com/claude-code](https://claude.com/claude-code).

## The pairing in one sentence

Press the OpenQuack hotkey, describe what you want Claude Code to do
(as long as you'd think it), release — the transcript appears at
your cursor in the Claude Code prompt. Press Enter.

## Why it works well

Claude Code prompts have an unusual shape: they reward **detail and
context**. "Fix the bug" is worse than "There's a race in the
streaming-pump frame ordering — Task spawning per buffer doesn't
guarantee FIFO at the actor; the AsyncStream pump fixes it. Apply
that pattern in `Sources/OpenQuackApp/OpenQuackApp.swift` line ~498."
The longer prompt is faster to *speak* than to *type*. Voice
collapses the typing tax on detail.

OpenQuack is built for this specific shape — long-form dictation
where the wait time after stop stays constant in clip length. A
30-second prompt finishes pasting ~3 seconds after you stop talking
(see [`docs/BENCHMARKS.md`](../BENCHMARKS.md)). On most other
dictation tools, the post-stop wait scales with your prompt length.

## Setup (5 minutes)

1. Install OpenQuack ([`docs/INSTALL.md`](../INSTALL.md)).
2. Grant Microphone + Accessibility when macOS asks. Accessibility
   is what lets the transcript paste at your cursor in the terminal;
   without it the transcript only goes to the clipboard.
3. Pick a hotkey in **Settings → Shortcut** that you'd want to press
   while your hands are on the keyboard. The default ⌃⇧Space works
   well in most terminals; alternatives that don't conflict with
   common terminal bindings: F5, F12, ⌥⇧V.
4. In Claude Code, position your cursor in the prompt area, press
   the hotkey, speak your intent, press the hotkey again to stop.
   Press Enter to send.

## Workflow patterns that pair well

**Steering the agent.** Describe the higher-level direction and
constraints, then let Claude Code handle the implementation. Voice
is faster than typing for this because most of what you'd say is
intent, not code. Example: *"Read the polish engine spec, scope down
PR #2 to just the protocol surface, file it as a draft PR."*

**Reviewing diffs aloud.** Read what Claude Code wrote back to it as
you scan. *"That's right — but rename `currentPolishEngine` to
`makePolishEngine` since it constructs rather than fetches. Apply."*
Voice keeps your hands free to scroll.

**Running approval prompts.** Claude Code asks for approval before
running commands. Voice the approval if your hands are away from
the keyboard. *"Yes, run it."*

**Dictating commit messages.** OpenQuack pastes anywhere a cursor
sits, including the `git commit -e` editor. Speak the commit body
naturally; the multi-paragraph cadence translates well.

## Pitfalls

- **Don't dictate code blocks.** Whisper transcribes prose, not
  syntax. If you need to drop in a code snippet, copy-paste — voice
  is for the surrounding intent.
- **Proper nouns and jargon.** Add project names, file paths, and
  technical terms to **Settings → General → Custom dictionary**
  (one per line). Whisper biases toward those words during
  decoding. Without it: "Whisper Kit" might come out two words;
  "Claude Code" might come out "cloud code."
- **First transcription is slow.** Whisper has a cold start on
  Apple Silicon (~10-30 s for `medium` on M-series). Open OpenQuack
  before Claude Code so the model is warm when you press the
  hotkey.

## Why not just type

You can. The point isn't that voice is universally better — it's
that for *long, detailed prompts*, voice is faster end-to-end. A
40-word prompt takes ~10 seconds to speak and ~3 seconds to paste.
Same prompt takes 30+ seconds to type at 90 WPM (and that's a
typing speed most people don't sustain).

If you mostly send 5-word prompts, OpenQuack doesn't help. If your
prompts to Claude Code are paragraphs of context, it's the right
shape.

## Quick voice-to-action (kickoff mode)

Sometimes you don't want to dictate *into* a prompt field — you want
to **start a Claude Code session** with what you just said. Set a
timer. List a folder. Sketch a one-file prototype. Whatever Claude
Code can do from a fresh shell.

Bind a second hotkey in **Settings → Shortcut → Agent kickoff** (e.g.
⌃⇧K). When you press it:

- OpenQuack records and transcribes as normal
- Instead of pasting at your cursor, it opens a new Terminal window
  in `~/OpenQuackAgent/` with `claude` already running on your
  transcript as the seed prompt
- You see the session work in that window — approvals, output, side
  effects — and can continue typing or speaking into it

Your normal dictation hotkey is unaffected and keeps pasting locally.
The kickoff hotkey is opt-in: the first time you bind it, OpenQuack
asks for consent because the transcript now leaves your machine via
Claude Code's API call. Revoke any time by clearing the binding in
Settings.

Useful when:

- *You're not in Claude Code.* Browsing, in Mail, in a meeting — you
  want a small task done without switching contexts.
- *The agent is the actuator, not the editor.* "Move my downloaded
  conference talks into ~/Movies/talks/", "Open a PR template for
  the bench update I keep forgetting", "Tell me what's listening on
  port 5432."
- *You want a scratch workspace.* `~/OpenQuackAgent/` is isolated —
  Claude can scaffold prototypes there without touching your real
  repos.

## Privacy

Claude Code itself routes your prompts through Anthropic's API
under your auth. OpenQuack doesn't change that — it just gets the
prompt from your voice into the prompt field. Audio and the
transcript stay on your Mac (transcribed locally via WhisperKit);
nothing OpenQuack does adds a network hop **in dictation mode**.

The agent-kickoff hotkey (above) is the one exception: in that mode,
the transcript is handed to `claude`, which routes through Anthropic
under your existing credentials. The kickoff hotkey ships unbound
and is opt-in with a consent prompt that names this destination
explicitly. Dictation-mode is untouched by that consent.

The privacy gradient is yours to set per Claude Code's settings.
