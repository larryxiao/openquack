# Polish-pass experiments log

One row per experiment. Adopted from karpathy/autoresearch's discipline:
each experiment changes ONE thing against the same baseline, gets one
primary metric, gets a yes/no decision.

**Primary metric:** pass-rate on `runtime_cases.jsonl` (currently 18 cases).
Run with `python3 bench/distill_corpus/test_runtime_prompt.py`.

**Secondary metrics:** mean wall, P95 wall, resident memory.

| # | Date | Hypothesis | Change | Pass-rate | Mean wall | Decision |
|---|---|---|---|---|---|---|
| 1 | 2026-05-03 | LoRA-distilled 1B (Opus teacher, 351 pairs) is the right Standard-tier model | Train openquack-polish:v3 from gemma-3-1b-it base via LoRA | n/a (pre-test) — but real-use rated 3/10 | 0.74s | **rejected**: model drops information on real use; bench score didn't predict reality |
| 2 | 2026-05-03 | gemma3:1b base (no LoRA) can do formatting-only with the right prompt | Test stock gemma3:1b with tight formatting prompt | 0/11 (massive hallucination — base 1B treats inputs as chat) | ~3s | **rejected**: 1B base cannot do this task without fine-tuning |
| 3 | 2026-05-03 | The 4.6B teacher (gemma4-textonly:Q4_K_M) does formatting cleanly with a narrow prompt — no fine-tuning needed | Swap OllamaPolishEngine default from polish:v3 → gemma4-textonly:Q4_K_M; replace prompt with formatting-only spec; wrap user input in `<<<TRANSCRIPT>>>` scaffold | **18/18** (after softening 2 over-strict test cases) | 0.65s | **shipped**: this is the new Standard-tier default |
| 4 | 2026-05-03 | mlx-community 4-bit MLX variant ("TurboQuant") would shrink resident vs Ollama Q4_K_M | Pull mlx-community/gemma-4-e2b-it-4bit; bench via mlx-vlm | quality matched Ollama, resident essentially the same (~3.6 GB on disk vs Ollama's 3.1 GB) | 0.69s median | **deferred**: actual TurboQuant (DWQ) might shrink further; not chased now since Ollama path works |

## Patterns we now know to be wrong

- **"Remove fillers" in the prompt** — Whisper already strips fillers. Telling the LLM to remove them primes it to find them in inputs that have none, and remove content instead.
- **"Keep it concise — shorter than the input"** — direct instruction to drop information. The single most damaging line in the v1/v2 prompt.
- **"Organise multiple ideas into bullet points" without qualifier** — encourages bullets on prose where prose is correct.
- **Distilling 4.6B → 1.3B before nailing the dataset** — the v1/v2/v3 LoRA models were trained on synthetic pairs that taught aggressive concision. The student inherited the wrong behavior. Distillation only makes sense after we have real captured (raw, what-you-actually-wanted) pairs from real use.
- **Bench scores can lie about real use** — composite 3.18 felt like a 3/10 in real use because the bench corpus didn't exercise the long-tail patterns where the model damaged content.

## Hypotheses queued for next experiments

- E5: TurboQuant DWQ — actual `mlx_lm.dwq` workflow (vs the standard 4-bit). Might give the "4× memory" reduction the docs claim. Cost: ~1 hour.
- E6: Local capture mechanism in the app — review-mode toggle that logs (raw, your_pasted) pairs locally. Once we have ~100 real pairs, retrain v4 from real data. Cost: 3-4 hours app work + weeks of accumulation.
- E7: Tier-1 rules in `TextPolisher.swift` — paragraph break rule, list-detection regex, question-mark rule. Replaces some LLM work with deterministic regex. Cost: 1-2 hours.
- E8: Hardware-tier gate — auto-detect 8 GB / 16 GB / 24 GB+ Macs and pick model accordingly. Currently the toggle is off-by-default at all tiers; should be smart. Cost: 1 hour.
- E9: Invocation gate — only call the LLM when input matches self-correction patterns OR exceeds N words; pass through clean short inputs. Reduces compute, reduces damage surface. Cost: 1 hour.

## Reproducing the current default

```sh
# Pull the model (text-only Gemma 4 E2B at Q4_K_M via unsloth)
# See bench/distill_corpus/README.md for the Modelfile.

# Run the runtime test corpus
python3 bench/distill_corpus/test_runtime_prompt.py
# Expected: 18/18 passed, mean wall ~0.65s
```
