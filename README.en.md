# زمزمه (Zemzeme)

*[نسخه‌ی کامل فارسی](README.md)*

![The Zemzeme panel holding a finished dictation](docs/img/panel-review.png)

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
- **Two destinations**: collect in the panel, where one click on the text focuses it for
  editing before you insert (the panel never takes focus just by appearing), or
  cursor-side, where a dot replaces the panel and the text is inserted once at the
  end. Right Command + E switches.
- **Live language switching**: right Command + L flips Persian and English **mid
  sentence**, as many times as you like. What you already said is transcribed in the
  old language, what follows in the new one, and both are joined in order.
- **File transcription**: audio and video files (voice notes, meeting recordings,
  podcasts) to text, no key and no ffmpeg. Also usable from Claude Code through the
  plugin in `tools/claude-plugin/`.
- **A history of every delivered transcript**, written the instant the text is
  handed over, so neither the clipboard nor the insertion has to have worked for the
  text to survive. Right Command + T opens the last 20, each with a one-click insert
  and copy. The store is an append-only JSONL file you can read with `tail`.
- **Nothing you said is dropped when the network is.** A piece that comes back with
  no text is a failure, never an answer, so its place in the text is marked
  `⟨جامانده⟩` and you are told the moment it happens. Two failures in a row stop the
  sending (not the recording). The next Esc re-sends only the missing pieces, each
  landing back in its own slot; nothing incomplete is ever typed at your cursor
  unless you ask for it with the insert button.
- **Optional AI cleanup** that sends **text only**, never audio, using your own free
  Gemini key. Off by default.
- **An optional signature line** appended to every piece of text that leaves the app.
  Right Command + G toggles it, the line itself is yours to edit, and it is never
  stored anywhere. Off by default.
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

If you would rather have a file, `Zemzeme-2.4.0.dmg` is on the
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

## Shortcuts

All of them are on the **right** Command key. The card at right Command + H shows this
same table with keycaps, and tells you the state of each toggle right now.

| Key | What it does |
|---|---|
| ⌘ twice | start and end dictation |
| ⌘ once | you are done talking: the text arrives |
| Esc | end dictation and insert the text |
| ⌘ + Space | pause and resume |
| ⌘ + C | copy the text so far |
| ⌘ + I | insert the text at your cursor |
| ⌘ + D | throw away everything so far: text, audio, timer. From zero |
| ⌘ + L | switch language, mid sentence |
| ⌘ + E | switch between "collect in the panel" and "cursor-side" |
| ⌘ + S | high microphone sensitivity, for whispering and quiet rooms |
| ⌘ + F | the file transcription panel |
| ⌘ + T | history: the last 20 transcripts, with insert and copy |
| ⌘ + H | the shortcut card |
| ⌘ + B | bilingual listening |
| ⌘ + P | raw preview |
| ⌘ + A | AI text cleanup |
| ⌘ + G | signature: one short line at the end of every text |

Apart from `F`, `T`, `H`, `B`, `P`, `A` and `G`, the letters only work during a
dictation. You can also drag the panel from any empty part of it.

## The signature line

One short line, separated by a blank line, appended to every piece of text that leaves
Zemzeme: copy, insert, the Esc handover, the history window, and the file-transcription
copy. **Right Command + G** toggles it. Off by default.

The shipped default is:

```
(speech-to-text, mentally fix typos)
```

That default exists because the main use is dictating AI prompts: the reader should
know an odd spelling or a swapped word is a speech-to-text artifact, not what you
meant.

**The line is yours, though.** The menu row **"خطِ امضا…"** opens a sheet where you can
put anything: your name, a source note, a disclaimer. The same sheet has a **restore
default** button. Leave the line empty and nothing is appended, even with the toggle
on.

The signature is **never stored**: not in the panel editor, not in the history, not in
the session's text file. It is added at the moment text leaves. So turning the toggle
off also changes what old history entries hand out, and editing text in the panel never
collides with it.

## Getting the optional API key

Zemzeme works with no key at all: dictation and file transcription run from the moment
you install. A key buys one thing, the AI cleanup pass (right Command + A), and it is
off by default.

The key is free and needs no credit card. Five steps:

1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey).
2. Sign in with your Google account.
3. Click **Create API key**.
4. Copy the key. It starts with `AIza`.
5. On your Mac, open the Zemzeme menu, click **"کلید Gemini (اختیاری)…"**, paste, save.

No terminal needed. The key goes straight to your Mac's Keychain (service
`zemzeme-gemini`): nothing lands in the repo, a `.env` file, or any log.

**The key is tested when you save it**, with a deliberately tiny request to the same
model the pass itself uses. A key Google does not recognise is not saved at all, and
the sheet says why: a saved-but-wrong key means a toggle that looks on and does
nothing. You can ask again any time with `zemzeme --checkkey`.

If the AI Studio page will not open for you, or will not let you create a key, that is
a Google regional restriction, not a Zemzeme fault. Dictation and file transcription
work fully without it.

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
- Transcript history is on by default and kept for 60 days in `history.jsonl`, next
  to everything else on your own disk. Change it with
  `defaults write io.seyed.zemzeme historyKeepDays 30`; `0` means never sweep. The
  same daily sweep also trims old lines out of `app.log`.
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
