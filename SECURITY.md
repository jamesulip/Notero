# Security

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue.

Use GitHub's **Report a vulnerability** button under this repository's Security
tab, which opens a private advisory visible only to the maintainers.

Please include what you were doing, what happened, and the smallest input or
sequence that reproduces it. There is no bounty programme.

## What this project's security posture actually is

The design goal is that recordings and transcripts never leave the machine, so
most of the usual attack surface does not exist here:

- **No accounts, no API keys, no tokens, no secrets.** Nothing in this
  repository authenticates against anything. There is no credential to leak.
- **No telemetry, no crash reporting, no analytics, no network calls** from the
  native app other than downloading model weights from Hugging Face on first
  launch.
- **All inference is local.** Whisper, voice activity detection and speaker
  diarization all run on-device via CoreML.

## Where the real risk is

**Untrusted media files.** The app decodes whatever audio or video you drop on
it through AVFoundation, and the CLI does the same for `--audio`. A malicious
media file is the most plausible attack on the native app. Treat imported files
the way you would treat opening them in any other media application.

**Model weights.** First launch downloads roughly 1.6 GB of CoreML weights from
Hugging Face over HTTPS. Those weights are third-party code that runs on your
machine. Pointing the app or `transcribe --models DIR` at a weights directory
means trusting whatever produced it.

**The legacy Python server** under `server/` is the exposed component, and it
has no authentication of any kind. It is superseded by the native app and kept
only as prior work. If you run it:

- Bind it to loopback (`--host 127.0.0.1`) and put TLS and access control in
  front of it. `docs/DEPLOY.md` describes doing this with Tailscale.
- Do **not** put it on the public internet. Anyone who can reach the port can
  open sessions, read stored transcripts and delete archived audio.
- Session ids are validated against `SESSION_ID_RE` in `server/main.py` because
  they become filenames, SQLite keys and HTTP header values. Do not loosen that
  pattern; `../../x` would otherwise write and delete files outside the archive.

## Your own data

Recordings, transcripts and the SwiftData store live under
`~/Library/Application Support/Transcriber/` and are not encrypted beyond
whatever FileVault gives you. The Python server writes the same kind of data
under `data/`, which is gitignored.

Exports contain full verbatim transcripts. Meeting audio is usually the most
sensitive thing this project touches — check what you are attaching before you
share an export.

## Supported versions

This is a single-maintainer project. Fixes land on the default branch; there are
no backports to older tags.
