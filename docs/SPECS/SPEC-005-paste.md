# SPEC-005 — Paste at cursor

**Status:** ratified — shipped 2026-04-27 (`Sources/OpenQuackKit/Output/PasteService.swift`)
**Owner:** `OpenQuackKit/Output/`
**Last updated:** 2026-04-26

## Goal

After the active agent returns `.text(String)`, deposit the text at the cursor position in whatever app is currently focused — the same UX as a system paste.

## Non-goals

- Direct text-injection via Accessibility (`AXUIElementSetAttributeValue`). We use the simpler "pasteboard + simulated `⌘V`" idiom, which works in 99 % of apps without Accessibility-tree manipulation.
- Rich text (bold / italics / formatting). Plain text only.

## Public surface

```swift
public enum PasteService {
    /// Set the text on the general pasteboard, then post a synthetic ⌘V event.
    /// Restores the previous pasteboard contents after a short delay.
    public static func paste(_ text: String) async throws

    /// Just put text on the pasteboard — for the "clipboard-only" Settings option.
    public static func copyToClipboard(_ text: String)
}
```

## Behaviour

`paste(_:)`:

1. Snapshot the current `NSPasteboard.general` contents (string variant; we accept that we can't perfectly preserve rich types).
2. Write `text` to the pasteboard.
3. Post a `kCGEventKeyDown` for `V` with `.maskCommand`, then the matching `kCGEventKeyUp`.
4. After ~600 ms, restore the snapshot.

The 600 ms delay covers normal apps; some sluggish ones may miss the restore. Document this and provide a "clipboard-only" mode as an escape hatch.

## Permissions

- Posting `CGEvent`s requires Accessibility permission (`com.apple.security.accessibility`).
- On first `paste(_:)`, prompt via `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`.
- If denied, fall back to clipboard-only mode and surface a banner explaining how to grant.

## Open questions

- Do we restore the pasteboard at all, or leave the user's last copy as our utterance? Other dictation tools split here. Lean restore-by-default with a Settings opt-out.
- For very long transcripts (> 1 MB), should we chunk the paste? Probably never relevant for voice input; defer.

## References

- `CGEvent.post(tap:)` docs.
- Existing voxt implementation for prior art.
