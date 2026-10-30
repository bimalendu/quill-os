# The Quill OS no-AI policy

Quill OS does not integrate AI. This page says exactly what that means, how it
is enforced, and where it stops.

## Scope

Decided 2026-10-30.

**Not shipped, and not enabled by default:** generative and assistant AI:
chatbots, LLM assistants, local LLM runtimes and servers, AI agents, and
AI-generated-content tools, including the ones built into other software
(Firefox).

**Allowed:** classical machine learning that does one fixed local job.
Tesseract OCR (Okular, Skanpage), eSpeak text-to-speech, and text prediction in
input methods stay. They are not assistants and do not generate content.

If you want a stricter line (no learned models at all), that would also drop
OCR and predictive input; see "Changing the scope".

## What is enforced, and where

| What | Where | How |
|---|---|---|
| No denylisted package or Flatpak in an image | `policy/ai-denylist.txt` | `make check-image` runs `tests/check-denylist.sh`; CI fails the build on a match. The first-boot package picker's groups (Phase 5) are checked against the same list. |
| Firefox AI features off by default | `packages/quill-no-ai/policies.json` -> `/usr/lib64/firefox/distribution/policies.json` | Firefox's `AIControls` policy, `Default: blocked`, `Locked: false`. |
| The Firefox policy is valid for the shipped Firefox | `tests/check-no-ai.sh` (`make check-no-ai`) | Validates against the schema inside the image's own Firefox. |
| Firefox really applies the policy | `tests/probe-firefox.py` (`make check-firefox`) | Starts the image's own Firefox headless in a chroot and asks it, over Marionette, for the effective settings. Takes about a minute. |
| The gate itself works | `tests/test-denylist.sh` (in `make test`) | Feeds it clean and denylisted lists and requires pass and fail respectively. |

### Firefox

Firefox reads policies only from `<install dir>/distribution/policies.json`
(checked in the shipped Firefox), so the file lives there, not in `/etc`.

`AIControls.Default` applies to every AI feature Firefox has, including ones
added later, unless a feature is set explicitly. In Firefox 159 the features
are: Translations, PDFAltText, SmartTabGroups, LinkPreviewKeyPoints,
SidebarChatbot, SmartWindow, SpeechRecognition. Blocked means off and
unavailable in the UI; on-device models are removed.

`Locked: false` is deliberate. Users can turn features on in Firefox's
settings. If you want them unable to, set `Locked` to `true`.

Firefox's Translations (local neural machine translation) is classed as an AI
feature by Mozilla, so it is blocked by default too, and users can enable it.

## What the policy does not do

- It does not stop users installing AI software. The denylist gates what Quill
  **ships**; the installed system does not block `dnf install`.
- It does not filter Flathub or Discover. Flathub carries AI apps; Quill
  cannot hide them from the store.
- It does not block websites' own AI, or AI browser extensions a user installs.
- It does not cover software the user adds later (editors, extensions).
- KDE Plasma has no AI integration in Fedora 44; a scan of the 2,004 image
  packages found none (matches were Tesseract, eSpeak and the OpenCV library).

## Maintainer checklist

On every new Firefox major version or Fedora release:

1. Build the image and run `make check-image check-no-ai check-firefox`.
   `check-no-ai` fails if Firefox removed or renamed a feature key;
   `check-firefox` fails if the running Firefox does not apply the policy.
2. List `AIControls` keys in the new Firefox and check `Default: blocked`
   still covers them. `check-no-ai.sh` prints the keys it found.
3. Search the new Fedora repos for newly packaged AI software and add it to
   `policy/ai-denylist.txt`:
   `dnf search "large language model" "AI assistant" ollama llama`, then
   judge by hand. Keep globs narrow: `copilot*` matches Haskell's unrelated
   `ghc-copilot-*`.

## Changing the scope

- **Add something to the denylist:** add an `rpm:` or `flatpak:` line to
  `policy/ai-denylist.txt` with a comment, run `make test`.
- **Make Firefox's setting unchangeable:** set `Locked` to `true` in
  `packages/quill-no-ai/policies.json` and update the matching assertion in
  `tests/check-no-ai.sh`, which currently requires `false`.
- **Stricter scope** (also drop Tesseract, `opencv-dnn`, ibus-typing-booster,
  libpinyin): add them to the denylist and to the kiwi `<ignore>` list. Expect
  to lose OCR in Okular and Skanpage and predictive input.

## Evidence

Measured 2026-10-30 on Firefox 159 from the Fedora 44 Asahi packages, by
`make check-firefox`:

| Image | Policy engine | Chatbot / link previews / smart tab groups / PDF alt text |
|---|---|---|
| Stock Fedora Asahi Remix (baseline) | inactive | all **on** |
| Quill OS (`quill-no-ai`) | active | all **off**, none locked |
