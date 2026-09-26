# Command Reference

Every target below is defined in the top-level [`Makefile`](../Makefile); run `make` with no arguments to print the same list. Unless a row says otherwise, commands **do not launch or foreground** Terminal Brain. Commands described as "from an already-running app" need the app open and its local API reachable on port 8765; the rest fall back to local reads or direct Oracle Inbox writes when the app is closed.

For the day-to-day workflow built on these commands, see [`START-HERE.md`](../START-HERE.md). Agents should also read [`AGENTS.md`](../AGENTS.md).

## Make targets

| Command | What it does |
| --- | --- |
| `make start` | Same as make use-now; safest first command |
| `make easy` | Same as make start; no-choice path for first value |
| `make answer` | Ask the default Oracle question with closed-app fallback |
| `make use-now` | One-command non-launching path: one move, ask, capture, delegate, close |
| `make check-in` | Guided clean-queue check-in; IDEA=... captures the answer |
| `make work-block` | Non-launching work block: pull forward, triage, close loop |
| `make next` | Non-launching next move; prints Start Here if app is reachable |
| `make first-minute` | Non-launching one-command value path and working proof |
| `make demo` | Non-launching temporary demo with seeded ideas, Bubble Up, Work Block |
| `make playbook` | Non-launching operator playbook for using Terminal Brain today |
| `make value-audit` | Non-launching evidence audit for first-use value and gaps |
| `make completion-audit` | Non-launching completion audit for world-class readiness |
| `make design-audit` | Non-launching static audit of native macOS shell and glass design |
| `make visual-review-plan` | Non-launching manual visual review checklist |
| `make freshness` | Non-launching source freshness registry and stale-memory warning |
| `make action-cards` | Non-launching ranked actions from freshness, memory, review, repo state |
| `make daily-brief` | Non-launching proactive brief: freshness, actions, Oracle answer |
| `make refresh-memory` | Non-launching refresh of derived Codex/Claude memory summaries |
| `make meeting-records` | Non-launching local meeting transcript/recording inventory |
| `make now` | Non-launching one-page orientation: value, next action, process truth, readiness |
| `make what-now` | Non-launching plain answer: what is running, what changed, blocker, next value command |
| `make sources` | Non-launching source inventory for Obsidian, Codex, Claude, Drafts, and agent memory |
| `make memory` | Non-launching derived Codex/Claude memory brief and follow-up prompts |
| `make memory-promote INDEX=1` | Promote a derived memory lead into Oracle Inbox |
| `make recent-work INDEX=1` | Promote a recent git change into Oracle Inbox |
| `make prove-value` | Non-launching proof of Oracle Brief -> Agent Prompt -> Outcome |
| `make value` | Non-launching value read; prints live Value Brief if app is reachable |
| `make oracle-brief` | Non-launching direct read: next moves, missing signal, cheap test, handoff |
| `make doctor` | Non-launching readiness audit with concrete setup warnings |
| `make audit` | Non-launching capability audit and evidence checklist |
| `make status` | Non-launching repo, CI, process, launchctl, and API status |
| `make processes` | Non-launching process map for app, Codex, MCP, kernel, and Drafts |
| `make cleanup-plan` | Non-destructive stale MCP/kernel cleanup plan |
| `make support-bundle` | Non-launching Markdown bundle for troubleshooting |
| `make verify` | Non-launching static QA |
| `make live` | API/MCP QA against an already-running app |
| `make ask QUERY=...` | Ask Oracle with closed-app fallback |
| `make ask-commit QUERY=... PROJECT=...` | Ask Oracle and commit with closed-app fallback |
| `make idea IDEA=... PROJECT=...` | Capture idea with closed-app fallback |
| `make review` | Non-launching Oracle Inbox review queue |
| `make review-status ID=... STATUS=accepted` | Set an Oracle Inbox note to new, accepted, linked, delegated, or dismissed |
| `make bubble-up` | Non-launching signals that should be pulled forward |
| `make outcome TITLE=... OUTCOME=... PROJECT=...` | Commit structured outcome |
| `make build` | Build the macOS app without launching it |
| `make install` | Copy the app to ~/Applications without launching it |
| `make snapshot` | Print Markdown snapshot from an already-running app |
| `make snapshot-json` | Print JSON snapshot from an already-running app |
| `make snapshot-brief` | Print Operator Brief JSON from an already-running app |
| `make snapshot-brief-md` | Print Operator Brief Markdown from an already-running app |
| `make snapshot-value` | Print Value Brief Markdown from an already-running app |
| `make snapshot-digest` | Print Oracle Digest Markdown from an already-running app |
| `make snapshot-oracle` | Print Oracle Brief Markdown from an already-running app |
| `make snapshot-today` | Print Decision Lane Markdown from an already-running app |
| `make snapshot-blindspots` | Print Blindspot Brief Markdown from an already-running app |
| `make snapshot-ideas` | Print Idea Pulse Markdown from an already-running app |
| `make snapshot-projects` | Print Project Memory Markdown from an already-running app |
| `make snapshot-deck` | Print Operator Deck JSON from an already-running app |
| `make snapshot-deck-md` | Print Operator Deck Markdown from an already-running app |
| `make latest-pack` | Print latest context pack Markdown from an already-running app |
| `make agent-prompt` | Non-launching focused agent prompt with closed-app fallback |
| `make start-here` | Print one-block Start Here path from an already-running app |
| `make handoff OUTPUT=/tmp/terminal-brain-handoff.md` | Write a single-file agent handoff (local fallback when the app is closed) |
| `make snapshot-file OUTPUT=/tmp/terminal-brain-snapshot.md` | Write the Markdown snapshot to a file |
| `make mcp-check` | Check MCP server syntax |
| `make mcp-test` | Check MCP tool contract |

## Underlying scripts

The Make targets wrap scripts in `mac-app/scripts/`. Most accept `--help`. A few flags worth knowing:

```zsh
./mac-app/scripts/oracle.zsh "what should I work on next?"
./mac-app/scripts/oracle.zsh --commit --project "Terminal Brain" "what changed?"
./mac-app/scripts/outcome.zsh --title "Shipped Review Queue" --project "Terminal Brain" \
  --next "Review stale reads tomorrow." "Added triage for committed Oracle reads."
./mac-app/scripts/snapshot.zsh --markdown            # also --json, --value, --digest, --today,
                                                     # --blindspots, --ideas, --projects, --deck,
                                                     # --deck-markdown, --latest-pack, --agent-prompt,
                                                     # --start-here, --brief-markdown
./mac-app/scripts/snapshot.zsh --markdown --output /tmp/terminal-brain-snapshot.md
./mac-app/scripts/handoff.zsh --output /tmp/terminal-brain-handoff.md
./mac-app/scripts/processes.zsh --details            # include matching process rows
```

`make support-bundle` writes `/tmp/terminal-brain-support-bundle.md` unless `OUTPUT=/path/file.md` is supplied.

## Verification

| Command | Scope |
| --- | --- |
| `./mac-app/scripts/verify-static.zsh` (`make verify`) | Shell syntax, MCP syntax and tool contract, API route contract, Swift type-check, app build, foreground guard, UI copy checks, secret-pattern scan. This is what CI runs. |
| `./mac-app/scripts/verify-live.zsh` (`make live`) | `/health`, `/snapshot`, `/handoff/markdown`, `/agent-prompt/markdown`, and MCP snapshot/handoff/prompt tools against an app that is **already running**. Never starts it. |
| `node mcp-server/check-tools.mjs` (`make mcp-test`) | MCP tool list matches `mcp-server/expected-tools.json`. |
