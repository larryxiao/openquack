#!/usr/bin/env bash
# Live debug log console for OpenQuack. Pass a topic; this streams that
# topic's `.debug` os_log from the running app in real time, parsed from
# ndjson and reformatted into readable blocks. Debug-level logs are inert
# (not captured / not persisted) until streamed, so this costs nothing in
# normal use and ships nothing extra in the app.
#
# Each app log line is a JSON object (the message body), so the stream is
# newline-delimited JSON — parsed robustly here instead of by string slicing.
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

# Formatter: each ndjson line wraps our message in `eventMessage` (itself
# JSON). Double-parse, then print a readable block. Single-quoted heredoc so
# the Python can use both quote styles freely.
read -r -d '' FORMAT <<'PY' || true
import sys, json
while True:
    line = sys.stdin.readline()
    if not line:
        break
    line = line.strip()
    if not line.startswith("{"):
        continue                      # skip the "Filtering…" header etc.
    try:
        entry = json.loads(line)
        d = json.loads(entry.get("eventMessage", "") or "{}")
    except Exception:
        continue
    if "raw" not in d:
        continue
    ts = entry.get("timestamp", "")
    t = ts[11:19] if len(ts) >= 19 else ts
    llm = "ok" if d.get("llm") else "FELL BACK"
    ms = d.get("ms")
    ms_s = "%dms" % ms if ms is not None else "-"
    print("\n[%s] %s · LLM %s · %s" % (t, d.get("engine", "?"), llm, ms_s))
    print("  raw      : %s" % d.get("raw", ""))
    print("  polished : %s" % d.get("polished", ""))
    sys.stdout.flush()
PY

# `script -q /dev/null …` gives `log stream` a pty so it stays line-buffered
# through the pipe (otherwise output blocks and isn't live).
script -q /dev/null log stream \
    --level debug \
    --style ndjson \
    --predicate "subsystem == \"$SUBSYSTEM\" AND category == \"$category\"" \
| python3 -u -c "$FORMAT"
