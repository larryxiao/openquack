#!/usr/bin/env python3
"""
v3b raw-input generator — expanded dataset (~600 examples).

DATA SECURITY CONTRACT
======================
Every seed sentence in this file is HAND-WRITTEN synthetic content. None of
it comes from real user dictations or any user data. This file is the only
input to `v3b_run_teacher.py`, which sends it through the Anthropic API
(via `claude -p`). It is therefore safe to send to a third-party API.

If we ever want to train on REAL user dictations, the capture must happen
locally on the user's machine and the model must be trained locally without
the data ever leaving — DO NOT send actual user dictations through this
pipeline.

DISTRIBUTION TARGET (~600 examples)
==================================
- ~70% passthrough (clean inputs that should be preserved)
- ~15% self-corrections (the high-value polish case)
- ~5% stutters / repetitions
- ~10% edge cases (lists, questions, code-mixed, numbers, very-short)

LANGUAGE MIX
============
- ~50% EN, ~10% each ZH JA ES FR DE
"""
import json, random, os
random.seed(42)

# =========================================================================
# CLEAN PASSTHROUGH SEEDS — by domain. These are what real Whisper output
# looks like (Whisper-medium already strips um/uh/etc).
# =========================================================================

CLEAN_EN_DEV = [
    # Backend / infra
    "the build is failing on CI again because of a flaky test",
    "the deploy went out at 3 PM and everything looks green",
    "I bumped the dependency to the latest minor version",
    "the migration completed without errors",
    "we should add an index on the user_id column",
    "the cron job didn't run last night",
    "memoize the result, it's recomputed every render",
    "use a Set instead of an Array for O(1) lookup",
    "the test is flaky on CI but passes locally",
    "bisect the regression to find the bad commit",
    "review the security implications before merging",
    "the cache invalidation logic needs review",
    "we're rate-limited by the upstream API",
    "the migration script needs to handle null values",
    "ship behind a feature flag and gradually ramp",
    "the query is doing a full table scan",
    "increase the timeout for the upstream call",
    "merge the conflict and force-push the branch",
    "the canary has been stable for an hour",
    "the database backup completed successfully",
    "the new caching layer cut p99 latency by 40 percent",
    "we shipped two features and a bug fix this week",
    # Frontend
    "the React component is re-rendering on every keystroke",
    "use useMemo to cache the expensive computation",
    "the state update is happening before the effect runs",
    "wrap the handler in useCallback to prevent re-renders",
    "the bundle size grew by 200 kilobytes after adding lodash",
    "lazy load the dashboard route to defer the chart library",
    "the layout shift is being caused by the late-loading hero image",
    "set width and height on the image to reserve space",
    # Mobile
    "the iOS build is failing because of a Swift 6 sendable warning",
    "the Android keyboard is covering the input field",
    "the App Store reviewer rejected us for missing the privacy manifest",
    "the push notification token needs to refresh on app launch",
    "test on a real device because the simulator's haptics are different",
    # Data / ML
    "the model is overfitting after epoch 3",
    "drop the duplicate rows before joining the tables",
    "the embedding dimension needs to match the model's hidden size",
    "use a cosine schedule with warmup for the learning rate",
    "the validation loss diverged at iteration 200",
    "the dataset has class imbalance, try stratified sampling",
    "log the gradient norm to catch exploding gradients early",
    # DevOps
    "the pod is OOMKilled because the memory limit is too low",
    "the certificate expires next week, rotate it now",
    "the load balancer is routing traffic to the old version",
    "scale the deployment to 5 replicas for the launch",
    "the secrets manager rotation broke the integration",
]

CLEAN_EN_WORK = [
    # FYI / heads-up
    "FYI the API rate limit was raised to 10k per hour",
    "heads up the meeting moved to Thursday at 2",
    "just letting you know I pushed the fix to main",
    "wanted to flag that the dashboard is loading slowly",
    "thought you should know the new hire starts Monday",
    "FYI we're seeing a small spike in 5xx errors",
    "heads up I'm taking Friday off",
    "wanted to mention the contract was signed yesterday",
    "FYI the office network is being upgraded this weekend",
    # Status / completion
    "I drafted the postmortem in the shared doc",
    "I reproduced the race condition locally",
    "I filed the bug as issue 1247",
    "I added the integration test you suggested",
    "I merged the PR and deleted the branch",
    "I finished the design review notes",
    "the rollout hit 100% with no incidents",
    "the security audit came back clean",
    # Asks / requests
    "can you take a look at the open PR when you get a sec",
    "did the security review come back yet",
    "what's the ETA on the new endpoint",
    "do you have bandwidth to review my doc this afternoon",
    "could you ping me when the deploy finishes",
    "would you mind reviewing this before standup",
    "can you share the link to the dashboard",
    # Casual office
    "the all-hands is at 4 PM in the main room",
    "office is closed Monday for the holiday",
    "the team lunch is on Thursday",
    "let's sync after lunch to align on priorities",
    "I'll be in late tomorrow due to a doctor's appointment",
    "I'm working from home today",
    "let me know if you need help with the migration",
    "send me the dashboard link when you have a sec",
    # Multi-clause but clean
    "the proposal looks good but needs more numbers",
    "the new endpoint is faster but uses more memory",
    "I disagree with the current approach but let's discuss",
    "we should document this decision in the wiki",
    "we shipped the feature behind a flag and gradually ramped traffic",
    "the meeting was productive and we agreed on the next steps",
]

CLEAN_EN_PERSONAL = [
    "I'll pick up groceries on the way home",
    "remind me to call the dentist tomorrow",
    "the kids have soccer practice at 4",
    "we're out of coffee, can you grab some",
    "my flight gets in at 9:30 PM",
    "the restaurant takes reservations starting at 6",
    "I left my keys on the kitchen counter",
    "the package should arrive by Friday",
    "tell mom happy birthday for me",
    "I'm running late, traffic is brutal",
    "the recipe says 350 degrees for 25 minutes",
    "the gym closes at 10 tonight",
    "we need to renew the car registration this month",
    "the mortgage payment auto-drafts on the first",
    "I'll be at the coffee shop on the corner",
]

CLEAN_EN_QUESTIONS = [
    "can you fix the bug where it drops the last word of long inputs",
    "should we ship this Friday or wait until Monday",
    "do you know if the API is paginated by default",
    "what time does the meeting start",
    "did anyone respond to the security email",
    "where did we land on the pricing decision",
    "how long does the migration usually take",
    "is the staging environment up",
    "are we still on for tomorrow",
    "who owns the deployment runbook",
    "why is the test suite suddenly so slow",
    "when do we need to ship by",
]

CLEAN_EN_LONG = [
    "the issue is that we're double-counting events from the new instrumentation because the old client is still emitting them and the dedup logic only kicks in after ingestion",
    "I think we should split this into two PRs because the type changes are noisy and would make the actual logic diff hard to review carefully",
    "the user reported that when they paste a long passage the last few words sometimes get cut off and we tracked it down to a buffer flush issue in the paste service",
    "I spent the morning bisecting the regression and it turns out it was the dependency bump from last Tuesday that introduced the new behavior in the cache layer",
    "the design review went well but we need to circle back on the empty state because the team felt the current copy was confusing for first-time users",
    "I'm going to skip the standup tomorrow because I have an early flight and I'll catch up on the threads in the afternoon when I land",
    "the postmortem covers the timeline of the incident but we still need to add the action items and assign owners before we can close it out",
    "the new hire is going to shadow the on-call rotation for the first two weeks before taking primary on a low-traffic shift",
]

CLEAN_ZH = [
    "我觉得我们可以重构一下 polish 模块",
    "我们应该用 Claude Code 来打开一个 PR",
    "明天下午三点开会讨论基准测试结果",
    "数据库迁移脚本需要处理空值情况",
    "把超时时间调长一点试试",
    "新的端点速度更快但内存占用更多",
    "构建在 CI 上又失败了",
    "上线时间推迟到下周一",
    "我已经把 bug 提交到 issue 系统",
    "明天早上九点开个会简单同步一下",
    "代码审查发现了一个潜在的内存泄漏",
    "测试在本地能通过但在 CI 上失败",
    "新功能上线后用户反馈很好",
    "周五下午开个回顾会议",
    "请帮我审查一下这个 PR",
    "服务器响应时间最近变长了",
    "建议把日志级别调整到 INFO",
    "缓存命中率今天达到了 95%",
    "我把文档更新了，请大家看一下",
    "下周二有一个产品评审会",
]

CLEAN_JA = [
    "ポリッシュモジュールをリファクタしようと思います",
    "明日の三時から会議があります",
    "テストがCIで失敗しています",
    "依存関係を最新版に更新してください",
    "新しいエンドポイントにユニットテストを追加します",
    "デプロイが終わって、すべて緑です",
    "リリースノートをドラフトしました",
    "本番環境のデータベースをバックアップしました",
    "明日のミーティングは延期になりました",
    "コードレビューをお願いします",
    "新しい機能のドキュメントを書きました",
    "パフォーマンステストの結果が出ました",
    "サーバーのレスポンスタイムが改善されました",
    "週末はリリース作業があります",
    "新しいメンバーが月曜日に入社します",
    "セキュリティ監査の結果を共有します",
    "本日のスタンドアップは中止です",
    "プルリクエストをマージしました",
    "ログを調べたところ、原因が分かりました",
    "明日は在宅勤務にします",
]

CLEAN_ES = [
    "Deberíamos usar el modelo más pequeño",
    "La compilación está fallando en CI",
    "Hay que documentar esta decisión en el wiki",
    "El despliegue está completo y todo está verde",
    "Voy a llegar tarde mañana",
    "El nuevo endpoint es más rápido pero usa más memoria",
    "Pásame el enlace del dashboard cuando puedas",
    "La reunión semanal es a las tres de la tarde",
    "Acabo de mergear el PR a main",
    "Hay un bug en producción que necesita atención urgente",
    "La migración de la base de datos terminó sin errores",
    "Vamos a revisar el plan en la siguiente reunión",
    "Necesitamos actualizar la documentación del API",
    "El equipo de diseño quiere otra iteración",
    "El customer success reportó un problema",
    "La nueva versión sale el viernes",
    "Tenemos que arreglar este test antes de mergear",
    "El servidor de staging está caído otra vez",
    "Voy a trabajar desde casa hoy",
    "El informe trimestral está casi listo",
]

CLEAN_FR = [
    "On devrait utiliser le modèle plus petit",
    "Le déploiement est terminé et tout est vert",
    "Réunion à quinze heures demain pour discuter des résultats",
    "Le test est instable sur CI mais passe localement",
    "Je vais arriver en retard demain matin",
    "Pousse la correction sur main quand tu as un moment",
    "La revue de code a soulevé quelques points",
    "Il faut mettre à jour la documentation après ce changement",
    "Le nouveau endpoint répond plus vite",
    "On a un bug en production qu'il faut corriger",
    "La migration de la base s'est bien passée",
    "Je vais travailler depuis la maison aujourd'hui",
    "Le rapport mensuel est presque terminé",
    "L'équipe design veut une autre itération",
    "Le serveur de staging est encore en panne",
    "Je serai absent vendredi pour un rendez-vous",
    "On va sortir une nouvelle version la semaine prochaine",
    "Il faut planifier la rétrospective de sprint",
    "L'audit de sécurité a révélé un problème",
    "Le client a accepté la proposition",
]

CLEAN_DE = [
    "Wir sollten das kleinere Modell nehmen",
    "Der Build schlägt im CI wieder fehl",
    "Das Deployment ist fertig und alles ist grün",
    "Bitte den Code Review machen bevor du mergest",
    "Lass uns nach dem Mittag synchronisieren",
    "Ich komme morgen später, ich habe einen Arzttermin",
    "Die Migration ist erfolgreich abgeschlossen",
    "Der Pull Request ist bereit für Review",
    "Wir haben einen Bug in Production gefunden",
    "Die neue Version kommt nächsten Freitag raus",
    "Das Meeting wurde auf Donnerstag verschoben",
    "Der Server reagiert langsamer als sonst",
    "Bitte aktualisiere die Dokumentation",
    "Das Customer Feedback war sehr positiv",
    "Wir müssen die Tests stabilisieren",
    "Ich arbeite heute von zu Hause aus",
    "Der Sprint Review ist am Freitag",
    "Die Performance hat sich deutlich verbessert",
    "Wir sollten ein Postmortem schreiben",
    "Der neue Mitarbeiter fängt am Montag an",
]

# =========================================================================
# SELF-CORRECTION SEEDS — the high-value transformation
# =========================================================================

SELF_CORRECTIONS_EN = [
    "I think we should I mean let's just merge the PR",
    "let me think actually no scratch that let's go with option B",
    "I think we should I mean actually let's use the smaller model",
    "we could refactor it actually no let's rewrite it from scratch",
    "I was thinking Monday actually let's ship it Friday",
    "we could use Ollama wait it doesn't support our model let's use mlx-lm",
    "the meeting is at 3 no wait it's at 4 PM tomorrow",
    "ideally we'd ship Friday but realistically Monday is more honest",
    "I think we should actually no what I mean is let's just merge the PR",
    "we should run the migration actually let's scrap it for now",
    "the meeting was Wednesday hmm actually it's Tuesday",
    "let's roll forward I mean actually let's revert the change",
    "we'll call it polish_two actually polish_v3",
    "around fifteen percent actually closer to twenty",
    "we use MySQL well actually we switched to Postgres last quarter",
    "send it to John no wait send it to Sarah she's the new owner",
    "the cost is around 50 dollars no actually it's closer to 75",
    "schedule it for next Tuesday no wait Thursday is better",
    "let's call the function getUserData actually fetchUserProfile is clearer",
    "the meeting room is 401 actually I think it's 405",
    "use the staging environment no use the dev one for this test",
    "the deadline is end of quarter actually end of month",
    "I'll review it tomorrow no I can do it tonight",
    "we need three replicas actually two should be enough",
    "the API returns JSON wait no it's XML for this endpoint",
    "let's add a button no actually a dropdown makes more sense",
    "ship it as a hotfix actually let's batch it with the next release",
    "the user is in the EU no I think they're in the US East",
    "I want to add tests first no let's get the feature working then add tests",
    "the budget is 10k actually we got bumped up to 15k",
    "the call is at 2 PM Pacific no it's 2 PM Eastern",
    "use bcrypt actually argon2 is more modern",
    "we should fix it now actually it can wait until Monday",
    "the customer wants feature X actually they're asking for feature Y",
    "the script needs to run weekly actually daily would be better",
]

SELF_CORRECTIONS_ZH = [
    "我觉得吧 不对 我们应该重写整个模块",
    "用 MySQL 不对其实我们已经换成 Postgres 了",
    "时间是下午两点 不对应该是三点",
    "派 John 来做 等等让 Sarah 来 她更熟悉这块",
    "周一发布 不对周三更合适",
    "我以为是 100 块 其实是 150",
    "用大模型 不对小的应该够用",
    "明天开会 不对后天",
    "在生产环境跑 不对 先在 staging 试试",
]

SELF_CORRECTIONS_JA = [
    "月曜日にリリース いや水曜日のほうが良い",
    "MySQL を使う 違う Postgres に切り替えた",
    "三時に会議 いや四時だった",
    "大きいモデルを使う いや小さいので十分",
    "今すぐ修正 いや月曜日まで待てる",
    "Sarah に頼む いや John のほうが詳しい",
]

SELF_CORRECTIONS_ES = [
    "deberíamos usar el modelo grande no espera mejor el más pequeño",
    "lanzar el lunes no mejor el viernes",
    "usar MySQL espera no ya cambiamos a Postgres",
    "la reunión es a las tres no espera a las cuatro",
    "enviarlo a John no mejor a Sarah",
    "arreglarlo ahora no puede esperar hasta el lunes",
    "tres réplicas no espera con dos basta",
]

SELF_CORRECTIONS_FR = [
    "on devrait utiliser Ollama non attends mlx-lm directement",
    "on lance lundi non vendredi serait mieux",
    "MySQL attends non on est passé à Postgres",
    "la réunion à trois heures non quatre heures",
    "envoyer à Jean non plutôt à Sarah",
    "corriger maintenant non ça peut attendre lundi",
]

SELF_CORRECTIONS_DE = [
    "wir nehmen MySQL warte nein wir haben auf Postgres umgestellt",
    "Release am Montag nein Donnerstag wäre besser",
    "drei Replicas nein zwei reichen",
    "schick es an Hans nein lieber an Sarah",
    "jetzt fixen nein kann bis Montag warten",
]

# =========================================================================
# STUTTER PATTERNS — rare in real Whisper but should be cleaned
# =========================================================================

STUTTERS_EN = [
    "the the the build is failing on CI",
    "I I I think we should ship this",
    "let's let's just merge the PR",
    "we we should add an index here",
    "the the dashboard is loading slowly",
    "could could you take a look at this",
    "I I just wanted to let you know",
    "the the the deploy is happening now",
    "let me let me check the logs first",
    "we we need to roll this back",
    "the customer the customer is asking for an update",
    "I I think the the migration is done",
    "send me send me the link please",
    "we should we should ship this on Friday",
    "I'll I'll take a look this afternoon",
]

STUTTERS_MULTI = [
    ("zh", "我我觉得这个 bug 比较严重"),
    ("ja", "明日明日のミーティングをキャンセルします"),
    ("es", "el el deploy salió bien"),
    ("fr", "le le build est cassé"),
    ("de", "der der Build ist gerade fertig"),
]

# =========================================================================
# EDGE CASES — questions, lists, code-mixed, numbers, very-short
# =========================================================================

EDGE_VERY_SHORT = [
    "yes",
    "ok",
    "thanks",
    "got it",
    "sounds good",
    "will do",
    "no",
    "maybe",
    "Hello world.",
    "Send.",
]

EDGE_LISTS = [
    "we need to do three things first deploy second monitor third document",
    "the priorities are performance reliability and developer experience",
    "we tested chrome firefox safari and edge",
    "the regions are us-east us-west eu-west and ap-southeast",
    "the candidates are Alice Bob and Carol",
]

EDGE_NUMBERS_DATES = [
    "the meeting is on May 15th at 3 PM Pacific",
    "the budget is 50,000 dollars for the quarter",
    "the SLO is 99.9 percent uptime measured monthly",
    "the cache TTL is 300 seconds",
    "the deploy hit 100 percent of users at 2:47 PM",
    "the conversion rate dropped from 12.3 to 11.8 percent overnight",
    "version 2.3.1 ships on July 22nd",
]

EDGE_CODE_MIXED = [
    "the function should return Promise<User[]> not just User[]",
    "use git rebase -i HEAD~3 to squash the last three commits",
    "the env var is OPENQUACK_DEBUG=1",
    "in the JSX use className not class",
    "the regex is /^\\d{3}-\\d{4}$/ for the phone number",
    "import React, { useState } from 'react'",
    "set CORS to Access-Control-Allow-Origin: *",
]

EDGE_TECHNICAL_TERMS = [
    "the Kubernetes pod is in CrashLoopBackOff",
    "the Postgres query plan shows a sequential scan",
    "WebSocket reconnection is failing with code 1006",
    "the JVM is throwing OutOfMemoryError on the GC overhead",
    "the SSL handshake fails with TLSV1_ALERT_PROTOCOL_VERSION",
    "use exponential backoff with jitter for the retry policy",
    "the Redis cluster is in MOVED state during failover",
]

EDGE_INFORMAL = [
    "wow that's actually really cool",
    "haha yeah that's exactly what I was thinking",
    "lol the build broke again",
    "ugh I forgot to push my changes",
    "ok cool let's do that",
    "yeah no that's fine",
    "oh nice that's a great idea",
]

# =========================================================================
# Build the corpus
# =========================================================================

raws = []

# Clean passthrough — distributed across domains
for s in CLEAN_EN_DEV:        raws.append({"raw": s, "language": "en", "category": "dev",        "expected": "passthrough"})
for s in CLEAN_EN_WORK:       raws.append({"raw": s, "language": "en", "category": "work",       "expected": "passthrough"})
for s in CLEAN_EN_PERSONAL:   raws.append({"raw": s, "language": "en", "category": "personal",   "expected": "passthrough"})
for s in CLEAN_EN_QUESTIONS:  raws.append({"raw": s, "language": "en", "category": "question",   "expected": "passthrough"})
for s in CLEAN_EN_LONG:       raws.append({"raw": s, "language": "en", "category": "long",       "expected": "passthrough"})
for s in CLEAN_ZH:            raws.append({"raw": s, "language": "zh", "category": "general",    "expected": "passthrough"})
for s in CLEAN_JA:            raws.append({"raw": s, "language": "ja", "category": "general",    "expected": "passthrough"})
for s in CLEAN_ES:            raws.append({"raw": s, "language": "es", "category": "general",    "expected": "passthrough"})
for s in CLEAN_FR:            raws.append({"raw": s, "language": "fr", "category": "general",    "expected": "passthrough"})
for s in CLEAN_DE:            raws.append({"raw": s, "language": "de", "category": "general",    "expected": "passthrough"})

# Self-corrections
for s in SELF_CORRECTIONS_EN: raws.append({"raw": s, "language": "en", "category": "self_corr",  "expected": "self_correction"})
for s in SELF_CORRECTIONS_ZH: raws.append({"raw": s, "language": "zh", "category": "self_corr",  "expected": "self_correction"})
for s in SELF_CORRECTIONS_JA: raws.append({"raw": s, "language": "ja", "category": "self_corr",  "expected": "self_correction"})
for s in SELF_CORRECTIONS_ES: raws.append({"raw": s, "language": "es", "category": "self_corr",  "expected": "self_correction"})
for s in SELF_CORRECTIONS_FR: raws.append({"raw": s, "language": "fr", "category": "self_corr",  "expected": "self_correction"})
for s in SELF_CORRECTIONS_DE: raws.append({"raw": s, "language": "de", "category": "self_corr",  "expected": "self_correction"})

# Stutters
for s in STUTTERS_EN:         raws.append({"raw": s, "language": "en", "category": "stutter",    "expected": "stutter"})
for lang, s in STUTTERS_MULTI: raws.append({"raw": s, "language": lang, "category": "stutter",   "expected": "stutter"})

# Edge cases
for s in EDGE_VERY_SHORT:     raws.append({"raw": s, "language": "en", "category": "very_short", "expected": "passthrough"})
for s in EDGE_LISTS:          raws.append({"raw": s, "language": "en", "category": "list",       "expected": "passthrough"})
for s in EDGE_NUMBERS_DATES:  raws.append({"raw": s, "language": "en", "category": "numbers",    "expected": "passthrough"})
for s in EDGE_CODE_MIXED:     raws.append({"raw": s, "language": "en", "category": "code",       "expected": "passthrough"})
for s in EDGE_TECHNICAL_TERMS:raws.append({"raw": s, "language": "en", "category": "technical",  "expected": "passthrough"})
for s in EDGE_INFORMAL:       raws.append({"raw": s, "language": "en", "category": "informal",   "expected": "passthrough"})

# Dedup
seen = set()
out = []
for r in raws:
    if r["raw"] in seen: continue
    seen.add(r["raw"])
    out.append(r)

random.shuffle(out)

os.makedirs("/tmp/distill", exist_ok=True)
with open("/tmp/distill/v3b_raws.jsonl", "w") as f:
    for r in out:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

from collections import Counter
print(f"Generated {len(out)} raw inputs")
print()
print(f"By expected behaviour: {dict(Counter(r['expected'] for r in out))}")
print(f"By language:           {dict(Counter(r['language'] for r in out))}")
print(f"By category:           {dict(Counter(r['category'] for r in out))}")
