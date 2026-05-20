<p align="center">
  <img src="../images/banner.png" alt="OpenQuack — Habla. Envía. En privado. El overlay de grabación muestra 'Listening' con un medidor de nivel en vivo; el popover de la barra de menús muestra 'Pasted at cursor' con la última transcripción y un pie con Settings / Quit.">
</p>

<div align="center">

**OpenQuack** *Habla. Envía. En privado.*

Dictado por voz para macOS. Nada sale de tu dispositivo — ni audio, ni texto, nada.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](../INSTALL.md)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)](../ROADMAP.md)

</div>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <strong>Español</strong> ·
  <a href="README.de.md">Deutsch</a>
</p>

> 🌐 **Traducido por máquina.** Damos la bienvenida a contribuciones de hablantes nativos — abre una PR o consulta [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

---

> 📢 **Novedades — [v2.0.0-alpha.9](https://github.com/larryxiao/openquack/releases/tag/v2.0.0-alpha.9):** dictado a toda velocidad, incluso en clips largos. Y un look renovado. ¡Esperamos que te guste!

## Qué es

OpenQuack es una pequeña app de barra de menús para macOS. Pulsa un atajo, habla, púlsalo de nuevo — la transcripción aparece en el cursor. Donde puedas escribir, puedes hablar.

El reconocimiento de voz ocurre en tu Mac. Sin nube, sin cuenta, sin registro, sin telemetría.

## Por qué

**Local.** Todo corre en tu dispositivo — grabación, transcripción, pulido opcional. Nada sale: ni audio, ni texto, ni telemetría, ni registro. El trabajo confidencial se queda confidencial, por diseño. Y como no hay llamadas a API en el camino, simplemente sigue funcionando — sin conexión, en un avión, detrás del firewall corporativo.

**Rápido.** Whisper sobre Apple Silicon transcribe en aproximadamente un quinto del tiempo que tardaste en hablar. Tasa de error de palabras de ~2,6 % sobre habla humana real en un M4 / 16 GB de base. Más rápido que escribir en la mayoría de los casos. Matriz completa en [`docs/BENCHMARKS.md`](../BENCHMARKS.md).

**Abierto.** Licencia MIT. Cada línea es auditable; cada cambio ocurre en público. La versión que corre en tu barra de menús es la versión de este repo.

## Lo que recibes

- **Dictado con una sola tecla.** Elige un atajo (por defecto ⌃⇧Space). Modo conmutar o pulsar para hablar.
- **Todo local.** El reconocimiento de voz corre en tu Mac. No necesitas Internet para dictar — funciona sin conexión, en un avión, en un túnel, detrás del firewall corporativo. Sin claves de API, sin límites de uso, sin caídas de servicio. El mismo dictado en lo personal y en lo profesional.
- **Multilingüe.** Whisper maneja 99 idiomas — inglés, chino, japonés, coreano, español, francés, alemán, italiano y portugués están directamente en Ajustes; detección automática activada por defecto.
- **Pegado automático en el cursor** en cualquier app. (Cae al portapapeles si prefieres pegar tú mismo.)
- **Formato inteligente** — mayúsculas, puntuación final, limpieza de muletillas tipo «eh / em».
- **Diccionario personalizado** — enséñale los nombres propios y de proyecto que realmente usas.
- **Parada automática tras silencio.** Cuando terminas de hablar, OpenQuack cierra solo.
- **Medidor de micro en vivo** para que veas que está escuchando.
- **Configuración rápida en el primer arranque** — permisos, atajo, listo en un minuto.
- **Diminuto.** Una app de barra de menús de 8 MB, más el modelo de voz en el primer arranque.
- **Código abierto**, MIT.

## Privacidad, en una pantalla

1. **Nada sale de tu dispositivo — ni audio, ni texto, nada.** Grabación y transcripción son completamente locales. Siempre.
2. **Sin analítica, sin telemetría, sin registro.**

El contrato de privacidad completo está en [`docs/VISION.md`](../VISION.md#privacy-contract).

## Lo que viene

Vista previa de lo que está en cola. Ambas cosas se apoyan en la base de dictado que ya está disponible hoy.

**Transcripción con contexto.** OpenQuack leerá el texto que rodea el sitio donde vas a pegar — la línea encima del cursor, la función en la que estás dentro, el hilo de chat al que respondes — y se lo dará como contexto al modelo de voz. Los términos del dominio se desambiguan por lo que estás haciendo realmente (cuando estás en un terminal, «cloud code» se convierte en «Claude Code», y no al revés). Menos jugueteo con el diccionario personalizado.

**Modo pensante.** Una segunda pasada después de la transcripción, a través de un pequeño LLM local, que convierte una frase hablada cruda en una frase escrita que tú realmente pulsarías «enviar». Muletillas recortadas, estructura ajustada, mayúsculas correctas en las palabras que importan. Desactivado por defecto, activable con un toque. Totalmente local — Ollama o MLX-LM, tú eliges.

Calendario y detalles de SPEC en [`docs/ROADMAP.md`](../ROADMAP.md).

El pato tiene planes más grandes. Hacia dónde va esto: [`docs/VISION.md`](../VISION.md).

## Instalación

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

O [descarga el DMG](https://github.com/larryxiao/openquack/releases) y arrástralo a Aplicaciones. Primer arranque: clic derecho → **Abrir** → **Abrir** (saltar Gatekeeper, una sola vez).

Da permiso de **Micrófono** cuando macOS lo pida, elige un atajo en **Ajustes → Atajo** (por defecto ⌃⇧Space).

¿Quieres un recorrido guiado? Ve [`docs/TUTORIAL.md`](../TUTORIAL.md) — cinco minutos de la instalación al primer dictado.

### O díselo a tu agente de IA

Pega esto en Claude Code, Codex, opencode, Hermes o similar:

```text
Install OpenQuack on this Mac:

  brew tap larryxiao/openquack https://github.com/larryxiao/openquack
  brew install --cask openquack

(Or grab the DMG from https://github.com/larryxiao/openquack/releases
and drag it into /Applications; first open right-click → Open → Open.)

Then launch /Applications/OpenQuack.app, grant Microphone, and pick a
hotkey in Settings → Shortcut. Default ⌃⇧Space.
```

Más opciones (desinstalación, build desde fuente, qué se descarga en el primer arranque): [`docs/INSTALL.md`](../INSTALL.md).

## Agradecimientos

OpenQuack se apoya en los hombros de trabajo open source generoso. Muchísimas gracias a:

- [**OpenAI Whisper**](https://github.com/openai/whisper) — el modelo de voz que hace posible todo esto.
- [**WhisperKit**](https://github.com/argmaxinc/WhisperKit) de Argmax — Whisper, rápido y nativo sobre Apple Silicon.
- [**KeyboardShortcuts**](https://github.com/sindresorhus/KeyboardShortcuts) de Sindre Sorhus — la maquinaria de atajos que pulsas cada día.
- [**voxt**](https://github.com/hehehai/voxt) — un proyecto hermano del que hemos aprendido mucho en lo técnico.
- [**Typeless**](https://www.typeless.com/) y [**Wispr Flow**](https://wisprflow.ai/) — las apps de código cerrado que demostraron lo agradable que puede sentirse la entrada por voz; apuntamos a la misma sensación, en local y en abierto.

Y a quienes abren issues, mandan PRs y se lo cuentan a sus amigos: gracias. El pato grazna gracias a vosotros.

## Contribuir

OpenQuack es **open source AI-native** — cada PR cita un SPEC, las tareas atómicas vienen del roadmap, el flujo es amigable para agentes de código a escala (y humanos en el mismo camino).

Empieza por [`AGENTS.md`](../../AGENTS.md), elige una tarea 🔵 en [`docs/ROADMAP.md`](../ROADMAP.md), abre una PR en borrador.

Bajo el capó: [`TUTORIAL`](../TUTORIAL.md) · [`DEVELOPMENT`](../DEVELOPMENT.md) · [`ARCHITECTURE`](../ARCHITECTURE.md) · [`BENCHMARKS`](../BENCHMARKS.md) · [`DESIGN`](../DESIGN.md) · [`INSTALL`](../INSTALL.md) · [`BLOG`](../blog/README.md).

## Licencia

MIT — ver [LICENSE](../../LICENSE).

(Comentarios sobre la traducción bienvenidos vía PR o [GitHub Discussions](https://github.com/larryxiao/openquack/discussions).)
