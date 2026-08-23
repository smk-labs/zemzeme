---
name: transcribe
description: Turn an audio or video file into text with the local Zemzeme backend. Use for voice notes (Telegram ogg/opus, WhatsApp amr), meeting and call recordings, interviews, lectures, podcasts, and video files, in Persian or English. Triggers on "این وویس رو متن کن", "این فایل صوتی رو پیاده کن", "متن این جلسه رو بده", "transcribe this audio", "transcribe this voice note", "what does this recording say", "give me the text of this meeting", "make subtitles for this file", or any request to read, summarize, or search a file you can only hear.
---

# Transcribe a file to text

One command turns a sound or video file into a `.txt` file next to it. Then you read that file.

## The command

```
/Applications/Zemzeme.app/Contents/MacOS/zemzeme --transcribe <file> [--lang fa-IR] [--jobs 2] [--out DIR] [--srt]
```

- **stdout** prints one line per finished file: the full path of the `.txt` it wrote. That is the only thing on stdout.
- **stderr** prints progress. Ignore it unless the run fails.
- **Exit 0** means every file finished. Non zero means at least one did not.

So the flow is always: run the command, take the path from stdout, then `Read` that path to get the text. Do not try to read the transcript from the command output itself.

If the binary is not at that path, the app is not installed. Tell the user, do not hunt for another copy.

## Language

- Default is `fa-IR`. Leave it alone for Persian audio.
- Pass `--lang en-US` when you know the audio is English. Guessing wrong costs a whole run, so if you are unsure, ask the user in one short question.
- The text comes back raw, exactly as the speech engine returned it. No cleanup pass runs on it in either language: Persian keeps whatever spacing and punctuation the engine produced, English comes back lowercase and unpunctuated. Tidy it yourself when you present it.

## Keep `--jobs` at 2

The default is 2. You may raise it to 4 for a long file when the user is waiting. **Never go above 4.**

This is not a performance guess, it is a shared resource limit. The backend talks to the same free Google endpoint that live dictation uses, on the same key and IP. A heavy run makes that endpoint go quiet for a while, and the user's live dictation loses its share too. The run itself does not fail, it just slows down and the user's typing breaks. Do not "optimize" this number.

## Formats

Works with no conversion: ogg, opus, oga, amr, mp3, m4a, aac, 3gp, wav, aiff, caf, flac, au, mp4, mov.

**mkv and webm do not work.** macOS has no demuxer for them. Refuse before running anything and give the user the one line fix:

```bash
afconvert -f m4af -d aac input.mkv output.m4a
```

If `afconvert` also refuses (it usually will, for the same reason), the user needs ffmpeg for that one step. Do not run the transcribe command on mkv or webm to "check", it will just fail.

## When it fails with a permission error

If stderr shows `Operation not permitted` or error code `-54`, nothing is wrong with the file or the backend. The process simply cannot read that folder. This happens with `~/Downloads`, `~/Desktop`, `~/Documents` and iCloud folders under macOS privacy protection.

Ask the user to copy the file somewhere readable, for example `/tmp` or inside the project, then run again on the new path. **Do not retry the same path**, and do not retry with different flags. It will fail the same way every time.

## Long files: run in the background

Speed is roughly 2.6 times realtime at `--jobs 2`. A 90 minute recording therefore takes something like half an hour. (Measured reference: 97 minutes of audio finished in 17 minutes at `--jobs 3`.)

Anything over about 10 minutes of audio: start the command as a **background** bash call, tell the user how long you expect it to take, and get on with other work. Poll for the result instead of blocking the turn. Short voice notes, under a couple of minutes, are fine to run inline.

## Subtitles

Add `--srt` only when the user actually asks for subtitles. It writes a second file and prints its path on stdout too.

Warn them once: the timings are estimates. The endpoint returns no timestamps, so they are calculated from how many bytes were sent. Good enough to follow along, not good enough to ship as real subtitles.

## Other flags

- `--out DIR` puts the output files in `DIR` instead of next to the input. Useful when the input folder is read only.
- Several files can be passed in one command. Each finished file prints its own path on stdout.

## Worked example

```bash
/Applications/Zemzeme.app/Contents/MacOS/zemzeme --transcribe /tmp/voice.ogg --lang fa-IR --jobs 2
```

stdout:

```
/tmp/voice.txt
```

Then `Read` `/tmp/voice.txt` and answer the user's actual question, whether that is the full text, a summary, or one detail from it.
