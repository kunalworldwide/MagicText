# MagicText

**Select text anywhere on macOS → press a hotkey → it's refined in place.**

OpenWispr/FluidVoice-style polish, for text instead of voice. A native macOS menu bar app: no Electron, no telemetry, your keys never leave your machine.

## What it does

1. Configure any **OpenAI-compatible** gateway (OpenAI, OpenRouter, Ollama, LM Studio, llama.cpp server…)
2. Select text in any app, press **⌃⌥⌘R** (re-recordable)
3. MagicText fixes spelling, punctuation, and grammar — and replaces the selection in place

Tones (Formal / Casual / Emoji) are selectable in Settings.

## Install

Download the latest `MagicText-<version>-macOS.dmg` from [Releases](../../releases), drag to Applications, open it.

First launch requires **one** permission: **Accessibility** (System Settings → Privacy & Security → Accessibility) — it's how MagicText reads and replaces the selected text. No other permissions, no network calls except to the gateway you configure.

## Build from source

```bash
git clone https://github.com/kunalworldwide/MagicText.git
cd MagicText
swift test
bash scripts/build-app.sh          # produces build/MagicText.app + DMG
```

## Architecture

- **`MagicTextCore`** — testable logic: gateway client (OpenAI-compatible), URL normalization, Keychain store, prompts, hotkey model. Zero third-party dependencies.
- **`MagicText`** — the app: Carbon global hotkey, AX-based text capture/replace with a clipboard-simulation fallback, menu bar presence, floating status pill.

API keys are stored in the **macOS Keychain**, never in plaintext preferences.

## Roadmap

- [x] v0.1 — refine selection in place, any OpenAI-compatible gateway
- [ ] v0.2 — per-app tone rules
- [ ] v0.3 — refinement history
- [ ] v0.4 — signed + notarized builds, Homebrew cask

## License

MIT
