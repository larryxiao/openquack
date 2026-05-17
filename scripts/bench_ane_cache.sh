#!/bin/bash
# bench_ane_cache.sh — volunteer measurement script for SPEC-030
#
# Measures:
#   1. WhisperKit model source weights on disk
#   2. e5rt (CoreML / ANE) compiled cache size
#   3. Cold + warm transcribe latency on a short sample clip
#
# Writes JSON to bench/out/<host-tag>/cache-report.json and prints a
# copy-pasteable markdown summary at the end.
#
# Read-only outside bench/out/. Bash 3.2 compatible (stock macOS).
# No network calls. No audio / transcript content is uploaded — only
# durations, byte counts, and host fields.
#
# Usage:
#   bash scripts/bench_ane_cache.sh                 # uses bundled sample
#   bash scripts/bench_ane_cache.sh path/to/clip.wav # custom clip
#
# Exit codes:
#   0  report written
#   1  could not locate OpenQuack app or cache (see error)
#   2  user-aborted at the timed-transcribe step

set -u

SAMPLE_CLIP_DEFAULT="bench/corpus/samples/short_en_10s.wav"
APP_SUPPORT="$HOME/Library/Application Support/OpenQuack/WhisperKit"
CACHES_ROOT="$HOME/Library/Caches/org.openquack.OpenQuack"

# --- Host fields ---------------------------------------------------------
chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
hw_model="$(sysctl -n hw.model 2>/dev/null || echo unknown)"
mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
ram_gb=$(( mem_bytes / 1024 / 1024 / 1024 ))
macos_build="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
macos_version="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
form_factor="$(system_profiler SPHardwareDataType 2>/dev/null \
  | awk -F': ' '/Model Name/ {print $2; exit}')"

host_tag="$(echo "$hw_model-$ram_gb-$macos_build" | tr ' /' '-_' | tr -d '(),')"

# --- Sanity checks -------------------------------------------------------
if [ ! -d "$APP_SUPPORT" ]; then
  echo "error: $APP_SUPPORT not found." >&2
  echo "Install OpenQuack and run a transcription at least once, then re-run." >&2
  exit 1
fi

# --- Helpers -------------------------------------------------------------
# du -sk gives KB on macOS; multiply ×1024 for bytes.
dir_bytes() {
  if [ -d "$1" ]; then
    du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
  else
    echo 0
  fi
}

ms_since() {
  # epoch ms diff using python3 (ships with macOS via Xcode CLT) or
  # falls back to date +%s if python3 absent.
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import time, sys; print(int((time.time() - float(sys.argv[1])) * 1000))" "$1"
  else
    echo $(( ($(date +%s) - ${1%.*}) * 1000 ))
  fi
}

epoch_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import time; print(time.time())"
  else
    date +%s
  fi
}

# --- Model source weights ------------------------------------------------
models_root="$APP_SUPPORT/models/argmaxinc/whisperkit-coreml"
models_json=""
if [ -d "$models_root" ]; then
  for variant_dir in "$models_root"/*; do
    [ -d "$variant_dir" ] || continue
    variant="$(basename "$variant_dir")"
    case "$variant" in .*) continue ;; esac
    bytes=$(dir_bytes "$variant_dir")
    [ -n "$models_json" ] && models_json="$models_json,"
    models_json="$models_json"$'\n    '"{\"variant\": \"$variant\", \"bytes\": $bytes}"
  done
fi

# --- e5rt cache ----------------------------------------------------------
e5rt_root="$CACHES_ROOT/com.apple.e5rt.e5bundlecache"
e5rt_bytes=$(dir_bytes "$e5rt_root")
e5rt_os_build=""
e5rt_bundles=0
if [ -d "$e5rt_root" ]; then
  # First-level child is the OS-build path segment.
  e5rt_os_build="$(ls -1 "$e5rt_root" 2>/dev/null | head -n1)"
  if [ -n "$e5rt_os_build" ] && [ -d "$e5rt_root/$e5rt_os_build" ]; then
    e5rt_bundles=$(find "$e5rt_root/$e5rt_os_build" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi
fi

# --- Timed transcribes ---------------------------------------------------
clip="${1:-$SAMPLE_CLIP_DEFAULT}"
cold_ms="null"
warm_ms="null"
sample_clip_label="$clip"

if [ ! -f "$clip" ]; then
  echo "warn: sample clip '$clip' not found." >&2
  echo "      You can supply your own: bash scripts/bench_ane_cache.sh path/to.wav" >&2
  echo "      Continuing without timing data." >&2
else
  if command -v openquack-cli >/dev/null 2>&1; then
    # Cold = kill any warm pipe first. We can't actually flush the ANE
    # cache from userspace, so this measures *process* cold-start, not
    # cache-miss cold-start. A true cache-miss measurement requires a
    # macOS update or manual deletion of e5rt — out of scope here.
    echo "Running cold transcribe (this may take 10–30 s)..."
    t0=$(epoch_ms)
    if openquack-cli transcribe --quiet "$clip" >/dev/null 2>&1; then
      cold_ms=$(ms_since "$t0")
    else
      echo "warn: cold transcribe failed; reporting null." >&2
    fi
    echo "Running warm transcribe..."
    t0=$(epoch_ms)
    if openquack-cli transcribe --quiet "$clip" >/dev/null 2>&1; then
      warm_ms=$(ms_since "$t0")
    else
      echo "warn: warm transcribe failed; reporting null." >&2
    fi
  else
    cat <<'EOF' >&2

note: openquack-cli not on PATH. Skipping timed-transcribe step.

To include timings in your report:
  1. Quit OpenQuack (menu bar → Quit), then relaunch.
  2. Dictate any ~10 s phrase using the hotkey, time it with a stopwatch.
     (This is your "cold" number.)
  3. Dictate again immediately. (This is your "warm" number.)
  4. Re-run this script with the numbers in env vars:
       OQ_COLD_MS=14300 OQ_WARM_MS=820 bash scripts/bench_ane_cache.sh

EOF
    [ -n "${OQ_COLD_MS:-}" ] && cold_ms="$OQ_COLD_MS"
    [ -n "${OQ_WARM_MS:-}" ] && warm_ms="$OQ_WARM_MS"
  fi
fi

# --- OpenQuack version ---------------------------------------------------
oq_version="unknown"
for app_path in "/Applications/OpenQuack.app" "$HOME/Applications/OpenQuack.app"; do
  if [ -f "$app_path/Contents/Info.plist" ]; then
    oq_version="$(defaults read "$app_path/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unknown)"
    break
  fi
done

# --- Write report --------------------------------------------------------
out_dir="bench/out/$host_tag"
mkdir -p "$out_dir"
report_path="$out_dir/cache-report.json"

captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$report_path" <<EOF
{
  "host": {
    "chip": "$chip",
    "hw_model": "$hw_model",
    "form_factor": "$form_factor",
    "ram_gb": $ram_gb,
    "macos_version": "$macos_version",
    "macos_build": "$macos_build"
  },
  "openquack_version": "$oq_version",
  "models_on_disk": [$models_json
  ],
  "e5rt_cache": {
    "path_os_build": "$e5rt_os_build",
    "total_bytes": $e5rt_bytes,
    "bundles": $e5rt_bundles
  },
  "timings": {
    "cold_transcribe_ms": $cold_ms,
    "warm_transcribe_ms": $warm_ms,
    "sample_clip": "$sample_clip_label"
  },
  "captured_at": "$captured_at"
}
EOF

# --- Human-readable summary ---------------------------------------------
human_bytes() {
  python3 - "$1" <<'PY' 2>/dev/null || echo "$1 B"
import sys
n = int(sys.argv[1])
for u in ["B","KB","MB","GB","TB"]:
    if n < 1024 or u == "TB":
        print(f"{n:.1f} {u}")
        break
    n /= 1024
PY
}

echo
echo "================================================================"
echo "Report written to $report_path"
echo "================================================================"
echo
echo "Paste the block below into the GitHub Discussion thread for SPEC-030"
echo "(or open a PR adding $report_path)."
echo
echo "----- start summary -----"
echo "**Host:** $chip — $hw_model — ${ram_gb} GB RAM — macOS $macos_version ($macos_build)"
echo "**OpenQuack:** $oq_version"
echo
echo "| Metric | Value |"
echo "|---|---|"
total_model_bytes=0
if [ -d "$models_root" ]; then
  for variant_dir in "$models_root"/*; do
    [ -d "$variant_dir" ] || continue
    variant="$(basename "$variant_dir")"
    case "$variant" in .*) continue ;; esac
    b=$(dir_bytes "$variant_dir")
    total_model_bytes=$(( total_model_bytes + b ))
    echo "| Model source — $variant | $(human_bytes "$b") |"
  done
fi
echo "| **Source weights total** | $(human_bytes "$total_model_bytes") |"
echo "| e5rt cache total | $(human_bytes "$e5rt_bytes") (OS build \`$e5rt_os_build\`, $e5rt_bundles bundles) |"
echo "| Cold transcribe | ${cold_ms} ms |"
echo "| Warm transcribe | ${warm_ms} ms |"
echo "----- end summary -----"
echo
