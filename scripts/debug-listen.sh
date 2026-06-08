#!/usr/bin/env bash
# Live debug log console for OpenQuack. Pass a topic; this streams that
# topic's `.debug` os_log from the running app in real time, parses the
# ndjson, and reformats it into readable blocks. Debug-level logs are inert
# (not captured / not persisted) until streamed, so this costs nothing in
# normal use and ships nothing extra in the app.
#
# Each app log line is a JSON object (the message body), so the stream is
# newline-delimited JSON — parsed robustly here instead of by string slicing.
# Plain `log stream | python3` pipe: live, and Ctrl-C just works (no pty, so
# the terminal is never touched).
#
# Topics:
#   polish   raw → polished per dictation (engine, success, latency)
#
# Usage: bash scripts/debug-listen.sh polish     # then dictate in the app
#        (Ctrl-C to stop)
set -uo pipefail

SUBSYSTEM="org.openquack.OpenQuack"

usage() {
    echo "usage: $(basename "$0") <topic>" >&2
    echo "topics: polish" >&2
    exit 2
}

topic="${1:-}"
case "$topic" in
    polish) category="polish" ;;
    "")     usage ;;
    *)      echo "unknown topic: $topic" >&2; usage ;;
esac

echo "● debug-listen ON — topic: $topic. Dictate in the app to see output; Ctrl-C to stop." >&2

# Formatter: each ndjson line wraps our message in `eventMessage` (itself
# JSON). Double-parse, then print a readable block. Single-quoted heredoc so
# the Python can use both quote styles freely.
read -r -d '' FORMAT <<'PY' || true
import sys, json
TTY = sys.stdout.isatty()  # skip color when piped to a file
def c(code, s):
    return "\033[%sm%s\033[0m" % (code, s) if TTY else s
try:
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line.startswith("{"):
            continue                  # skip the "Filtering…" header etc.
        try:
            entry = json.loads(line)
            d = json.loads(entry.get("eventMessage", "") or "{}")
        except Exception:
            continue
        if "raw" not in d:
            continue
        ts = entry.get("timestamp", "")
        t = ts[11:19] if len(ts) >= 19 else ts
        llm = c("32", "ok") if d.get("llm") else c("31", "FELL BACK")
        ms = d.get("ms")
        ms_s = "%dms" % ms if ms is not None else "-"
        sys.stdout.write("\n[%s] %s · LLM %s · %s\n" % (t, d.get("engine", "?"), llm, ms_s))
        sys.stdout.write("  raw      : %s\n" % c("33", d.get("raw", "")))
        sys.stdout.write("  polished : %s\n" % c("32", d.get("polished", "")))
        sys.stdout.flush()
except KeyboardInterrupt:
    pass
PY

log stream \
    --level debug \
    --style ndjson \
    --predicate "subsystem == \"$SUBSYSTEM\" AND category == \"$category\"" \
| python3 -u -c "$FORMAT"
