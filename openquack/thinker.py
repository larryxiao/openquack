"""LLM-powered text organizer using Ollama (local models, no cloud).

Optimized for speed: short inputs get a minimal prompt and tight token cap.
Multilingual: works with any language, responds in the same language as input.
"""

import re
import requests


# Compact, multilingual, action-oriented system prompt.
# Every extra token here adds latency, so keep it tight.
_SYSTEM = """\
You reorganize raw voice transcriptions into clean, structured text.

You MUST:
- Respond in the SAME language as the input
- Add correct punctuation (。，for Chinese; periods, commas for English; etc.)
- Remove filler words, verbal tics, false starts, and repetitions
- Remove garbled or nonsensical text (transcription errors/artifacts)
- Organize multiple ideas into bullet points (use • or -)
- Keep it concise — shorter than the input
- Preserve all technical terms, proper nouns, and names exactly as spoken
- Output ONLY the reorganized text — no commentary, labels, or markdown fences"""


def _estimate_words(text: str) -> int:
    """Estimate word count for any language. CJK characters each count as a word."""
    space_words = len(text.split())
    cjk_chars = len(re.findall(r'[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff\uac00-\ud7af]', text))
    return space_words + cjk_chars


def _quick_clean(text: str) -> str:
    """Fast regex cleanup for very short inputs — skips LLM entirely."""
    fillers = r'\b(um|uh|uh+|ah|like|you know|basically|I mean|so yeah|right|actually|literally)\b'
    text = re.sub(fillers, '', text, flags=re.IGNORECASE)
    text = re.sub(r'\s{2,}', ' ', text)
    text = re.sub(r'\s([,.])', r'\1', text)
    text = text.strip()
    if text and text[0].islower():
        text = text[0].upper() + text[1:]
    if text and text[-1] not in '.!?。！？':
        text += '.'
    return text


class Thinker:
    def __init__(self, ollama_url: str = "http://localhost:11434", model: str = "gemma4:e2b"):
        self.url = ollama_url.rstrip("/")
        self.model = model

    def is_available(self) -> bool:
        """Check if Ollama is running and the model is available."""
        try:
            r = requests.get(f"{self.url}/api/tags", timeout=3)
            if r.status_code != 200:
                return False
            names = []
            for m in r.json().get("models", []):
                name = m["name"]
                names.append(name)                  # "gemma4:e2b"
                names.append(name.split(":")[0])     # "gemma4"
            return self.model in names
        except Exception:
            return False

    def warm(self):
        """Send an empty keep-alive to pre-load the model into GPU memory."""
        try:
            requests.post(
                f"{self.url}/api/chat",
                json={"model": self.model, "messages": [], "keep_alive": -1},
                timeout=5,
            )
        except Exception:
            pass

    def polish(self, raw_text: str, context: dict) -> str:
        """Polish raw transcription. Short inputs use fast regex, longer ones use the LLM."""
        word_count = _estimate_words(raw_text)

        # Fast path: very short and already clean-looking → regex only
        if word_count < 8:
            return _quick_clean(raw_text)

        # Build concise user message with context hint
        app = context.get("app", "")
        ctx_tag = f" [{app}]" if app and app != "Unknown" else ""
        user_msg = f"[App:{ctx_tag}]\n{raw_text}" if ctx_tag else raw_text

        # Scale token budget to input — don't let the model ramble
        num_predict = min(max(word_count * 2, 80), 1024)

        try:
            resp = requests.post(
                f"{self.url}/api/chat",
                json={
                    "model": self.model,
                    "messages": [
                        {"role": "system", "content": _SYSTEM},
                        {"role": "user", "content": user_msg},
                    ],
                    "stream": False,
                    "think": False,  # disable thinking — text cleanup doesn't need CoT
                    "keep_alive": -1,
                    "options": {
                        "temperature": 0.3 if word_count < 50 else 0.5,
                        "num_predict": num_predict,
                    },
                },
                timeout=90,
            )
            resp.raise_for_status()
            content = resp.json().get("message", {}).get("content", "")
            return content.strip() if content.strip() else raw_text
        except Exception:
            return _quick_clean(raw_text)
