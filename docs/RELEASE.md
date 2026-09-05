# How to release the app

**The app does not update itself.** It downloads no code, checks no signature
and replaces no bundle. A release is a zip on the GitHub releases page that a
user downloads and installs by hand.

This document tells you how to publish one.

## Versioning

The marketing version is in `app/VERSION`. Use three numbers, for example
`1.2.0`.

`build-app.sh` writes that version into the bundle as
`CFBundleShortVersionString`. It writes the commit count as `CFBundleVersion`,
thus two bundles from different commits never share a build number. Settings ▸
About shows both.

[CHANGELOG.md](../CHANGELOG.md) holds a section for each version, and the
release notes come from that section.

## To publish a release

1. Write the changes in `CHANGELOG.md`, under a heading with the new version
   number. This is the full record.
2. Write a short summary for the release page in a separate file, for example
   `notes.md`: a few groups with a heading each, and one line for each change.
   The full CHANGELOG section is too long for the page.
3. Put the new version number in `app/VERSION`.
4. Commit all changes. The script refuses to release from a tree that has
   changes, because the build number comes from the number of commits. Keep
   `notes.md` outside the repository, or delete it before the commit.
5. Release:

   ```bash
   cd app
   ./scripts/release.sh --dry-run                 # build and package only
   ./scripts/release.sh --notes ~/notes.md        # the same, then tag and publish
   ```

The script does this:

- It reads `VERSION` and stops if the tag `v<version>` already exists.
- It stops if the working tree has changes.
- It stops if `CHANGELOG.md` has no section for the version.
- It writes the release notes: the install steps, then the file from
  `--notes`, then one line about updating. Without `--notes` it uses the
  CHANGELOG section, which reads long on the page.
- It builds `Notero.app` with `build-app.sh`.
- It makes `dist/Notero-<version>.zip` with `ditto`. Do not use `zip`. The
  executable bit and the code signature must stay correct.
- It makes the tag `v<version>`, pushes it, and makes the GitHub release with
  the `.zip`.

## What the user does

The app has no update button. It has a link.

**Notero ▸ Releases on GitHub…** opens the releases page. Settings ▸ About
holds the same link and the version of that copy. The user downloads the zip,
unpacks it, quits the app, and replaces `Notero.app`.

**A replacement of the app does not touch the user data.** The recordings, the
transcripts and the notes are in
`~/Library/Application Support/Transcriber/`.

## Limits

**The app has no Developer ID certificate.** `build-app.sh` signs the bundle
with an Apple Development identity if the Mac has one, and ad hoc if not.
Neither is a Developer ID. Thus:

- **Gatekeeper refuses a bundle that a browser downloaded.** macOS puts a
  quarantine attribute on the file. To open it the first time, the user
  right-clicks the app and selects Open. Say this on the release page.
- **macOS asks for the audio permissions again after a replacement of an
  ad-hoc build.** macOS connects a permission to the signature, and an ad-hoc
  signature changes with each build. A build signed with an Apple Development
  identity keeps its permissions across builds.

To remove both limits, sign with a Developer ID certificate and notarize the
`.zip`. Then add the `codesign` identity and `notarytool` to `build-app.sh`.

## The releases page must be readable

`About.owner` and `About.repository` in
`app/Sources/Transcriber/About.swift` give the address that the menu item
opens. A private repository answers 404 to a user who is not signed in.

Either make the repository public, or change those two constants to a public
repository that holds the releases.
