#!/usr/bin/env python3
"""
v2 dataset addition — informational messages where the polished output
should PRESERVE the content, not aggressively concise it away.

Targets the SPEC-016 v1 ctx_002_* failure mode: model returned
"Let me know if you have a second." for the "deploy is done" inputs
because the v1 training data biased the student toward over-concision.

Strategy: for each seed, produce 1-3 variations:
  (a) the seed exactly as-is (idempotency: clean → clean)
  (b) a lightly-fluffed version (1 leading "hey" / "ok so" / "just")
  (c) a moderately-fluffed version (1 filler injected mid-sentence)

The teacher should produce outputs that PRESERVE the informational
content in all three cases. The student then learns "if there's no
filler to drop, don't invent one to drop — keep the message."
"""
import json, random, os
random.seed(13)

# Informational seeds: status updates, FYI / heads-up, action-complete,
# simple announcements, single-sentence questions. The polished version
# of each of these should look ~identical to the seed (with light
# capitalisation / punctuation cleanup but content preserved).
SEEDS = [
    # status updates
    "the deploy is done and everything looks green",
    "the build finished and all tests passed",
    "the migration completed without errors",
    "the release went out at 3 PM",
    "the rollout hit 100% with no incidents",
    "the cron job ran on schedule this morning",
    "the canary has been stable for an hour",
    "the database backup completed successfully",
    "the staging environment is now in sync with main",
    # FYI / heads up
    "FYI the API rate limit was raised to 10k per hour",
    "heads up the meeting moved to Thursday at 2",
    "just letting you know I pushed the fix to main",
    "wanted to flag that the dashboard is loading slowly",
    "thought you should know the new hire starts Monday",
    "FYI we're seeing a small spike in 5xx errors",
    "heads up I'm taking Friday off",
    # action-complete
    "I merged the PR and deleted the branch",
    "I filed the bug as issue 1247",
    "I added the integration test you suggested",
    "I bumped the dependency to the latest minor version",
    "I drafted the postmortem in the shared doc",
    "I reproduced the race condition locally",
    # simple announcements
    "the all-hands is at 4 PM in the main room",
    "office is closed Monday for the holiday",
    "version 2.3.1 is rolling out tomorrow",
    "the new design system docs are live",
    # statements that should not be rephrased away
    "this is the third time the test has flaked today",
    "the customer escalation came in around lunch",
    "we shipped two features and a bug fix this week",
    "the new caching layer cut p99 latency by 40 percent",
    # questions / small asks
    "can you take a look at the open PR when you get a sec",
    "did the security review come back yet",
    "what's the ETA on the new endpoint",
    "do you have bandwidth to review my doc this afternoon",
    # notices in the same shape as the failing ctx_002 case
    "hey just letting you know the deploy is done and everything looks green",
    "hey just a heads up the build is passing again",
    "hey just letting you know I'm done with the design doc",
    "hey just confirming the cron job ran",
    "ok so the migration is done and we can move on",
    # multilingual
    "デプロイが終わって、すべて緑です",  # JA: deploy done, all green
    "部署完成了，所有测试都通过了",  # ZH: deploy done, all tests passed
    "el despliegue está completo y todo está en verde",  # ES
    "le déploiement est terminé et tout est vert",  # FR
    "das Deployment ist fertig und alles ist grün",  # DE
]

# Light filler banks per language — for the (c) variant only.
LIGHT_FILLERS = {
    "en": ["um", "so", "well", "okay"],
    "zh": ["嗯"],
    "ja": ["えーと"],
    "es": ["bueno"],
    "fr": ["bon"],
    "de": ["also"],
}

def lang_of(text):
    if any('一' <= c <= '鿿' for c in text): return 'zh'
    if any('぀' <= c <= 'ヿ' for c in text): return 'ja'
    if any(c in 'áéíóúñ¿¡' for c in text.lower()): return 'es'
    # Check DE before FR — `ü` is in both, but `ä/ö/ß` are German-only.
    if any(c in 'äöß' for c in text.lower()): return 'de'
    if any(c in 'àâçéèêëîïôùûüÿœæ' for c in text.lower()): return 'fr'
    if 'ü' in text.lower() and not any(c in 'àâçéèêëîïôûÿœæ' for c in text.lower()):
        return 'de'  # ü-only words like "grün" are German
    return 'en'

records = []
for seed in SEEDS:
    lang = lang_of(seed)
    fillers = LIGHT_FILLERS.get(lang, LIGHT_FILLERS['en'])

    # (a) seed as-is — idempotency on informational input
    records.append({"raw": seed, "language": lang, "kind": "informational_idempotent"})

    # (b) one leading filler word
    if random.random() < 0.7:
        lead = random.choice(fillers)
        records.append({"raw": f"{lead} {seed}", "language": lang, "kind": "informational_light"})

    # (c) one mid-sentence filler
    if random.random() < 0.5 and len(seed.split()) > 5:
        words = seed.split()
        pos = random.randint(2, len(words) - 2)
        words.insert(pos, random.choice(fillers))
        records.append({"raw": ' '.join(words), "language": lang, "kind": "informational_mid"})

# Dedup
seen = set()
out = []
for r in records:
    k = (r['raw'], r['language'])
    if k in seen: continue
    seen.add(k)
    out.append(r)

random.shuffle(out)
os.makedirs('/tmp/distill', exist_ok=True)
with open('/tmp/distill/raws_informational.jsonl', 'w') as f:
    for r in out:
        f.write(json.dumps(r, ensure_ascii=False) + '\n')

from collections import Counter
print(f"Generated {len(out)} informational raw inputs")
print(f"By kind: {dict(Counter(r['kind'] for r in out))}")
print(f"By language: {dict(Counter(r['language'] for r in out))}")
print("\nFirst 6:")
for r in out[:6]:
    print(f"  [{r['language']}] [{r['kind']}] {r['raw']}")
