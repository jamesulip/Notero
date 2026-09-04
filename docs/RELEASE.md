# How to release the app

The app can update itself. This document tells you how to publish a release
that the app accepts, and what to do before the first one.

Read [The signing key](#the-signing-key) before you publish. A release that is
not signed correctly is a release that no installed copy can accept.

## What the updater does

1. The app asks GitHub which releases exist.
2. The app compares the newest release to its own version.
3. The app downloads the `.zip` and the `.sig` from that release.
4. The app makes a SHA-256 digest of the `.zip`. The digest must agree with the
   digest in the `.sig`. If it does not, the download is damaged.
5. The app checks the Ed25519 signature in the `.sig` against the public key in
   `Sources/TranscriberCore/Update.swift`. If the signature is wrong, some
   person other than you made the `.zip`. The app stops.
6. The app opens the `.zip`. The bundle in it must have the same bundle
   identifier as the app, and the version that the release gives.
7. The app writes a script, starts it, and quits. The script waits for the app
   to stop. Then it moves the new bundle into position. Then it opens the app.

The app refuses to install at each of steps 4, 5 and 6. It tells the user which
step refused. It does not change the installed copy.

The code is in `Sources/TranscriberCore/Update.swift` (the decisions) and
`Sources/Transcriber/Updater.swift` (the network, the files and the swap).

## Before the first release

### The signing key

Make the key one time:

```bash
cd app
./scripts/release.sh --init-key
```

This writes `~/.config/transcriber/release-key`. The mode of the file is 0600.
It prints one line of Swift. Put that line in
`Sources/TranscriberCore/Update.swift`, in `UpdateSource.publicKey`. Then
commit that change.

**Make a backup of the key file.** Each installed copy of the app holds the
public half. If you lose the private half, no installed copy can accept another
release. Each user must then install the app again by hand.

**Do not put the key file in the repository.** `.gitignore` refuses a file with
the name `release-key`, but keep the file outside the repository.

To use a key in a different position, set `TRANSCRIBER_RELEASE_KEY` to the path.

### A feed that the app can read

The app sends no token, and it never will. A token in a released binary is a
token that each user of that binary holds. Thus the list of releases must be
readable by any person.

**A private repository is not readable.** It answers 404, and the app says so.

Select one of these three:

1. **Make the repository public.** Nothing in the code changes.
2. **Publish from a second, public repository.** Change `owner` and
   `repository` in `UpdateSource`. The second repository holds the releases and
   no source.
3. **Put a JSON file on an HTTPS server of your own.** Give its address in
   `UpdateSource.feedOverride`. The file must have the shape that the GitHub
   endpoint returns. To make one, copy that reply.

## To publish a release

1. Write the changes in `CHANGELOG.md`, under a heading with the new version
   number. The release notes come from that section.
2. Put the new version number in `app/VERSION`. Use three numbers, for example
   `1.2.0`. Do not add a suffix: the app refuses a version such as `1.2.0-rc1`.
3. Commit all changes. The script refuses to release from a tree that has
   changes, because the build number comes from the number of commits.
4. Release:

   ```bash
   cd app
   ./scripts/release.sh --dry-run   # build, package and sign only
   ./scripts/release.sh             # the same, then tag and publish
   ```

The script does this:

- It builds the signing tool from `scripts/relkey.swift` and
  `Sources/TranscriberCore/Update.swift`. The two halves of the signature
  format are thus one piece of code.
- It stops if the public key in `Update.swift` is not the public half of the
  key on this machine.
- It builds `Transcriber.app` with `build-app.sh`.
- It makes `dist/Transcriber-<version>.zip` with `ditto`. Do not use `zip`. The
  executable bit and the code signature must stay correct.
- It signs the `.zip` and then verifies the signature.
- It makes the tag `v<version>`, pushes it, and makes the GitHub release with
  the `.zip` and the `.sig`.

Each installed copy sees the new release at its next check.

## Limits

**The app has no Developer ID certificate.** `build-app.sh` signs the bundle ad
hoc. Thus:

- macOS can ask for microphone access again after an update. The permission is
  connected to the signature, and the signature changes with each build.
- A user who downloads the `.zip` in a browser gets a bundle that Gatekeeper
  refuses. The updater does not have this problem, because the app downloads
  the file itself and macOS puts no quarantine attribute on it.

To remove both limits, sign with a Developer ID certificate and notarize the
`.zip`. Then add the `codesign` identity and `notarytool` to `build-app.sh`.

**The app cannot install into a folder that it cannot write.** The updater says
so and offers the releases page. Put the app in `/Applications` or in
`~/Applications`.

**The app does not install while a recording runs.** The button stays off until
the recording stops.
