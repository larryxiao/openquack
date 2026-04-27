#!/usr/bin/env bash
# Generate the synthetic part of the bench corpus using macOS `say`.
#
# Buckets created:
#   short/           5 single-voice English clips (Samantha) — quick smoke test
#   voices/          5 sentences × 4 English voices (US/UK/AU accents) = 20 clips
#   multilingual/    Short sentences in zh, ja, ko, es, fr, de (native voices)
#
# Real human speech (LibriSpeech) → see fetch_librispeech.sh.
# Noise-augmented clips             → run mix_noise.py after this.
set -euo pipefail

CORPUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v say >/dev/null 2>&1; then
    echo "error: \`say\` not found (macOS only)" >&2; exit 1
fi
if ! command -v afconvert >/dev/null 2>&1; then
    echo "error: \`afconvert\` not found (ships with macOS)" >&2; exit 1
fi

# Render text -> 16 kHz mono WAV with a given voice, save reference text.
generate() {
    local outdir="$1" id="$2" voice="$3" text="$4"
    local aiff="$outdir/${id}.aiff"
    local wav="$outdir/${id}.wav"
    local txt="$outdir/${id}.txt"

    mkdir -p "$outdir"
    say -v "$voice" -o "$aiff" -- "$text"
    afconvert -f WAVE -d LEI16@16000 -c 1 "$aiff" "$wav" >/dev/null
    rm -f "$aiff"
    printf '%s\n' "$text" > "$txt"
    printf '  ✓ %s\n' "$id"
}

# ── short/ — single-voice, kept for quick smoke tests ─────────────────────
echo "→ short/ (Samantha × 5)"
SHORT="$CORPUS_DIR/short"
generate "$SHORT" tts_001 Samantha "The quick brown fox jumps over the lazy dog."
generate "$SHORT" tts_002 Samantha "Hello world, this is a test of the OpenQuack benchmark."
generate "$SHORT" tts_003 Samantha "Privacy first voice to text on Apple Silicon."
generate "$SHORT" tts_004 Samantha "She sells seashells by the seashore on a sunny afternoon."
generate "$SHORT" tts_005 Samantha "Two roads diverged in a yellow wood and I took the one less travelled by."

# ── voices/ — 4 English voices × 5 sentences = 20 clips ───────────────────
echo
echo "→ voices/ (4 English accents × 5 sentences)"
VOICES_DIR="$CORPUS_DIR/voices"
ENG_TEXTS=(
    "The quick brown fox jumps over the lazy dog."
    "Hello world, this is a test of the OpenQuack benchmark."
    "Privacy first voice to text on Apple Silicon."
    "She sells seashells by the seashore on a sunny afternoon."
    "Two roads diverged in a yellow wood and I took the one less travelled by."
)
for voice in Samantha Daniel Karen Fred; do
    voice_lower="$(echo "$voice" | tr '[:upper:]' '[:lower:]')"
    for i in "${!ENG_TEXTS[@]}"; do
        idx=$(printf "%03d" "$((i+1))")
        generate "$VOICES_DIR" "${voice_lower}_${idx}" "$voice" "${ENG_TEXTS[$i]}"
    done
done

# ── multilingual/ — native sentences per language ─────────────────────────
echo
echo "→ multilingual/ (zh, ja, ko, es, fr, de)"
ML_DIR="$CORPUS_DIR/multilingual"

generate "$ML_DIR" zh_001 Tingting "春天来了，花儿都开了。"
generate "$ML_DIR" zh_002 Tingting "今天的天气真好，我们出去散步吧。"

generate "$ML_DIR" ja_001 Kyoko    "今日はとても良い天気です。"
generate "$ML_DIR" ja_002 Kyoko    "猫はいつも窓辺で日向ぼっこをしています。"

generate "$ML_DIR" ko_001 Yuna     "안녕하세요 만나서 반갑습니다."
generate "$ML_DIR" ko_002 Yuna     "오늘 날씨가 정말 좋네요."

generate "$ML_DIR" es_001 Paulina  "Hoy es un día hermoso para pasear por el parque."
generate "$ML_DIR" es_002 Paulina  "Me gustaría tomar un café con leche, por favor."

generate "$ML_DIR" fr_001 Thomas   "Le chat est sur le tapis devant la fenêtre."
generate "$ML_DIR" fr_002 Thomas   "Je voudrais un café et un croissant, s'il vous plaît."

generate "$ML_DIR" de_001 Anna     "Heute ist das Wetter wirklich schön."
generate "$ML_DIR" de_002 Anna     "Ich möchte einen Kaffee und ein Stück Kuchen, bitte."

echo
total=$(find "$CORPUS_DIR" -name '*.wav' | wc -l | tr -d ' ')
echo "✓ Synthetic corpus ready: $total WAV clips."
echo
echo "Next steps:"
echo "  • Real human speech:    bash bench/corpus/fetch_librispeech.sh"
echo "  • Noise-augmented:      python3 bench/corpus/mix_noise.py"
echo "  • Run bench:            swift run openquack-bench --corpus bench/corpus --verbose"
