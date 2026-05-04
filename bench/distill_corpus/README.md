# Polish-pass distillation corpus + scripts

Per [SPEC-016 — distilled polish model](../../docs/SPECS/SPEC-016-distilled-polish-model.md).

## Files

- `generate_raws.py` — synthesises ~350 raw dictation inputs from ~80 polished seed sentences across 6 languages by inserting fillers, stutters, and Whisper-style mishearings.
- `teacher_polish.py` — runs `gemma4-textonly:Q4_K_M` (the recommended Standard-tier polish model) over the raw inputs to produce reference (raw, polished) pairs.
- `bench_student.py` — runs a fused LoRA model over the 34-case OpenQuack polish corpus and writes results into the standard polish-bench JSONL shape.
- `train.jsonl` / `valid.jsonl` / `test.jsonl` — produced by `teacher_polish.py`. 299 / 35 / 17 records in MLX-LM `messages` chat format.

## Reproducing the distilled model

```sh
# 1. Generate raws (no LLM)
python3 bench/distill_corpus/generate_raws.py

# 2. Run teacher (~5 min with gemma4-textonly:Q4_K_M warm)
python3 bench/distill_corpus/teacher_polish.py

# 3. LoRA train (~15 min on M4)
mlx_lm.lora --model mlx-community/gemma-3-1b-it-bf16 --train \
  --data /tmp/distill/dataset \
  --fine-tune-type lora --num-layers 16 --batch-size 2 --iters 300 \
  --learning-rate 1e-4 --adapter-path /tmp/distill/adapters \
  --steps-per-eval 50 --max-seq-length 1024

# 4. Fuse the adapter into the base model
mlx_lm.fuse --model mlx-community/gemma-3-1b-it-bf16 \
  --adapter-path /tmp/distill/adapters \
  --save-path /tmp/distill/student-fused

# 5. Bench the fused model
python3 bench/distill_corpus/bench_student.py /tmp/distill/student-fused gemma3-1b-distilled
```

Bench output lands in `bench/out/polish/<host>-gemma3-1b-distilled/`.
