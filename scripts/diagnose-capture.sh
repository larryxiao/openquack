#!/usr/bin/env bash
# Diagnose & fix the "transcript is just 'You.' / 'Thank you.'" problem.
#
# That output is Whisper hallucinating on SILENT audio — it almost always
# means the mic wasn't actually captured (permission not effective, or the
# wrong input device), not a model bug. This script:
#   1. Shows the active input device.
#   2. Records 3 s straight from the mic (independent of OpenQuack) and
#      reports the peak level, so you can tell signal from silence.
#   3. Resets OpenQuack's stale Microphone/Accessibility TCC grants.
#   4. Restarts the app so macOS re-prompts cleanly.
#
# Usage: bash scripts/diagnose-capture.sh          # full: probe + reset + restart
#        bash scripts/diagnose-capture.sh probe    # mic probe only (no reset)
set -uo pipefail

MODE="${1:-full}"
BUNDLE_ID="org.openquack.OpenQuack"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/OpenQuack.app"
[[ -d "$APP" ]] || APP="/Applications/OpenQuack.app"

echo "──────────────────────────────────────────────"
echo " OpenQuack capture diagnosis"
echo "──────────────────────────────────────────────"

echo
echo "▸ Active audio input device(s):"
system_profiler SPAudioDataType 2>/dev/null \
  | awk '/Input Source|Default Input Device|Manufacturer:/{print "   "$0}' \
  | sed 's/^   *//' | sed 's/^/   /' || echo "   (could not read)"

echo
echo "▸ Mic signal probe — recording 3 s directly from the system mic."
PROBE="$(mktemp -t oqmicprobe).swift"
cat > "$PROBE" <<'SWIFT'
import AVFoundation
import Foundation

let status = AVCaptureDevice.authorizationStatus(for: .audio)
if status == .denied || status == .restricted {
    print("RESULT: TERMINAL_DENIED — the terminal running this script has no")
    print("        Microphone permission. Grant it in System Settings →")
    print("        Privacy & Security → Microphone (enable your terminal app),")
    print("        then re-run. This is about the terminal, not OpenQuack.")
    exit(2)
}
let sem = DispatchSemaphore(value: 0)
var granted = true
if status == .notDetermined {
    AVCaptureDevice.requestAccess(for: .audio) { ok in granted = ok; sem.signal() }
    sem.wait()
}
guard granted else {
    print("RESULT: TERMINAL_DENIED — permission request was declined.")
    exit(2)
}

let engine = AVAudioEngine()
let input = engine.inputNode
let fmt = input.inputFormat(forBus: 0)
guard fmt.sampleRate > 0 else {
    print("RESULT: NO_DEVICE — no usable input device/format (sampleRate=0).")
    exit(3)
}
var peak: Float = 0
var sumSq: Double = 0
var count: Int = 0
input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
    guard let ch = buf.floatChannelData?[0] else { return }
    let n = Int(buf.frameLength)
    for i in 0..<n {
        let v = ch[i]
        peak = max(peak, abs(v))
        sumSq += Double(v * v)
        count += 1
    }
}
do { try engine.start() } catch {
    print("RESULT: ENGINE_FAILED — \(error.localizedDescription)")
    exit(3)
}
FileHandle.standardOutput.write("   >>> please speak now (3s)…\n".data(using: .utf8)!)
Thread.sleep(forTimeInterval: 3)
engine.stop()
let rms = count > 0 ? (sumSq / Double(count)).squareRoot() : 0
print(String(format: "   device sample rate: %.0f Hz", fmt.sampleRate))
print(String(format: "   peak amplitude: %.4f   rms: %.4f", peak, rms))
if peak < 0.01 {
    print("RESULT: SILENT — the mic captured essentially no signal.")
    print("        Either nothing was spoken, the input device is wrong/muted,")
    print("        or the mic is dead. Try System Settings → Sound → Input and")
    print("        watch the input level bar while you talk.")
} else {
    print("RESULT: OK — the mic IS capturing audio at the system level.")
    print("        So if OpenQuack still returns 'You.', it's OpenQuack's mic")
    print("        permission specifically — the reset below fixes that.")
}
SWIFT
swift "$PROBE" 2>&1
PROBE_RC=$?
rm -f "$PROBE"

[[ "$MODE" == "probe" ]] && { echo; echo "(probe-only mode — skipping reset/restart)"; exit "$PROBE_RC"; }

echo
echo "▸ Resetting OpenQuack's TCC grants (clears stale entries so macOS"
echo "  re-prompts cleanly on next recording)…"
tccutil reset Microphone   "$BUNDLE_ID" 2>&1 | sed 's/^/   /' || true
tccutil reset Accessibility "$BUNDLE_ID" 2>&1 | sed 's/^/   /' || true
echo "   done."

echo
echo "▸ Restarting OpenQuack…"
pkill -f "OpenQuack.app/Contents/MacOS/openquack" 2>/dev/null && echo "   stopped old instance" || echo "   (no running instance)"
sleep 1
if [[ -d "$APP" ]]; then
    open "$APP" && echo "   launched: $APP"
else
    echo "   ⚠ app bundle not found at $APP — build it with scripts/wrap_app.sh"
fi

echo
echo "──────────────────────────────────────────────"
echo " Next: record once in OpenQuack. macOS will re-ask for the mic —"
echo " click Allow. Watch the overlay's level meter move as you speak."
echo " Probe exit code: $PROBE_RC"
echo "──────────────────────────────────────────────"
