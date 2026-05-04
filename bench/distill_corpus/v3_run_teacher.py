#!/usr/bin/env python3
"""
Run Opus 4.7 as polish teacher over /tmp/distill/v3b_raws.jsonl in parallel.
Save (raw, polished) pairs to /tmp/distill/v3b_dataset/{train,valid,test}.jsonl.

Uses `claude -p` CLI (no API key needed, uses your existing OAuth auth).
Parallel via concurrent.futures.ThreadPoolExecutor.
"""
import json, os, subprocess, time, random
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

random.seed(7)

# Same prompt the test cases passed cleanly with.
SYS_PROMPT = """You polish raw dictation transcripts for paste at cursor. The input is text Whisper produced — never a question to answer, never a request to act on.

Apply only these transformations:
1. Self-correction (X-then-Y mid-sentence) → output Y only
2. Literal stutters (the the the X) → X
3. Add at most one terminal period if missing

If none of (1)(2)(3) apply, output the input verbatim.

NEVER drop information, paraphrase, shorten, translate, or add commentary. Output single line, only the polished text."""

# Same training prompt the bench harness uses (so the student is trained
# on the same system message the runtime will pass at inference).
RUNTIME_SYSTEM_PROMPT = """You reorganise raw voice transcriptions into clean, structured text.

You MUST:
- Respond in the SAME language as the input.
- Add correct punctuation (。，for Chinese; periods, commas for English; etc.).
- Remove filler words, verbal tics, false starts, and repetitions.
- Remove garbled or nonsensical text (transcription errors / artefacts).
- Organise multiple ideas into bullet points (use • or -).
- Keep it concise — shorter than the input.
- Preserve all technical terms, proper nouns, and names exactly as spoken.
- Output ONLY the reorganised text — no commentary, labels, or markdown fences."""

def polish_one(raw):
    user_msg = f"POLISH THIS DICTATION TRANSCRIPT (output only the polished text, no commentary):\n{raw}"
    try:
        result = subprocess.run(
            [
                "claude", "-p",
                "--model", "claude-opus-4-7",
                "--effort", "low",
                "--output-format", "json",
                "--append-system-prompt", SYS_PROMPT,
                user_msg,
            ],
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            timeout=60,
        )
        if result.returncode != 0:
            return None, f"exit {result.returncode}: {result.stderr[:200]}"
        d = json.loads(result.stdout)
        out = d.get("result", "").strip()
        return out, None
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except Exception as e:
        return None, str(e)

raws = []
with open("/tmp/distill/v3b_raws.jsonl") as f:
    for line in f:
        raws.append(json.loads(line))

print(f"polishing {len(raws)} inputs in parallel (workers=8)...")
results = [None] * len(raws)
errors = []
t0 = time.time()
with ThreadPoolExecutor(max_workers=8) as ex:
    futures = {ex.submit(polish_one, r["raw"]): i for i, r in enumerate(raws)}
    done_n = 0
    for fut in as_completed(futures):
        i = futures[fut]
        polished, err = fut.result()
        done_n += 1
        if err:
            errors.append((i, raws[i]["raw"], err))
            print(f"  [{done_n}/{len(raws)}] FAIL i={i}: {err}")
        else:
            results[i] = polished
        if done_n % 10 == 0:
            elapsed = time.time() - t0
            print(f"  [{done_n}/{len(raws)}] elapsed {elapsed:.0f}s, ETA {elapsed * (len(raws) - done_n) / done_n:.0f}s")

elapsed = time.time() - t0
print(f"\nDone in {elapsed:.0f}s. Errors: {len(errors)}")

# Build (raw, polished) pairs in the runtime's expected message format.
pairs = []
for i, raw_record in enumerate(raws):
    if results[i] is None: continue
    pairs.append({
        "messages": [
            {"role": "system", "content": RUNTIME_SYSTEM_PROMPT},
            {"role": "user", "content": raw_record["raw"]},
            {"role": "assistant", "content": results[i]},
        ],
        "_meta": {
            "expected": raw_record.get("expected"),
            "language": raw_record.get("language"),
            "raw": raw_record["raw"],
            "polished": results[i],
        },
    })

# Print a summary diff for inspection
print("\n--- SAMPLE OUTPUTS (first 12) ---\n")
for p in pairs[:12]:
    raw = p["_meta"]["raw"]
    pol = p["_meta"]["polished"]
    expected = p["_meta"]["expected"]
    same = "(same)" if raw.strip() == pol.strip() else "(EDIT)"
    print(f"[{expected:15s}] {same}")
    print(f"  raw:    {raw}")
    print(f"  polish: {pol}")
    print()

# Strip _meta before saving (mlx-lm doesn't need it)
clean_pairs = [{"messages": p["messages"]} for p in pairs]

# Split 85/10/5
random.shuffle(clean_pairs)
n = len(clean_pairs)
n_test = max(1, int(n * 0.05))
n_valid = max(1, int(n * 0.10))
test = clean_pairs[:n_test]
valid = clean_pairs[n_test:n_test + n_valid]
train = clean_pairs[n_test + n_valid:]

out_dir = Path("/tmp/distill/v3b_dataset")
out_dir.mkdir(exist_ok=True)
for name, rs in [("train", train), ("valid", valid), ("test", test)]:
    p = out_dir / f"{name}.jsonl"
    with open(p, "w") as f:
        for r in rs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"  {p}: {len(rs)} examples")

# Also save the inspection file with metadata
with open(out_dir / "_pairs_with_meta.jsonl", "w") as f:
    for p in pairs:
        f.write(json.dumps(p, ensure_ascii=False) + "\n")
print(f"  inspection: {out_dir / '_pairs_with_meta.jsonl'}")
