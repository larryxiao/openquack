#!/usr/bin/env python3
"""
Generate synthetic raw dictation inputs for the distillation dataset.

Strategy: take ~120 polished seed sentences (from corpus refs + curated additions),
apply realistic Whisperification per sentence: filler insertion, stutter,
case/punct stripping, occasional proper-noun mishearing. Save as raw_inputs.jsonl.

Goal: 300-400 diverse raw inputs that mimic real Whisper-after-medium-model output
across the SPEC-007 polish dimensions.
"""
import json, random, re
random.seed(42)

# Seed sentences — start with the corpus refs, then expand.
# Mix of: tech/dev sentences, conversational, multilingual, lists, idempotent ones.
SEEDS = [
    # tech / dev (English)
    "Use Claude Code to open a PR for this branch.",
    "Use WhisperKit medium with mlx-swift.",
    "Run gemma3:1b and qwen2.5.",
    "OpenQuack uses SPM, not CocoaPods.",
    "We should refactor the polish module.",
    "Drop the Python dependency.",
    "Set up the bench, pull the models, run them.",
    "The build is failing on CI again because of the flaky test.",
    "Let's go with the smaller model.",
    "Meeting at 3 PM tomorrow to discuss bench results.",
    "The deploy is complete and the system is green.",
    "Fix the bug in the polish engine where it drops the last word.",
    "Pull the latest from main and rebase your branch.",
    "Add a unit test for the new endpoint.",
    "The cache invalidation logic needs review.",
    "We're rate-limited by the upstream API.",
    "The migration script needs to handle null values.",
    "Roll back to the previous deploy.",
    "Bump the dependency to the latest minor version.",
    "Ship behind a feature flag and gradually ramp.",
    "The query is doing a full table scan.",
    "Add an index on the user_id column.",
    "The cron job didn't run last night.",
    "Increase the timeout for the upstream call.",
    "Memoize the result, it's recomputed every render.",
    "Use a Set instead of an Array for O(1) lookup.",
    "The test is flaky on CI but passes locally.",
    "Bisect the regression to find the bad commit.",
    "Merge the conflict and force-push the branch.",
    "Review the security implications before merging.",
    # conversational / informal (English)
    "Could you grab a coffee, a tea, and a sandwich please?",
    "I think we should ship this on Friday.",
    "Let me know if you need help with the migration.",
    "Send me the dashboard link when you have a sec.",
    "I'm thinking of taking next Friday off.",
    "What time does the meeting start?",
    "Did you see the email from legal about the audit?",
    "I'll be in late tomorrow due to a doctor's appointment.",
    "Can we push the launch to next week?",
    "The customer escalated and we need to respond today.",
    "Let's sync after lunch to align on priorities.",
    "I disagree with the current approach but let's discuss.",
    "We should document this decision in the wiki.",
    "Add it to the agenda for the next standup.",
    "The new hire starts on Monday.",
    "Heads up the budget meeting is moved to 4 PM.",
    "I'll write the postmortem and circulate it tomorrow.",
    "The proposal looks good but needs more numbers.",
    "Loop in the design team on this thread.",
    "The retro went well, action items posted in Slack.",
    # idempotency check (clean text — should pass through almost unchanged)
    "Hello world.",
    "The quick brown fox jumps over the lazy dog.",
    "Voice dictation should respect privacy.",
    "Local-first software is good for users.",
    "Apple Silicon is fast for on-device inference.",
    # Chinese
    "我觉得我们可以重构 polish 模块。",
    "我们应该用 Claude Code 来打开一个 PR。",
    "明天下午三点开会讨论基准测试结果。",
    "数据库迁移脚本需要处理空值情况。",
    "把超时时间调长一点试试。",
    # Japanese
    "ポリッシュモジュールをリファクタしようと思います。",
    "明日の三時から会議があります。",
    "テストがCIで失敗しています。",
    "依存関係を最新版に更新してください。",
    "新しいエンドポイントにユニットテストを追加します。",
    # Spanish
    "Deberíamos usar el modelo más pequeño.",
    "La compilación está fallando en CI.",
    "Hay que documentar esta decisión en el wiki.",
    "El despliegue está completo y todo está verde.",
    "Voy a llegar tarde mañana.",
    # French
    "On devrait utiliser le modèle plus petit.",
    "Le déploiement est terminé et tout est vert.",
    "Réunion à quinze heures demain pour discuter des résultats.",
    "Le test est instable sur CI mais passe localement.",
    "Je vais arriver en retard demain matin.",
    # German
    "Wir sollten das kleinere Modell nehmen.",
    "Der Build schlägt im CI wieder fehl.",
    "Das Deployment ist fertig und alles ist grün.",
    "Bitte den Code Review machen bevor du mergest.",
    "Lass uns nach dem Mittag synchronisieren.",
]

# Filler banks per language
FILLERS = {
    "en": ["um", "uh", "like", "you know", "I mean", "basically", "actually", "literally", "so", "well"],
    "zh": ["嗯", "那个", "就是", "然后呢"],
    "ja": ["えーと", "あのー", "まあ", "そのー"],
    "es": ["este", "eh", "o sea", "bueno"],
    "fr": ["euh", "ben", "en fait", "tu vois"],
    "de": ["äh", "halt", "also", "irgendwie"],
}

# Whisper-style mishearings — common substitutions that the polish step should fix
MISHEARINGS = [
    ("Claude Code", "cloud code"),
    ("Claude", "cloud"),
    ("OpenQuack", "open black"),
    ("OpenQuack", "open quack"),  # capitalization-error variant
    ("WhisperKit", "whisper kit"),
    ("mlx-swift", "em el ex swift"),
    ("MLX", "em el ex"),
    ("SPM", "ese pe em"),
    ("CocoaPods", "coca pods"),
    ("gemma3", "gemma three"),
    ("qwen2.5", "quen two point five"),
    ("Apple Silicon", "apple silicon"),
    ("Privacy-first", "try the zebras"),
    ("in-context", "income tax"),
    ("CI", "see eye"),
    ("PR", "pee are"),
    ("the lazy dog", "the lady dog"),
]

def lang_of(text):
    if any('一' <= c <= '鿿' for c in text): return 'zh'
    if any('぀' <= c <= 'ヿ' for c in text): return 'ja'
    if any(c in 'áéíóúñ¿¡' for c in text.lower()): return 'es'
    if any(c in 'àâçéèêëîïôùûüÿœæ' for c in text.lower()): return 'fr'
    if any(c in 'äöüß' for c in text.lower()): return 'de'
    return 'en'

def whisperify(sentence, severity=2):
    """Apply 0..N transformations to make sentence look like raw Whisper dictation."""
    out = sentence
    lang = lang_of(out)
    fillers = FILLERS.get(lang, FILLERS['en'])

    # 1. Maybe apply a mishearing
    if random.random() < 0.30:
        eligible = [(c, w) for c, w in MISHEARINGS if c in out]
        if eligible:
            correct, wrong = random.choice(eligible)
            out = out.replace(correct, wrong, 1)

    # 2. Strip terminal punctuation sometimes
    if random.random() < 0.45:
        out = re.sub(r'[.!?。！？]\s*$', '', out)

    # 3. Lowercase the first letter sometimes (English)
    if lang == 'en' and random.random() < 0.35 and out and out[0].isupper():
        out = out[0].lower() + out[1:]

    # 4. Strip mid-sentence commas sometimes
    if random.random() < 0.30:
        out = out.replace(', ', ' ').replace('，', ' ')

    # 5. Insert fillers at start
    if random.random() < 0.55:
        n = random.randint(1, 2)
        prefix = ' '.join(random.sample(fillers, min(n, len(fillers))))
        out = f"{prefix} {out}"

    # 6. Insert mid-sentence filler
    if random.random() < 0.30:
        words = out.split(' ')
        if len(words) > 4:
            pos = random.randint(2, len(words) - 2)
            mid = random.choice(fillers)
            words.insert(pos, mid)
            out = ' '.join(words)

    # 7. Stutter
    if random.random() < 0.15:
        words = out.split(' ', 1)
        if len(words) >= 1 and words[0]:
            stutter = ' '.join([words[0]] * random.randint(2, 3))
            out = stutter + (' ' + words[1] if len(words) > 1 else '')

    # 8. False start (English)
    if lang == 'en' and random.random() < 0.20:
        starters = ["I think we should", "I mean", "actually", "let me think"]
        out = f"{random.choice(starters)} {out}"

    return out.strip()

# Generate dataset: each seed → N variations (some clean idempotent passthroughs).
records = []
for seed in SEEDS:
    lang = lang_of(seed)
    # 1 idempotency pass-through (clean → should equal clean)
    if random.random() < 0.20:
        records.append({"raw": seed, "language": lang, "kind": "idempotent"})
    # 4-5 augmented variations
    for _ in range(random.randint(4, 6)):
        raw = whisperify(seed, severity=random.randint(1, 3))
        if raw and raw != seed:
            records.append({"raw": raw, "language": lang, "seed": seed, "kind": "augmented"})

# Dedup
seen = set()
out_records = []
for r in records:
    k = (r['raw'], r['language'])
    if k in seen: continue
    seen.add(k)
    out_records.append(r)

random.shuffle(out_records)

import os
os.makedirs('/tmp/distill', exist_ok=True)
with open('/tmp/distill/raws.jsonl', 'w') as f:
    for r in out_records:
        f.write(json.dumps(r, ensure_ascii=False) + '\n')

# Stats
from collections import Counter
by_lang = Counter(r['language'] for r in out_records)
by_kind = Counter(r['kind'] for r in out_records)
print(f"Generated {len(out_records)} raw inputs")
print(f"By language: {dict(by_lang)}")
print(f"By kind: {dict(by_kind)}")
print(f"\nFirst 6 examples:")
for r in out_records[:6]:
    print(f"  [{r['language']}] {r['raw']}")
