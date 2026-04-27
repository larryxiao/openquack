#!/usr/bin/env bash
# Fetch a small subset of LibriSpeech dev-clean (real human read speech, English).
# License: CC BY 4.0 (https://www.openslr.org/12).
#
# Downloads the full dev-clean tarball (~337 MB) once, extracts N utterances
# spanning multiple speakers, converts FLAC → 16 kHz mono WAV, writes references.
# After extraction, the tarball is removed (audio is gitignored anyway).
#
# Override the count: `N=50 bash fetch_librispeech.sh`
set -euo pipefail

CORPUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LS_DIR="$CORPUS_DIR/librispeech"
TMP="$CORPUS_DIR/.libri-tmp"
TAR_URL="https://www.openslr.org/resources/12/dev-clean.tar.gz"
N="${N:-30}"

mkdir -p "$LS_DIR" "$TMP"

if ! command -v afconvert >/dev/null 2>&1; then
    echo "error: \`afconvert\` not found (ships with macOS)" >&2; exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "error: \`curl\` not found" >&2; exit 1
fi

echo "→ Downloading dev-clean.tar.gz (~337 MB)..."
curl -L --progress-bar -o "$TMP/dev-clean.tar.gz" "$TAR_URL"

echo "→ Extracting..."
tar -xzf "$TMP/dev-clean.tar.gz" -C "$TMP"

# Pick N utterances spanning multiple speakers. We sample 5 per speaker to get
# voice variety, capping at N total.
echo "→ Selecting $N utterances and converting to 16 kHz mono WAV..."
count=0
# Walk speakers in stable (sorted) order so re-runs pick the same set.
for speaker_dir in "$TMP/LibriSpeech/dev-clean"/*/; do
    [[ -d "$speaker_dir" ]] || continue
    per_speaker=0
    for chapter_dir in "$speaker_dir"*/; do
        [[ -d "$chapter_dir" ]] || continue
        # The .trans.txt file in each chapter dir lists utterance_id → transcript.
        trans_file=$(ls "$chapter_dir"*.trans.txt 2>/dev/null | head -1)
        [[ -f "$trans_file" ]] || continue
        # Sort by utterance ID, take 5 per speaker max (across chapters).
        while IFS= read -r line; do
            (( per_speaker >= 5 )) && break
            (( count >= N )) && break 3
            utt_id="${line%% *}"
            text="${line#* }"
            flac="$chapter_dir$utt_id.flac"
            [[ -f "$flac" ]] || continue
            wav="$LS_DIR/$utt_id.wav"
            txt="$LS_DIR/$utt_id.txt"
            afconvert -f WAVE -d LEI16@16000 -c 1 "$flac" "$wav" >/dev/null
            printf '%s\n' "$text" > "$txt"
            (( count++ ))
            (( per_speaker++ ))
            printf '  ✓ [%2d/%d] %s\n' "$count" "$N" "$utt_id"
        done < "$trans_file"
    done
done

echo "→ Cleaning up..."
rm -rf "$TMP"

total=$(ls "$LS_DIR"/*.wav 2>/dev/null | wc -l | tr -d ' ')
echo
echo "✓ $total LibriSpeech clips ready in bench/corpus/librispeech/"
echo "  License: CC BY 4.0 — http://www.openslr.org/12"
