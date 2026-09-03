# Changelog

## 1.0.1 — 2026-09-03

- Recordings a quit left in preparing, recording or transcribing are resolved at
  launch: completed if the transcript exists, otherwise marked failed with a
  message that says what to do. Nothing is deleted.
- Settings shows microphone permission state with the right action for it
  (ask once, or open System Settings once denied).
- Transcript info bar under the title: model, language, words, processing ratio,
  revision. An ⓘ popover shows everything stored about the transcript.
- The model load before a recording starts is shown as a preparing state in the
  header, toolbar and detail pane instead of looking like a hang.
- Working-copy write failures name the path, the reason and the free space on
  the volume. Audio-cache progress is reported in whole percents.
- Plan for 1.1 in `docs/APP-UPDATE-PLAN.md`.

## 1.0 — 2026-09-02

- First native macOS release.
