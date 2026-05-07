# Using OpenQuack with Cursor

Cursor's Composer and chat panes take prompts well — and the longer
and more contextual the prompt, the better the result. Voice is the
fastest way to produce that kind of prompt.

This guide is for people who already use Cursor. If you're new,
download from [cursor.sh](https://cursor.sh).

## The pairing in one sentence

Click into Composer (`⌘I`) or the chat pane, press the OpenQuack
hotkey, describe what you want Cursor to do as you'd describe it
to a teammate, release — the transcript pastes into Cursor's input.

## Why it works well

The prompts that produce the best Cursor output are the ones that
spell out **what to change, why, and the constraints**. That shape
is verbose by nature. "Refactor `parseConfig` to handle the new
schema, keep the old format readable as a fallback, throw on
ambiguity rather than guessing — see how `parseLegacy` handles the
same case for reference" is a paragraph. Speaking it takes ~12
seconds; typing it takes 40+.

OpenQuack's streaming transcription means the post-stop wait stays
~constant in clip length. A 30-second prompt pastes ~3 seconds
after you stop speaking, regardless of length (see
[`docs/BENCHMARKS.md`](../BENCHMARKS.md)). Most dictation tools'
post-stop wait scales with prompt length, which interrupts the
think-then-send flow.

## Setup (5 minutes)

1. Install OpenQuack ([`docs/INSTALL.md`](../INSTALL.md)).
2. Grant Microphone + Accessibility when macOS asks. Accessibility
   is what lets the transcript paste at the cursor inside Cursor;
   without it the transcript only lands on the clipboard.
3. Pick a hotkey in **Settings → Shortcut**. Cursor uses ⌘K, ⌘L,
   and ⌘I heavily; ⌃⇧Space (default), F5, or ⌥⇧V are safe choices.
4. Click into Composer or the chat input, press hotkey, speak,
   press again to stop. Press Enter to send.

## Workflow patterns

**Composer, with Cmd+I:** open Composer, dictate the change spec
naturally — file scope, target behaviour, constraints, references
to existing patterns. Hit Enter. Cursor reads, applies. Review the
diff visually.

**Chat pane for clarification:** when Cursor proposes something
that's *almost* right, voice the correction. Voice is faster than
typing for the kind of micro-feedback that comes naturally in the
moment ("yes but use `Result<T,E>` not `throws` — match the rest of
the file").

**Cmd+K for inline edits:** speak the change at the line level. Hit
return. Cursor inserts the edit at the cursor.

**Long-form refactor briefs:** for changes spanning multiple files,
the brief is often a paragraph. Voice it once into Composer rather
than typing it into chat. The streaming-tail latency win is the
biggest here.

## Pitfalls

- **Don't dictate code.** Whisper transcribes prose, not syntax.
  Type literal code; voice the surrounding intent.
- **Proper nouns and project names.** Add them in **Settings →
  General → Custom dictionary** (one per line). "Whisper Kit"
  becomes one word, "Cursor's Composer" stays as written.
- **Cursor's UI takes focus.** If your hotkey doesn't fire, click
  into the Cursor input first to make sure focus is there, then
  press the OpenQuack hotkey.
- **First transcription is slow.** Whisper cold-starts on Apple
  Silicon (~10-30 s for `medium` on M-series). Open OpenQuack
  before Cursor so the model is warm when you press the hotkey.

## Why not just type

For short questions ("what does this function do?"), typing is
fine. For *long, contextual prompts*, voice is faster end-to-end:
a 50-word brief takes ~15 seconds to speak and ~3 seconds to paste,
vs ~40+ seconds to type at sustained 90 WPM.

If you find Cursor most useful for short edits, OpenQuack adds
little. If you produce paragraph-length specs, the latency win is
the difference between flow and stop-and-go.

## Privacy

Cursor's prompts route through Cursor's services per their privacy
settings. OpenQuack doesn't change that — it just gets your voice
into the prompt field. Audio and the transcript stay on your Mac
(transcribed locally via WhisperKit); OpenQuack adds no network
hop. The privacy gradient is yours to set per Cursor's settings.
