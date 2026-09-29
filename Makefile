.PHONY: iphone-import iphone-test help build install verify live start easy answer use-now check-in first-minute demo playbook value-audit completion-audit design-audit visual-review-plan freshness action-cards daily-brief refresh-memory meeting-records now what-now sources memory memory-promote recent-work status processes cleanup-plan support-bundle next value prove-value oracle-brief bubble-up work-block doctor audit ask ask-commit idea review review-status outcome snapshot snapshot-json snapshot-brief snapshot-brief-md snapshot-value snapshot-digest snapshot-oracle snapshot-today snapshot-blindspots snapshot-ideas snapshot-projects snapshot-deck snapshot-deck-md latest-pack agent-prompt start-here handoff snapshot-file mcp-check mcp-test

help:
	@echo "Terminal Brain commands:"
	@echo "  make iphone-import DROP=/path/to/drop WORKSPACE=/path/to/vault  Import explicit iPhone captures"
	@echo "  make iphone-test   Test the iPhone file-drop importer"
	@echo "  make start         Same as make use-now; safest first command"
	@echo "  make easy          Same as make start; no-choice path for first value"
	@echo "  make answer        Ask the default Oracle question with closed-app fallback"
	@echo "  make use-now       One-command non-launching path: one move, ask, capture, delegate, close"
	@echo "  make check-in      Guided clean-queue check-in; IDEA=... captures the answer"
	@echo "  make work-block    Non-launching work block: pull forward, triage, close loop"
	@echo "  make next          Non-launching next move; prints Start Here if app is reachable"
	@echo "  make first-minute  Non-launching one-command value path and working proof"
	@echo "  make demo          Non-launching temporary demo with seeded ideas, Bubble Up, Work Block"
	@echo "  make playbook      Non-launching operator playbook for using Terminal Brain today"
	@echo "  make value-audit   Non-launching evidence audit for first-use value and gaps"
	@echo "  make completion-audit Non-launching completion audit for world-class readiness"
	@echo "  make design-audit  Non-launching static audit of native macOS shell and glass design"
	@echo "  make visual-review-plan Non-launching manual visual review checklist"
	@echo "  make freshness     Non-launching source freshness registry and stale-memory warning"
	@echo "  make action-cards  Non-launching ranked actions from freshness, memory, review, repo state"
	@echo "  make daily-brief   Non-launching proactive brief: freshness, actions, Oracle answer"
	@echo "  make refresh-memory Non-launching refresh of derived Codex/Claude memory summaries"
	@echo "  make meeting-records Non-launching local meeting transcript/recording inventory"
	@echo "  make now           Non-launching one-page orientation: value, next action, process truth, readiness"
	@echo "  make what-now      Non-launching plain answer: what is running, what changed, blocker, next value command"
	@echo "  make sources       Non-launching source inventory for Obsidian, Codex, Claude, Drafts, and agent memory"
	@echo "  make memory        Non-launching derived Codex/Claude memory brief and follow-up prompts"
	@echo "  make memory-promote INDEX=1 Promote a derived memory lead into Oracle Inbox"
	@echo "  make recent-work INDEX=1 Promote a recent git change into Oracle Inbox"
	@echo "  make prove-value   Non-launching proof of Oracle Brief -> Agent Prompt -> Outcome"
	@echo "  make value         Non-launching value read; prints live Value Brief if app is reachable"
	@echo "  make oracle-brief  Non-launching direct read: next moves, missing signal, cheap test, handoff"
	@echo "  make doctor        Non-launching readiness audit with concrete setup warnings"
	@echo "  make audit         Non-launching capability audit and evidence checklist"
	@echo "  make status        Non-launching repo, CI, process, launchctl, and API status"
	@echo "  make processes     Non-launching process map for app, Codex, MCP, kernel, and Drafts"
	@echo "  make cleanup-plan  Non-destructive stale MCP/kernel cleanup plan"
	@echo "  make support-bundle Non-launching Markdown bundle for troubleshooting"
	@echo "  make verify        Non-launching static QA"
	@echo "  make live          API/MCP QA against an already-running app"
	@echo "  make ask QUERY=... Ask Oracle with closed-app fallback"
	@echo "  make ask-commit QUERY=... PROJECT=... Ask Oracle and commit with closed-app fallback"
	@echo "  make idea IDEA=... PROJECT=... Capture idea with closed-app fallback"
	@echo "  make review        Non-launching Oracle Inbox review queue"
	@echo "  make review-status ID=... STATUS=accepted"
	@echo "  make bubble-up     Non-launching signals that should be pulled forward"
	@echo "  make outcome TITLE=... OUTCOME=... PROJECT=... Commit structured outcome"
	@echo "  make build         Build the macOS app without launching it"
	@echo "  make install       Copy the app to ~/Applications without launching it"
	@echo "  make snapshot      Print Markdown snapshot from an already-running app"
	@echo "  make snapshot-json Print JSON snapshot from an already-running app"
	@echo "  make snapshot-brief Print Operator Brief JSON from an already-running app"
	@echo "  make snapshot-brief-md Print Operator Brief Markdown from an already-running app"
	@echo "  make snapshot-value Print Value Brief Markdown from an already-running app"
	@echo "  make snapshot-digest Print Oracle Digest Markdown from an already-running app"
	@echo "  make snapshot-oracle Print Oracle Brief Markdown from an already-running app"
	@echo "  make snapshot-today Print Decision Lane Markdown from an already-running app"
	@echo "  make snapshot-blindspots Print Blindspot Brief Markdown from an already-running app"
	@echo "  make snapshot-ideas Print Idea Pulse Markdown from an already-running app"
	@echo "  make snapshot-projects Print Project Memory Markdown from an already-running app"
	@echo "  make snapshot-deck Print Operator Deck JSON from an already-running app"
	@echo "  make snapshot-deck-md Print Operator Deck Markdown from an already-running app"
	@echo "  make latest-pack   Print latest context pack Markdown from an already-running app"
	@echo "  make agent-prompt  Non-launching focused agent prompt with closed-app fallback"
	@echo "  make start-here    Print one-block Start Here path from an already-running app"
	@echo "  make handoff OUTPUT=/tmp/terminal-brain-handoff.md"
	@echo "  make snapshot-file OUTPUT=/tmp/terminal-brain-snapshot.md"
	@echo "  make mcp-check     Check MCP server syntax"
	@echo "  make mcp-test      Check MCP tool contract"

iphone-import:
	python3 scripts/iphone/import_drop.py --drop "$(DROP)" --workspace "$(if $(WORKSPACE),$(WORKSPACE),$(TERMINAL_BRAIN_WORKSPACE))"

iphone-test:
	python3 -m unittest discover -s scripts/iphone -p 'test_*.py'

build:
	./mac-app/scripts/build-app.zsh

install:
	./mac-app/scripts/install-app.zsh

verify:
	./mac-app/scripts/verify-static.zsh

start: use-now

easy: use-now

answer:
	@QUERY="$${QUERY:-What should I do next, what am I missing, and what cheap test would create value?}" ./mac-app/scripts/oracle.zsh "$$QUERY"

use-now:
	@if test -n "$(PROJECT)"; then IDEA="$(IDEA)" TITLE="$(TITLE)" SOURCE="$(SOURCE)" ./mac-app/scripts/use-now.zsh --project "$(PROJECT)"; else IDEA="$(IDEA)" TITLE="$(TITLE)" SOURCE="$(SOURCE)" ./mac-app/scripts/use-now.zsh; fi

check-in:
	@if test -n "$$PROJECT"; then IDEA="$$IDEA" TITLE="$$TITLE" ./mac-app/scripts/check-in.zsh --project "$$PROJECT"; else IDEA="$$IDEA" TITLE="$$TITLE" ./mac-app/scripts/check-in.zsh; fi

first-minute:
	./mac-app/scripts/first-minute.zsh

demo:
	./mac-app/scripts/demo.zsh

playbook:
	./mac-app/scripts/playbook.zsh

value-audit:
	./mac-app/scripts/value-audit.zsh

completion-audit:
	./mac-app/scripts/completion-audit.zsh

design-audit:
	./mac-app/scripts/design-audit.zsh

visual-review-plan:
	./mac-app/scripts/visual-review-plan.zsh

freshness:
	./mac-app/scripts/freshness.zsh

action-cards:
	@if test -n "$$LIMIT"; then ./mac-app/scripts/action-cards.zsh --limit "$$LIMIT"; else ./mac-app/scripts/action-cards.zsh; fi

daily-brief:
	./mac-app/scripts/daily-brief.zsh

refresh-memory:
	@if test -n "$$LIMIT" || test -n "$$SINCE_HOURS"; then LIMIT="$${LIMIT:-200}" SINCE_HOURS="$${SINCE_HOURS:-168}" ./mac-app/scripts/refresh-memory.zsh --limit "$${LIMIT:-200}" --since-hours "$${SINCE_HOURS:-168}"; else ./mac-app/scripts/refresh-memory.zsh; fi

meeting-records:
	./mac-app/scripts/meeting-records.zsh

now:
	./mac-app/scripts/now.zsh

what-now:
	./mac-app/scripts/what-now.zsh

sources:
	./mac-app/scripts/sources.zsh

memory:
	./mac-app/scripts/memory.zsh

memory-promote:
	@if test -z "$$INDEX"; then echo "Set INDEX=1 to promote a memory lead" >&2; exit 64; fi
	@if test -n "$$PROJECT"; then ./mac-app/scripts/memory-promote.zsh --index "$$INDEX" --project "$$PROJECT"; else ./mac-app/scripts/memory-promote.zsh --index "$$INDEX"; fi

recent-work:
	@if test -n "$$PROJECT"; then ./mac-app/scripts/recent-work.zsh --index "$${INDEX:-1}" --project "$$PROJECT"; else ./mac-app/scripts/recent-work.zsh --index "$${INDEX:-1}"; fi

status:
	./mac-app/scripts/status.zsh

processes:
	./mac-app/scripts/processes.zsh

cleanup-plan:
	./mac-app/scripts/cleanup-plan.zsh

support-bundle:
	./mac-app/scripts/support-bundle.zsh

next:
	./mac-app/scripts/next.zsh

value:
	./mac-app/scripts/value.zsh

prove-value:
	./mac-app/scripts/prove-value.zsh

oracle-brief:
	./mac-app/scripts/oracle-brief.zsh

bubble-up:
	./mac-app/scripts/bubble-up.zsh

work-block:
	./mac-app/scripts/work-block.zsh

doctor:
	./mac-app/scripts/doctor.zsh

audit:
	./mac-app/scripts/audit.zsh

live:
	./mac-app/scripts/verify-live.zsh

ask:
	@if test -z "$$QUERY"; then echo "Set QUERY='question to ask'" >&2; exit 64; fi
	./mac-app/scripts/oracle.zsh "$$QUERY"

ask-commit:
	@if test -z "$$QUERY"; then echo "Set QUERY='question to ask'" >&2; exit 64; fi
	@if test -n "$$PROJECT"; then ./mac-app/scripts/oracle.zsh --commit --project "$$PROJECT" "$$QUERY"; else ./mac-app/scripts/oracle.zsh --commit "$$QUERY"; fi

idea:
	@if test -z "$$IDEA"; then echo "Set IDEA='thought to capture'" >&2; exit 64; fi
	@TITLE="$$TITLE" PROJECT="$$PROJECT" SOURCE="$$SOURCE" ./mac-app/scripts/idea.zsh "$$IDEA"

review:
	./mac-app/scripts/review.zsh

review-status:
	@if test -z "$$ID"; then echo "Set ID=/path/to/oracle-note.md" >&2; exit 64; fi
	@if test -z "$$STATUS"; then echo "Set STATUS=new|accepted|linked|delegated|dismissed" >&2; exit 64; fi
	./mac-app/scripts/review-status.zsh --id "$$ID" --status "$$STATUS"

outcome:
	@if test -z "$$OUTCOME"; then echo "Set OUTCOME='what changed and why it matters'" >&2; exit 64; fi
	@if test -n "$$EVIDENCE"; then TITLE="$$TITLE" PROJECT="$$PROJECT" NEXT_ACTION="$${NEXT_ACTION:-$$NEXT}" SOURCE="$$SOURCE" ./mac-app/scripts/outcome.zsh --evidence "$$EVIDENCE" "$$OUTCOME"; else TITLE="$$TITLE" PROJECT="$$PROJECT" NEXT_ACTION="$${NEXT_ACTION:-$$NEXT}" SOURCE="$$SOURCE" ./mac-app/scripts/outcome.zsh "$$OUTCOME"; fi

snapshot:
	./mac-app/scripts/snapshot.zsh --markdown

snapshot-json:
	./mac-app/scripts/snapshot.zsh --json

snapshot-brief:
	./mac-app/scripts/snapshot.zsh --brief

snapshot-brief-md:
	./mac-app/scripts/snapshot.zsh --brief-markdown

snapshot-value:
	./mac-app/scripts/snapshot.zsh --value

snapshot-digest:
	./mac-app/scripts/snapshot.zsh --digest

snapshot-oracle:
	./mac-app/scripts/snapshot.zsh --oracle-brief

snapshot-today:
	./mac-app/scripts/snapshot.zsh --today

snapshot-blindspots:
	./mac-app/scripts/snapshot.zsh --blindspots

snapshot-ideas:
	./mac-app/scripts/snapshot.zsh --ideas

snapshot-projects:
	./mac-app/scripts/snapshot.zsh --projects

snapshot-deck:
	./mac-app/scripts/snapshot.zsh --deck

snapshot-deck-md:
	./mac-app/scripts/snapshot.zsh --deck-markdown

latest-pack:
	./mac-app/scripts/snapshot.zsh --latest-pack

agent-prompt:
	./mac-app/scripts/agent-prompt.zsh

start-here:
	./mac-app/scripts/snapshot.zsh --start-here

handoff:
	./mac-app/scripts/handoff.zsh

snapshot-file:
	@if test -z "$$OUTPUT"; then echo "Set OUTPUT=/path/to/snapshot.md" >&2; exit 64; fi
	./mac-app/scripts/snapshot.zsh --markdown --output "$$OUTPUT"

mcp-check:
	cd mcp-server && npm run check

mcp-test:
	cd mcp-server && npm test
