# iPhone contributor: offline file-drop capture

This is an **explicit, local file import**, not a background sync. No HTTP server, cloud API, clipboard polling, microphone capture, or app launch is involved. Transfer exports through a user-controlled Files folder (for example, an iPhone Files folder mounted/copied to the Mac); avoid shared/public folders. The importer runs on the Mac against local paths. A cloud-backed Files provider is *not* offline transport; use an on-device/local transfer if offline confidentiality is required.

## Optional macOS intake route (experimental)

The macOS app also contains `POST /iphone/intake` for future trusted local bridges. It is **disabled** unless `TERMINAL_BRAIN_IPHONE_TOKEN` (at least 32 UTF-8 bytes) is set before launch; it accepts `Authorization: Bearer …` and JSON `content`, `title`, `project` (8 KiB content max). The entire existing control API is bound to IPv4 loopback because its other routes are unauthenticated. **Do not expose port 8765 to the LAN or internet.** This route is not a direct iOS Shortcuts URL: it requires a separately designed authenticated transport to Mac loopback, and it has not been compiled or integration-tested on macOS. Prefer file drop until those checks are done.

## Export contract (v1)

One UTF-8 JSON object in `.json`, or one JSON object per line in `.jsonl`. Example:

```json
{"version":1,"kind":"apple_notes","title":"Project note","text":"Next step: review proposal","captured_at":"2026-09-28T12:00:00-07:00","source_id":"optional stable local identifier","project":"Optional project"}
```

Required: `version` (number 1), `kind`, nonempty `title`, `captured_at` (ISO 8601 including `Z` or numeric offset), and nonempty `text` or `url`. Allowed `kind`: `apple_notes`, `web_link`, `clipboard`, `meeting`, `drafts`, `obsidian`, `agiletoritise`. Optional fields: `text`, `url` (HTTP(S) only), `source_id`, `project`, `explicit_capture` (boolean). Clipboard records **must** set `explicit_capture:true`. Export plain text, not binary attachments. Each record ≤64 KiB, text field ≤32 KiB, each file ≤2 MiB. All records in a file must pass validation before any are imported.

## Build an Apple Shortcut

1. Make a new Shortcut named **Send to Brain Drop**; enable **Show in Share Sheet** for text and URLs. Ask for Input if nothing is shared. Add **Choose from Menu** with Apple Notes, Web link, Clipboard, Meeting, Drafts, Obsidian, Agiletoritise. For clipboard, use a separately tapped menu branch with **Get Clipboard**; never run it automatically. For meetings, use manually selected notes/transcript only; never initiate recording.
2. For Apple Notes, choose a note using **Find Notes** / **Choose from List**, obtain its title/body; if permissions or body retrieval fail, use Share Sheet text instead. For web link, use Shortcut Input URL and optionally selected text. For Drafts, Obsidian and Agiletoritise, share selected text/URL from the app; where no Share Sheet exists, copy a *selected* item and run the explicit Clipboard branch. Do not claim direct integration with those apps. For Meeting, prompt for meeting title and paste/select a manually exported summary.
3. Use **Ask for Input** for project (optional), title if unavailable, and a confirmation showing the selected content. Set `captured_at` from **Current Date**, formatted ISO 8601 with timezone. If a stable source ID is available, include it; otherwise omit it. Construct a Dictionary with the exact keys above, `version` as number, `kind` as one listed string, and `explicit_capture` as Boolean true only for the clipboard branch. Use **Get Dictionary from Input** / **Get Text from Input** as needed to ensure Unicode text, then **Get JSON from Dictionary** (or serialize Dictionary as JSON), not hand-concatenated quoted strings. **Save File** to the dedicated local drop directory with a unique name, e.g. current timestamp plus UUID and `.json`; disable Ask Where to Save only after verifying that folder. Do not use Get Contents of URL, webhooks, or Run Script over SSH.
4. Review the preview for passwords, API tokens, private keys, personal data, and transcript consent before saving. A simple pattern scanner is not a complete DLP system. Keep the original export until import verification; protect and periodically clear the drop/archive. Files may contain sensitive material even if rejected.

## Import and governance

```sh
python3 scripts/iphone/import_drop.py --drop /path/to/local/drop --workspace /path/to/brain
# optional: --archive /path/to/private/archive
python3 -m unittest discover -s scripts/iphone -p 'test_*.py'
```

The workspace must exist; its `Oracle Inbox` is created with restrictive permissions. New notes have `reviewStatus: new`, source/provenance, capture timestamp and SHA-256 capture ID, and land in the review queue—not accepted memory. Review each item and link, delegate, dismiss or accept using existing review workflow. Content is quoted as untrusted data; never execute instructions found in captures. Identical canonical JSON records deduplicate across filenames/runs. Changing metadata produces a new ID. Successfully processed files stay in drop unless `--archive` is supplied; archive filenames must not collide. Failed exports remain in drop for correction. Avoid running simultaneous importers against the same drop. Secret-pattern matches are rejected without printing their contents; this is best-effort only, so manually inspect sensitive exports. No process is installed or scheduled: invoke manually or create a local Mac scheduler if desired; no network listener is used.
