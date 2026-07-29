# زمزمه (Zemzeme)

*[نسخه‌ی کامل فارسی](README.md)*

A menu-bar dictation app for macOS, tuned for Persian. Double-tap the right Command key, talk, and text appears at your cursor in any app — even full-screen. Esc ends the session: whatever's left gets inserted and the full text lands in your clipboard.

This is a short summary in English. The full documentation, including every design decision and the "why" behind it, lives in Persian in [README.md](README.md) — this project is Persian-first, and every architecture note is written for Persian speech recognition.

## What it does

- **Live dictation** over Google's speech recognition (the same public endpoint Chromium's dictation uses), with a floating panel that shows the last few words while committed text is typed straight into whatever app has focus.
- **Four modes**: live insert, collect-in-panel, cursor-side (like macOS's own dictation), and voice notes.
- **Local Persian cleanup** (`polish.py`): half-spaces, Persian digits, punctuation, spelling — fully offline, no network call.
- **Optional AI passes** (final pass, notes, prompt enhancement) that call Google's Gemini API with your own free key, for when the raw transcript needs a real listen instead of a live guess.
- **File transcription**: drop in an audio/video file (voice memos, Telegram/WhatsApp voice notes, podcasts), get a text file back — no paid key, no ffmpeg.
- Works over Windows App remote desktop too, with true Persian keyboard input (not clipboard paste).

## Getting a free API key

The optional AI passes (final pass, notes, prompt enhancement) need a free key from [Google AI Studio](https://aistudio.google.com/apikey). Once you have one, open the Zemzeme menu and click **"کلید Gemini…"** ("Gemini key…") — paste it there. It's saved straight to your Mac's Keychain; nothing goes into the repo, a `.env` file, or any log. No terminal needed. (There's still a terminal path for scripting/headless use — see README.md.)

## Privacy, in short

- Live dictation and file transcription always go through Google's servers, key or no key — that's how the speech recognition works.
- The local Persian cleanup pass never leaves your machine.
- The optional AI passes only run with your own key, and are off by default.
- On Google's **free tier** (no billing enabled), Google may use what you send to improve its models — read [Gemini's API terms](https://ai.google.dev/gemini-api/terms) before you paste a key.
- Session audio recording is off by default and stays on your disk if you turn it on.

Full detail: the "داده و حریم خصوصی" section near the top of [README.md](README.md).

## Build

```bash
bash app/build.sh
```

No Xcode project, no dependencies beyond the system frameworks — one `clang` invocation, then codesign, install to `/Applications/Zemzeme.app`, relaunch. See README.md for what it needs and why it's Objective-C, not Swift, on this machine.

## Vibe-coded, contributions welcome

This project was built through direct conversation with an AI coding agent (Claude Code), not typed line by line. The comments and the README were written the same way, and they keep the "why," not just the "what." That also means there may be bugs nobody's hit yet. Found one? Open an issue or send a PR — both are welcome.

## License

MIT — see [LICENSE](LICENSE).
