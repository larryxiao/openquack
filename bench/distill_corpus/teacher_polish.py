#!/usr/bin/env python3
"""
Run the teacher (gemma4-textonly:Q4_K_M) over the synthetic raws and save
(raw, polished) pairs as JSONL. Output is MLX-LM compatible chat format.

Output: /tmp/distill/dataset/{train,valid,test}.jsonl
"""
import json, urllib.request, sys, os
from pathlib import Path

# Same prompt as the polish bench v2 — copied so distillation matches the polish task.
SYSTEM_PROMPT = """You reorganise raw voice transcriptions into clean, structured text.

You MUST:
- Respond in the SAME language as the input.
- Add correct punctuation (。，for Chinese; periods, commas for English; etc.).
- Remove filler words, verbal tics, false starts, and repetitions.
- Remove garbled or nonsensical text (transcription errors / artefacts).
- Organise multiple ideas into bullet points (use • or -).
- Keep it concise — shorter than the input.
- Preserve all technical terms, proper nouns, and names exactly as spoken.
- Output ONLY the reorganised text — no commentary, labels, or markdown fences."""

TEACHER = "gemma4-textonly:Q4_K_M"

def polish(raw):
    req = urllib.request.Request(
        "http://localhost:11434/api/chat",
        data=json.dumps({
            "model": TEACHER,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": raw},
            ],
            "stream": False,
            "think": False,
            "keep_alive": -1,
            "options": {"temperature": 0.3, "num_predict": 256},
        }).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())["message"]["content"].strip()

# Warm the teacher (prevents first-call long latency)
print(f"warming teacher {TEACHER}...")
urllib.request.urlopen(urllib.request.Request(
    "http://localhost:11434/api/chat",
    data=json.dumps({"model": TEACHER, "messages": [], "keep_alive": -1}).encode(),
    headers={"Content-Type": "application/json"},
), timeout=60).read()
print("ok\n")

# Read raws
raws = []
with open("/tmp/distill/raws.jsonl") as f:
    for line in f:
        raws.append(json.loads(line))

out_dir = Path("/tmp/distill/dataset")
out_dir.mkdir(exist_ok=True)

records = []
for i, r in enumerate(raws, 1):
    try:
        polished_text = polish(r["raw"])
    except Exception as e:
        print(f"  [{i}/{len(raws)}] {r['raw'][:50]}... ERROR: {e}")
        continue
    record = {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": r["raw"]},
            {"role": "assistant", "content": polished_text},
        ]
    }
    records.append(record)
    if i % 25 == 0:
        print(f"  [{i}/{len(raws)}] {r['raw'][:40]} → {polished_text[:40]}")

print(f"\nProduced {len(records)} (raw, polished) pairs")

# Filter: drop empty, near-identical (no work for student), and absurdly long.
filtered = []
for rec in records:
    raw = rec["messages"][1]["content"].strip()
    pol = rec["messages"][2]["content"].strip()
    if not pol:
        continue
    if len(pol) > 8 * max(1, len(raw)):  # absurd expansion
        continue
    filtered.append(rec)

print(f"After filter: {len(filtered)} records")

# Shuffle + split 85 / 10 / 5
import random
random.seed(7)
random.shuffle(filtered)
n = len(filtered)
n_valid = max(1, int(n * 0.10))
n_test = max(1, int(n * 0.05))
test = filtered[:n_test]
valid = filtered[n_test:n_test + n_valid]
train = filtered[n_test + n_valid:]

for name, rs in [("train", train), ("valid", valid), ("test", test)]:
    p = out_dir / f"{name}.jsonl"
    with open(p, "w") as f:
        for r in rs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"  {p} : {len(rs)} examples")

print("\nDone.")
