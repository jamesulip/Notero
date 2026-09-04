# Security

## How to report a vulnerability

Report a security problem privately. Do not open a public issue.

Use the **Report a vulnerability** button on the Security tab of this
repository. That button opens a private advisory that only the maintainers can
read.

In the report, give the action that you did, the result that you saw, and the
smallest input or sequence that reproduces the result. There is no bounty
programme.

## The security position of this project

The design goal is that recordings and transcripts stay on your machine. Most
of the usual attack surface therefore does not exist:

- **There are no accounts, API keys, tokens or secrets.** No part of this
  repository authenticates against any service. There is no credential to lose.
- **The native app sends no telemetry, no crash reports and no analytics.** It
  makes two kinds of network call. It downloads the model weights from Hugging
  Face at the first start. It asks GitHub which releases exist, if you ask it
  to, or once a day if you turn on automatic checks in Settings ▸ Updates. The
  automatic check is off until you turn it on. Neither call carries an
  identifier, and neither sends audio or text.
- **All inference is local.** Whisper, voice activity detection and speaker
  identification all run on your Mac through CoreML.

## Where the risk is

**Media files from an unknown source.** The app decodes each audio file and
video file that you drop on it with AVFoundation. The command-line tool does
the same for `--audio`. A malicious media file is the most probable attack on
the native app. Treat an imported file as you treat a file that you open in any
other media application.

**The model weights.** At the first start, the app downloads approximately
1.6 GB of CoreML weights from Hugging Face over HTTPS. Those weights are
third-party code that runs on your Mac. If you point the app or
`transcribe --models DIR` at a different weights directory, you also trust the
person who made that directory.

**The updater.** The app can replace its own bundle. Each release is signed
with an Ed25519 key, and the public half is compiled into the app. The app
refuses a download when the SHA-256 digest disagrees with the signature file,
when the signature is not from that key, or when the bundle in the download is
not Notero at the version that the release gives. The app holds no token,
thus a person who takes control of the release page still cannot make a
download that the app accepts. The private key is the one secret in this
project. `docs/RELEASE.md` tells you where it is and how to protect it.

The app installs into its own position on disk. It does not ask for an
administrator password, and it does not write outside its own bundle and
`~/Library/Application Support/Transcriber/Updates/`.

**The legacy Python server** in `server/` is the exposed component, and it has
no authentication of any kind. The native app replaces it, and the repository
keeps it only as prior work. If you run the server:

- Bind it to the loopback interface with `--host 127.0.0.1`. To reach it from
  another device, use an SSH tunnel, or put TLS and a password in front of it.
  `docs/DEPLOY.md` gives a procedure for each case.
- **Do not put the server on the public internet.** A person who can reach the
  port can open sessions, read the stored transcripts and delete the archived
  audio.
- `server/main.py` validates each session id against `SESSION_ID_RE`, because a
  session id becomes a filename, an SQLite key and an HTTP header value. **Do
  not make that pattern less strict.** The id `../../x` would then write and
  delete files outside the archive directory.

## Your own data

The recordings, the transcripts and the SwiftData store are in
`~/Library/Application Support/Transcriber/`. The app adds no encryption of its
own, thus FileVault is the only protection. The Python server writes the same
kind of data to `data/`, which is not in git.

An export contains the full transcript, word for word. Meeting audio is usually
the most sensitive data that this project touches. Read an export before you
send it to another person.

## Supported versions

This project has one maintainer. Fixes go to the default branch. There are no
backports to an older tag.
