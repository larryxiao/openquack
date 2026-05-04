#!/usr/bin/env python3
"""
Run the LoRA-distilled student over the 34-case polish corpus and write
results in the same JSONL shape as openquack-polish-bench so we can
compare/judge alongside the Ollama runs.

Output: bench/out/polish/M4-16GB-distilled/results.jsonl
"""
import json, time, sys, os, gc
from pathlib import Path

sys.path.insert(0, '/Users/x/Library/Python/3.13/lib/python/site-packages')
from mlx_lm import load, generate
import mlx.core as mx

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

def cjk_word_count(text):
    """Mirror the SPEC-007 / v0.1 heuristic for picking num_predict."""
    cjk = sum(1 for c in text if '぀' <= c <= '鿿' or '가' <= c <= '힯')
    latin = len([w for w in text.split() if w.strip()])
    return cjk + latin

cases = []
with open('/Users/x/projects/local_quack/bench/polish_corpus/cases.jsonl') as f:
    for line in f:
        cases.append(json.loads(line))

MODEL_PATH = sys.argv[1] if len(sys.argv) > 1 else '/tmp/distill/student-fused'
LABEL = sys.argv[2] if len(sys.argv) > 2 else 'gemma3-1b-distilled'
OUT_DIR = Path(f'/Users/x/projects/local_quack/bench/out/polish/M4-16GB-{LABEL}')
OUT_DIR.mkdir(parents=True, exist_ok=True)

print(f"Loading {MODEL_PATH}...")
t0 = time.time()
model, tokenizer = load(MODEL_PATH)
print(f"loaded in {time.time()-t0:.2f}s")

# Warm-up
_ = generate(model, tokenizer, prompt="hello", max_tokens=4, verbose=False)

results = []
for i, case in enumerate(cases, 1):
    raw = case['raw']
    wc = cjk_word_count(raw)
    num_predict = min(max(wc * 2, 80), 512)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": raw},
    ]
    prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)

    t = time.time()
    output = generate(
        model, tokenizer,
        prompt=prompt,
        max_tokens=num_predict,
        verbose=False,
    )
    wall = time.time() - t

    result = {
        "case_id": case['id'],
        "category": case['category'],
        "language": case['language'],
        "model": LABEL,
        "prompt_id": "v2",
        "raw": raw,
        "polished": output.strip(),
        "total_s": wall,
        "use_surrounding_text": False,
        "vocab_size": 0,
    }
    results.append(result)
    print(f"  [{i:2d}/{len(cases)}] ({wall:5.2f}s) {case['id']}: {output.strip()[:80]}")

    # Encourage MLX to release intermediate tensors
    if i % 5 == 0:
        gc.collect()

with open(OUT_DIR / 'results.jsonl', 'w') as f:
    for r in results:
        f.write(json.dumps(r, ensure_ascii=False) + '\n')

# Summary stats
import statistics
walls = [r['total_s'] for r in results]
print(f"\nWrote {OUT_DIR}/results.jsonl ({len(results)} cases)")
print(f"Mean wall: {statistics.mean(walls):.2f}s")
print(f"Median wall: {statistics.median(walls):.2f}s")
print(f"P95 wall: {sorted(walls)[int(len(walls)*0.95)]:.2f}s")
print(f"Max wall: {max(walls):.2f}s")
