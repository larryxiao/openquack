#!/usr/bin/env bash
# Generate the long-form bench corpus for SPEC-012 (streaming).
#
# Three public-domain sources (Austen / Dickens / Doyle) sliced into nested
# word-count prefixes targeting the SPEC-012 length buckets:
#
#   030s ≈  87 words   (Whisper offline single-window — streaming should bypass)
#   060s ≈ 175 words   (~ 6 s post-stop today, ≤ 1.5 s under streaming)
#   120s ≈ 350 words   (~13 s today, ≤ 2.0 s under streaming)
#   300s ≈ 875 words   (~26 s today, ≤ 2.5 s under streaming)
#
# 3 sources × 4 lengths = 12 WAV clips. Three samples per length is the
# variance floor; using three sources (different prose styles ⇒ different
# silence patterns) gives that without reusing the same passage thrice.
#
# Rate fixed at -r 175 (matches `say -v Samantha`'s natural cadence and
# keeps actual durations within ~10% of nominal). The bench harness keys on
# *measured* duration, not the bucket label, so small rate drift is fine.
set -euo pipefail

CORPUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$CORPUS_DIR/sources"

if ! command -v say >/dev/null 2>&1; then
    echo "error: \`say\` not found (macOS only)" >&2; exit 1
fi
if ! command -v afconvert >/dev/null 2>&1; then
    echo "error: \`afconvert\` not found (ships with macOS)" >&2; exit 1
fi
if ! command -v afinfo >/dev/null 2>&1; then
    echo "error: \`afinfo\` not found (ships with macOS)" >&2; exit 1
fi

# Take first N words from a source file, single-line, normalised whitespace.
take_words() {
    local n="$1" file="$2"
    tr '\n' ' ' < "$file" | tr -s ' ' | awk -v n="$n" '{
        for (i = 1; i <= n && i <= NF; i++) printf "%s%s", $i, (i==n||i==NF?"":" ")
    }'
}

# Render text → 16 kHz mono WAV at a fixed rate; emit reference .txt and
# print the measured duration.
generate() {
    local outdir="$1" id="$2" voice="$3" rate="$4" text="$5"
    local aiff="$outdir/${id}.aiff"
    local wav="$outdir/${id}.wav"
    local txt="$outdir/${id}.txt"

    mkdir -p "$outdir"
    say -v "$voice" -r "$rate" -o "$aiff" -- "$text"
    afconvert -f WAVE -d LEI16@16000 -c 1 "$aiff" "$wav" >/dev/null
    rm -f "$aiff"
    printf '%s\n' "$text" > "$txt"

    local dur
    dur=$(afinfo "$wav" 2>/dev/null \
            | awk '/estimated duration/ { gsub(/[^0-9.]/, "", $3); print $3 }')
    printf '  ✓ %-22s %6.1f s  (%s words)\n' "$id" "$dur" "$(printf '%s' "$text" | wc -w | tr -d ' ')"
}

# Word-count buckets keyed by nominal-second label.
LABELS=(030s 060s 120s 300s)
WORDS=(87    175  350  875)

echo "→ long/ (3 sources × 4 lengths = 12 clips, voice Samantha @ 175 wpm)"
for src in austen dickens doyle; do
    src_path="$SOURCES_DIR/${src}.txt"
    if [ ! -f "$src_path" ]; then
        echo "error: source missing: $src_path" >&2; exit 1
    fi
    avail=$(wc -w < "$src_path" | tr -d ' ')
    for i in "${!LABELS[@]}"; do
        n="${WORDS[$i]}"
        if [ "$avail" -lt "$n" ]; then
            echo "error: $src has $avail words, need $n for ${LABELS[$i]}" >&2; exit 1
        fi
        text=$(take_words "$n" "$src_path")
        generate "$CORPUS_DIR" "${src}_${LABELS[$i]}" Samantha 175 "$text"
    done
done

echo
total=$(find "$CORPUS_DIR" -maxdepth 1 -name '*.wav' | wc -l | tr -d ' ')
echo "✓ Long-form corpus ready: $total WAV clips in $CORPUS_DIR/"
