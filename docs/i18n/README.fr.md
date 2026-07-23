<p align="center">
  <img src="../images/banner.png" alt="OpenQuack — Parle. Envoie. En privé. L'overlay d'enregistrement affiche 'Listening' avec un vumètre en direct ; le popover de la barre de menus affiche 'Pasted at cursor' avec la dernière transcription et un pied de page Settings / Quit.">
</p>

<div align="center">

**OpenQuack** *Parle. Envoie. En privé.*

Dictée vocale pour macOS. Rien ne quitte ton appareil — ni audio, ni texte, rien.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](../INSTALL.md)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)](../ROADMAP.md)

</div>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../../README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <strong>Français</strong> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a>
</p>

> 🌐 **Traduction automatique.** Les contributions de locuteurs natifs sont les bienvenues — ouvre une PR ou consulte [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

---

> 📢 **Du nouveau — [v2.0.0-alpha.9](https://github.com/larryxiao/openquack/releases/tag/v2.0.0-alpha.9) :** dictée ultra-rapide, même sur les longs extraits. Et un nouveau look. On espère qu'il te plaira !

## C'est quoi

OpenQuack est une petite app de barre de menus pour macOS. Tu appuies sur un raccourci, tu parles, tu réappuies — ta transcription apparaît au curseur. Partout où tu peux taper, tu peux parler.

La reconnaissance vocale tourne sur ton Mac. Pas de cloud, pas de compte, pas d'inscription, pas de télémétrie.

## Pourquoi

**Local.** Tout tourne sur ton appareil — enregistrement, transcription, polissage optionnel. Rien ne sort : pas d'audio, pas de texte, pas de télémétrie, pas d'inscription. Le travail confidentiel reste confidentiel, par construction. Et comme il n'y a pas d'appel API dans la boucle, ça continue à fonctionner — hors ligne, dans un avion, derrière un pare-feu d'entreprise.

**Rapide.** Whisper sur Apple Silicon transcrit en environ un cinquième du temps que tu as passé à parler. Taux d'erreur de mots d'environ ~2,6 % sur de la vraie parole humaine sur un M4 / 16 Go de base. Plus rapide que la frappe dans la plupart des cas. Matrice complète dans [`docs/BENCHMARKS.md`](../BENCHMARKS.md).

**Ouvert.** Sous licence MIT. Chaque ligne est auditable ; chaque changement se fait en public. La version qui tourne dans ta barre de menus est la version de ce dépôt.

## Ce que tu obtiens

- **Dictée en une touche.** Choisis un raccourci (par défaut ⌃⇧Space). Bascule ou push-to-talk.
- **Tout local.** La reconnaissance vocale tourne sur ton Mac. Pas besoin d'Internet pour dicter — fonctionne hors ligne, dans un avion, dans un tunnel, derrière un pare-feu d'entreprise. Pas de clé API, pas de limite de taux, pas de panne de service. Même dictée en perso ou en pro.
- **Multilingue.** Whisper gère 99 langues — anglais, chinois, japonais, coréen, espagnol, français, allemand, italien et portugais sont directement dans les Réglages ; détection automatique activée par défaut.
- **Collage automatique au curseur** dans n'importe quelle app. (Repli sur le presse-papiers si tu préfères coller toi-même.)
- **Mise en forme intelligente** — majuscules, ponctuation finale, nettoyage des « euh / hum ».
- **Dictionnaire personnalisé** — apprends-lui les noms propres et noms de projet que tu utilises vraiment.
- **Arrêt automatique en cas de silence.** Quand tu finis de parler, OpenQuack se débrouille pour finir tout seul.
- **Vumètre micro en direct** pour voir qu'il écoute.
- **Configuration rapide au premier lancement** — permissions, raccourci, c'est plié en une minute.
- **Minuscule.** Une app de barre de menus de 8 Mo, plus le modèle vocal au premier lancement.
- **Open source**, MIT.

## Vie privée, sur un seul écran

1. **Rien ne quitte ton appareil — ni audio, ni texte, rien.** Enregistrement et transcription sont entièrement locaux. Toujours.
2. **Pas d'analytique, pas de télémétrie, pas d'inscription.**

Le contrat de vie privée complet est dans [`docs/VISION.md`](../VISION.md#privacy-contract).

## La suite

Aperçu de ce qui est en file d'attente. Les deux s'appuient sur la base de dictée disponible dès aujourd'hui.

**Transcription contextuelle.** OpenQuack lira le texte autour de l'endroit où tu vas coller — la ligne au-dessus du curseur, la fonction dans laquelle tu te trouves, le fil de discussion auquel tu réponds — et le donnera comme contexte au modèle vocal. Les termes du domaine sont désambiguïsés par ce que tu fais réellement (« cloud code » devient « Claude Code » quand tu es dans un terminal, et pas l'inverse). Moins de bricolage de dictionnaire personnalisé.

**Mode réflexion.** Une seconde passe après la transcription, à travers un petit LLM local, qui transforme une phrase parlée brute en phrase écrite que tu appuierais vraiment sur envoyer. Tics nettoyés, structure resserrée, bonne capitalisation sur les mots qui comptent. Désactivé par défaut, activable d'un seul clic. Entièrement local — Ollama ou MLX-LM, à ton choix.

Calendrier et détails SPEC dans [`docs/ROADMAP.md`](../ROADMAP.md).

Le canard a des plans plus ambitieux. Vers où ça va : [`docs/VISION.md`](../VISION.md).

## Installation

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

Ou [télécharge le DMG](https://github.com/larryxiao/openquack/releases) et glisse-le dans Applications. Premier lancement : clic droit → **Ouvrir** → **Ouvrir** (contournement unique de Gatekeeper).

Accorde **Microphone** quand macOS le demande, choisis un raccourci dans **Réglages → Raccourci** (par défaut ⌃⇧Space).

Tu veux un guide pas à pas ? Voir [`docs/TUTORIAL.md`](../TUTORIAL.md) — cinq minutes de l'installation à la première dictée.

### Ou demande à ton agent IA

Colle ceci dans Claude Code, Codex, opencode, Hermes ou similaire :

```text
Install OpenQuack on this Mac:

  brew tap larryxiao/openquack https://github.com/larryxiao/openquack
  brew install --cask openquack

(Or grab the DMG from https://github.com/larryxiao/openquack/releases
and drag it into /Applications; first open right-click → Open → Open.)

Then launch /Applications/OpenQuack.app, grant Microphone, and pick a
hotkey in Settings → Shortcut. Default ⌃⇧Space.
```

Plus d'options (désinstallation, build depuis les sources, ce qui est téléchargé au premier lancement) : [`docs/INSTALL.md`](../INSTALL.md).

## Remerciements

OpenQuack se tient sur les épaules d'un travail open source généreux. Un immense merci à :

- [**OpenAI Whisper**](https://github.com/openai/whisper) — le modèle vocal qui rend tout ça possible.
- [**WhisperKit**](https://github.com/argmaxinc/WhisperKit) par Argmax — Whisper, rapide et natif sur Apple Silicon.
- [**KeyboardShortcuts**](https://github.com/sindresorhus/KeyboardShortcuts) par Sindre Sorhus — la mécanique de raccourci que tu enfonces tous les jours.
- [**voxt**](https://github.com/hehehai/voxt) — un projet frère dont on a beaucoup appris côté technique.
- [**Typeless**](https://www.typeless.com/) et [**Wispr Flow**](https://wisprflow.ai/) — les apps closed source qui ont prouvé à quel point la saisie vocale peut être agréable ; on vise la même sensation, en local et en ouvert.

Et à toutes les personnes qui ouvrent des issues, des PR, qui en parlent à leurs amis : merci. Le canard cancane grâce à vous.

## Contribuer

OpenQuack est un **open source AI-native** — chaque PR cite un SPEC, les tâches atomiques viennent de la roadmap, le workflow est pensé pour les agents de code à grande échelle (et les humains sur le même chemin).

Commence par [`AGENTS.md`](../../AGENTS.md), choisis une tâche 🔵 dans [`docs/ROADMAP.md`](../ROADMAP.md), ouvre une PR en draft.

Sous le capot : [`TUTORIAL`](../TUTORIAL.md) · [`DEVELOPMENT`](../DEVELOPMENT.md) · [`ARCHITECTURE`](../ARCHITECTURE.md) · [`BENCHMARKS`](../BENCHMARKS.md) · [`DESIGN`](../DESIGN.md) · [`INSTALL`](../INSTALL.md) · [`BLOG`](../blog/README.md).

## Licence

MIT — voir [LICENSE](../../LICENSE).

(Retours sur la traduction bienvenus via PR ou [GitHub Discussions](https://github.com/larryxiao/openquack/discussions).)
