# زمزمه (Zemzeme)

*[نسخه‌ی کامل فارسی](README.md)*

A menu-bar dictation app for macOS, tuned for Persian. Double-tap the right Command
key, talk, and **tap right Command once when you are done**: the text arrives all at
once.

**Free, and no account.** No sign-up, no login, no key, no minute cap. Dictation and
file transcription work from the moment you install. One optional feature (an AI
cleanup pass) needs a key and is off by default. In exchange your audio goes to
Google's servers: read [Privacy](#privacy) before you use it.

This is a short summary in English. The full documentation, including every design
decision and the "why" behind it, lives in Persian in [README.md](README.md): this
project is Persian-first, and every architecture note is written for Persian speech
recognition.

## What it does

- **Dictation into any app**, even full-screen, through a floating panel that never
  steals focus. Nothing is shown while you speak, on purpose; the text lands in one
  piece when you finish.
- **Two destinations**: collect in the panel (editable before you insert), or
  cursor-side, where a dot replaces the panel and the text is inserted once at the
  end. Right Command + E switches.
- **Live language switching**: right Command + L flips Persian and English **mid
  sentence**, as many times as you like. What you already said is transcribed in the
  old language, what follows in the new one, and both are joined in order.
- **File transcription**: audio and video files (voice notes, meeting recordings,
  podcasts) to text, no key and no ffmpeg. Also usable from Claude Code through the
  plugin in `tools/claude-plugin/`.
- **Optional AI cleanup** that sends **text only**, never audio, using your own free
  Gemini key. Off by default.
- Works over Windows App remote desktop, where it always uses the clipboard route.

## Install

Needs macOS 13 or newer and the Xcode Command Line Tools
(`xcode-select --install` if you do not have them).

```bash
curl -fsSL https://raw.githubusercontent.com/smk-labs/zemzeme/main/install.sh | bash
```

That fetches the source, compiles it with a single `clang` call and installs to
`/Applications`. It takes seconds and pulls in no dependencies.

**Why build instead of downloading an app?** The app is signed with a self-made
certificate, not an Apple one, so any downloaded `.app` gets quarantined and macOS
calls it "damaged". Building locally avoids that entirely, and the certificate
becomes this Mac's own, so the Accessibility and microphone permissions survive
every later build instead of being asked again.

If you would rather have a file, `Zemzeme-2.0.0.dmg` is on the
[Releases](https://github.com/smk-labs/zemzeme/releases) page. Drag the app to
Applications, then clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Zemzeme.app
```

## Permissions

Two, both required, both explained by the app on first launch.

| Permission | Asked | Without it |
|---|---|---|
| **Accessibility** | first launch | no text at the cursor, and the double-tap hotkey is not heard |
| **Microphone** | first dictation | no audio at all |

Accessibility lives in System Settings › Privacy & Security › Accessibility. The app
watches for it, so the hotkey comes up the moment you tick the box, with no restart.

## First minute

1. Double-tap the **right** Command key (left Command does nothing).
2. Talk. Nothing appears while you speak. The green dot means it is listening.
3. Tap right Command once when you are done. The text arrives in the panel.
4. Esc inserts that text at your cursor and closes the session.

Every button on the panel's toolbar has its shortcut letter printed under it, and
**right Command + H** opens the full card.

## Getting the optional API key

The AI cleanup pass needs a free key from
[Google AI Studio](https://aistudio.google.com/apikey). Open the Zemzeme menu, click
**"کلید Gemini (اختیاری)…"**, and paste it. It goes straight to your Mac's Keychain:
nothing lands in the repo, a `.env` file, or any log. No terminal needed.

## Privacy

- Dictation and file transcription always go through Google's servers, key or no
  key: that is how the speech recognition works. The engine is a public,
  undocumented Google endpoint, using Chromium's public key, not yours.
- It is free and uncapped, but there is **no service agreement behind it**. Assume
  Google may use what you send to improve its models. Do not dictate confidential
  material into any cloud tool, this one included.
- Audio never reaches an AI model, in any mode. The optional pass takes **text**
  only.
- The optional AI pass runs only with your own key and is off by default. On
  Gemini's **free tier**, Google's own terms say it may use what you send for
  training; read the [Gemini API terms](https://ai.google.dev/gemini-api/terms)
  before you paste a key.
- Session audio recording is off by default. When on, it stays on your disk for
  seven days and is then swept automatically.
- Everything is local, in `~/Library/Application Support/Zemzeme`. There is no
  Zemzeme server at all.

## Build

```bash
bash app/build.sh
```

No Xcode project, no dependencies beyond the system frameworks: one `clang`
invocation, then codesign, install to `/Applications/Zemzeme.app`, relaunch. The
Vazirmatn font ships in the repo (`app/fonts/`, SIL OFL) so the build is identical on
any Mac. See README.md for why it is Objective-C and not Swift on this machine.

## Vibe-coded, contributions welcome

This project was built through direct conversation with an AI coding agent (Claude
Code), not typed line by line. The comments and the README were written the same way,
and they keep the "why," not just the "what." That also means there may be bugs
nobody's hit yet. Found one? Open an issue or send a PR, both are welcome.

## License

MIT, see [LICENSE](LICENSE). The Vazirmatn font has its own:
[app/fonts/OFL.txt](app/fonts/OFL.txt).
