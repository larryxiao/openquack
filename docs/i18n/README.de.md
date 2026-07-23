<p align="center">
  <img src="../images/banner.png" alt="OpenQuack — Sprich. Schick. Privat. Das Aufnahme-Overlay zeigt 'Listening' mit einer Live-Pegelanzeige; das Menüleisten-Popover zeigt 'Pasted at cursor' mit dem letzten Transkript und einer Settings / Quit-Fußzeile.">
</p>

<div align="center">

**OpenQuack** *Sprich. Schick. Privat.*

Sprachdiktat für macOS. Nichts verlässt dein Gerät — kein Audio, kein Text, nichts.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](../INSTALL.md)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)](../ROADMAP.md)

</div>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../../README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a> ·
  <strong>Deutsch</strong>
</p>

> 🌐 **Maschinell übersetzt.** Beiträge von Muttersprachler:innen sind willkommen — öffne einen PR oder schau in [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

---

> 📢 **Neu — [v2.0.0-alpha.9](https://github.com/larryxiao/openquack/releases/tag/v2.0.0-alpha.9):** rasend schnelles Diktat, auch bei langen Clips. Plus ein frischer neuer Look. Hoffentlich gefällt's dir!

## Was es ist

OpenQuack ist eine winzige Menüleisten-App für macOS. Drück einen Hotkey, sprich, drück nochmal — dein Transkript erscheint am Cursor. Wo du tippen kannst, kannst du reden.

Spracherkennung läuft auf deinem Mac. Keine Cloud, kein Account, keine Anmeldung, keine Telemetrie.

## Warum

**Lokal.** Alles läuft auf deinem Gerät — Aufnahme, Transkription, optionales Polieren. Nichts geht raus: kein Audio, kein Text, keine Telemetrie, keine Anmeldung. Vertrauliche Arbeit bleibt vertraulich, von der Bauart her. Und weil im Loop kein API-Aufruf ist, läuft es einfach weiter — offline, im Flugzeug, hinter einer Firmen-Firewall.

**Schnell.** Whisper auf Apple Silicon transkribiert in etwa einem Fünftel der Zeit, die du fürs Sprechen gebraucht hast. ~2,6 % Wortfehlerrate auf echter menschlicher Sprache auf einem Basis-M4 / 16 GB. In den meisten Fällen schneller als Tippen. Volle Bench-Matrix in [`docs/BENCHMARKS.md`](../BENCHMARKS.md).

**Offen.** MIT-lizenziert. Jede Zeile ist auditierbar; jede Änderung passiert öffentlich. Die Version, die in deiner Menüleiste läuft, ist die Version aus diesem Repo.

## Was du bekommst

- **Diktat per Tastendruck.** Such dir einen Hotkey aus (Standard ⌃⇧Space). Toggle oder Push-to-Talk.
- **Alles lokal.** Spracherkennung läuft auf deinem Mac. Kein Internet fürs Diktieren — funktioniert offline, im Flugzeug, im Tunnel, hinter einer Firmen-Firewall. Keine API-Keys, keine Rate-Limits, keine Service-Ausfälle. Gleiches Diktat, ob privat oder geschäftlich.
- **Mehrsprachig.** Whisper kann 99 Sprachen — Englisch, Chinesisch, Japanisch, Koreanisch, Spanisch, Französisch, Deutsch, Italienisch und Portugiesisch sind direkt in den Einstellungen; Auto-Erkennung ist standardmäßig an.
- **Auto-Einfügen am Cursor** in jeder App. (Fällt auf die Zwischenablage zurück, wenn du lieber selbst einfügst.)
- **Smarte Formatierung** — Großschreibung, Endzeichen, Aufräumen von „äh / ähm".
- **Eigenes Wörterbuch** — bring ihm die Eigennamen und Projektnamen bei, die du wirklich benutzt.
- **Auto-Stop bei Stille.** Wenn du fertig gesprochen hast, beendet OpenQuack von selbst.
- **Live-Mikrofonpegel** als Overlay, damit du siehst, dass es zuhört.
- **Schnelle Ersteinrichtung** — Berechtigungen, Hotkey, in einer Minute fertig.
- **Winzig.** Eine 8 MB große Menüleisten-App, plus das Sprachmodell beim ersten Start.
- **Open Source**, MIT.

## Datenschutz, auf einem Bildschirm

1. **Nichts verlässt dein Gerät — kein Audio, kein Text, nichts.** Aufnahme und Transkription sind komplett lokal. Immer.
2. **Keine Analytik, keine Telemetrie, keine Anmeldung.**

Der vollständige Datenschutz-Vertrag steht in [`docs/VISION.md`](../VISION.md#privacy-contract).

## Was als Nächstes kommt

Ein Blick auf das, was in der Pipeline ist. Beides baut auf der Diktat-Grundlage auf, die heute schon ausgeliefert wird.

**Kontextsensitive Transkription.** OpenQuack wird den Text rund um die Stelle lesen, an die du gerade einfügen willst — die Zeile über dem Cursor, die Funktion, in der du gerade bist, den Chat-Thread, auf den du antwortest — und das dem Sprachmodell als Kontext mitgeben. Fachbegriffe werden anhand dessen disambiguiert, was du wirklich tust („cloud code" wird im Terminal zu „Claude Code", und nicht andersherum). Weniger Bastelei am eigenen Wörterbuch.

**Denk-Modus.** Ein zweiter Durchgang nach der Transkription, durch ein kleines lokales LLM, der einen rohen gesprochenen Satz in einen geschriebenen verwandelt, bei dem du wirklich auf Senden drücken würdest. Füllwörter raus, Struktur gestrafft, richtige Großschreibung bei den Wörtern, die zählen. Standardmäßig aus, mit einem Toggle einschaltbar. Vollständig lokal — Ollama oder MLX-LM, deine Wahl.

Zeitplan und SPEC-Details in [`docs/ROADMAP.md`](../ROADMAP.md).

Die Ente hat größere Pläne. Wohin das geht: [`docs/VISION.md`](../VISION.md).

## Installation

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

Oder [DMG laden](https://github.com/larryxiao/openquack/releases) und in den Programme-Ordner ziehen. Erster Start: Rechtsklick → **Öffnen** → **Öffnen** (einmalige Gatekeeper-Umgehung).

Erlaube **Mikrofon**, wenn macOS fragt, und such dir einen Hotkey unter **Einstellungen → Kurzbefehl** aus (Standard ⌃⇧Space).

Lieber ein geführter Rundgang? Schau in [`docs/TUTORIAL.md`](../TUTORIAL.md) — fünf Minuten von der Installation bis zum ersten Diktat.

### Oder lass deinen KI-Agenten ran

Kopier das in Claude Code, Codex, opencode, Hermes oder ähnliche:

```text
Install OpenQuack on this Mac:

  brew tap larryxiao/openquack https://github.com/larryxiao/openquack
  brew install --cask openquack

(Or grab the DMG from https://github.com/larryxiao/openquack/releases
and drag it into /Applications; first open right-click → Open → Open.)

Then launch /Applications/OpenQuack.app, grant Microphone, and pick a
hotkey in Settings → Shortcut. Default ⌃⇧Space.
```

Mehr Optionen (Deinstallation, Build aus dem Quellcode, was beim ersten Start heruntergeladen wird): [`docs/INSTALL.md`](../INSTALL.md).

## Danksagung

OpenQuack steht auf den Schultern großzügiger Open-Source-Arbeit. Riesigen Dank an:

- [**OpenAI Whisper**](https://github.com/openai/whisper) — das Sprachmodell, das das alles erst möglich macht.
- [**WhisperKit**](https://github.com/argmaxinc/WhisperKit) von Argmax — Whisper, schnell und nativ auf Apple Silicon.
- [**KeyboardShortcuts**](https://github.com/sindresorhus/KeyboardShortcuts) von Sindre Sorhus — die Hotkey-Mechanik, die du jeden Tag drückst.
- [**voxt**](https://github.com/hehehai/voxt) — ein verwandtes Projekt, von dem wir technisch viel gelernt haben.
- [**Typeless**](https://www.typeless.com/) und [**Wispr Flow**](https://wisprflow.ai/) — die Closed-Source-Apps, die gezeigt haben, wie schön sich Voice-First-Eingabe anfühlen kann; wir zielen auf dasselbe Gefühl, lokal und offen.

Und an alle, die Issues schreiben, PRs öffnen und Freund:innen davon erzählen: Danke. Die Ente quakt wegen euch.

## Mitmachen

OpenQuack ist **AI-native Open Source** — jeder PR zitiert ein SPEC, atomare Aufgaben kommen aus der Roadmap, der Workflow ist freundlich zu Coding-Agenten in großem Maßstab (und zu Menschen auf demselben Weg).

Fang mit [`AGENTS.md`](../../AGENTS.md) an, schnapp dir eine 🔵-Aufgabe in [`docs/ROADMAP.md`](../ROADMAP.md), öffne einen Draft-PR.

Unter der Haube: [`TUTORIAL`](../TUTORIAL.md) · [`DEVELOPMENT`](../DEVELOPMENT.md) · [`ARCHITECTURE`](../ARCHITECTURE.md) · [`BENCHMARKS`](../BENCHMARKS.md) · [`DESIGN`](../DESIGN.md) · [`INSTALL`](../INSTALL.md) · [`BLOG`](../blog/README.md).

## Lizenz

MIT — siehe [LICENSE](../../LICENSE).

(Übersetzungs-Feedback gerne per PR oder über [GitHub Discussions](https://github.com/larryxiao/openquack/discussions).)
