# Windows port: plan, parked

Written 2026-07-24 from a full read of this repo. **No code has been written. This is a decision record, not a task list in progress.** Pick it up whenever; nothing here expires except the risk note at the bottom.

## What a port actually costs

Roughly 2,900 lines of C#, zero third-party packages, in five phases. Two of the three hard parts are already OS-independent and move over untouched: the Google full-duplex speech protocol and the Persian polish daemon. What genuinely has to be rebuilt is the thin macOS shell around them: hotkey, mic, text injection, floating panel.

## Read from the right tree

Port from `app/Sources-objc/` (~2,900 lines). **Do not port from `app/swift-port/`.** That tree is a same-day snapshot that was never updated and is missing, at minimum: the whole Persian polish pass, pause/resume, the mic-dead watchdog, the interim salvage-merge, the `hasResults` empty-frame guard, and the 600 ms paste delay that a real RDP test forced. Porting from it would silently ship a worse product than the Mac one.

## Language: C# on .NET 8, no NuGet

Everything needed is in the standard library: streaming HTTP, clipboard, process spawn, P/Invoke to Win32. WPF is used for one thing only, the floating bar, because it renders Persian and right-to-left text correctly out of the box. Keyboard hook, mic capture and text injection all go straight to Win32.

Publish self-contained: no installer, no admin rights. That matters on a corporate laptop.

Rejected: C++ (streaming HTTP is fragile and slow to build against), Rust (an HTTP client drags in dozens of transitive crates, which is the opposite of what this repo stands for).

## Mac to Windows, piece by piece

| Piece | Today on macOS | On Windows |
|---|---|---|
| Hotkey | Karabiner rule + right-Cmd double tap, shelling out to `zemzeme://toggle` | In-app global hook (`WH_KEYBOARD_LL`), right-Ctrl double tap. The external dependency disappears. |
| Mic | `AVAudioEngine` + `AVAudioConverter` | `waveIn` opened directly at 16 kHz mono s16le; Windows resamples for us |
| Speech to text | Two parallel HTTP streams + hand-rolled protobuf walker | Same wire contract, one-to-one translation onto `HttpClient` |
| Text injection | Synthetic Unicode keystrokes, or clipboard + Cmd+V | `SendInput` with Unicode, or clipboard + Ctrl+V. Register the `ExcludeClipboardContentFromMonitorProcessing` format so dictated text does not pile up in Win+V history (same intent as the `org.nspasteboard.TransientType` marker). |
| Floating bar | `NSPanel`, non-activating, all Spaces, over fullscreen | WPF topmost window with `WS_EX_NOACTIVATE` and `WS_EX_TOOLWINDOW`. Never takes focus. Virtual desktops need explicit handling; exclusive-fullscreen games are out of scope. |
| Persian polish | Python daemon on 127.0.0.1:17636 | Same daemon, logic untouched. Only the venv setup and process spawn become Windows-shaped. |
| Settings | `NSUserDefaults` | `settings.json` in `%APPDATA%\zemzeme` |
| Font | Copied from the build machine's own font folder | Bundle Vazirmatn in the repo. The Mac build should adopt this too; today it silently falls back to the system font on any machine that lacks the font. |

New code lives in `app/win/`. The macOS tree is not touched.

## Phases

**Phase 0, prove the wire (~350 lines).** Protobuf frame parser, the up/down stream pair, and a `--selftest` that replays a recorded raw audio file. No UI, no mic. This goes first because the single biggest risk in the whole project is the corporate network, and half an hour of work settles it. If phase 0 fails, nothing else is worth writing.

**Phase 1, usable every day (~1,200 lines).** Mic capture, the Google engine with all its watchdogs and the five-minute session rotation, the hotkey, direct typing, a minimal bar, and Esc to finish with the transcript copied to the clipboard.

**Phase 2, parity (~700 lines).** Paste mode with automatic RDP detection, the injection queue that resumes when you switch back to the target app, pause and retry, the full tray menu, collect mode.

**Phase 3, Persian polish (~200 lines of glue).** Run `polish.py` on this machine's Python 3.12, spawn the daemon from the app, run the existing golden tests.

**Phase 4, fallback engine (~400 lines).** The browser relay. On Windows, Edge is always installed and could stand in for Chrome, but its engine is Azure, so Persian quality needs its own test before trusting it. Plus the stress test.

## Risks

- **Corporate network is the real one.** A proxy or filter may block Google's `speech-api` endpoint outright. That is why phase 0 exists and why it comes before everything else.
- **Elevated windows.** Windows refuses synthetic input from a normal-privilege app into an Administrator window. The existing queue model, with its "N queued" chip, already covers this gracefully.
- **Dictating into an RDP session.** Use paste mode with the 600 ms delay. That number came from a real failed test on the Mac at 350 ms; carry it over rather than re-learning it.
- **Exclusive-fullscreen games** will not show the bar. Accepted, out of use case.

## Defaults chosen here

Language and UI: C# .NET 8 with WPF, no external packages. Default hotkey: double-tap right Ctrl, changeable in settings. Code location: `app/win/`. Data and logs: `%APPDATA%\zemzeme`.

## Inherited risk worth knowing

The speech engine depends on an unofficial, publicly shared Google API key with no service agreement behind it. It has been stress-tested, not blessed. Any port inherits that exposure and therefore also inherits the need for a fallback engine, unless a different speech provider is chosen at that point.
