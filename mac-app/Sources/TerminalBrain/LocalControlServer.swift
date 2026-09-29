import Foundation
import Network

final class LocalControlServer {
    private let port: NWEndpoint.Port = 8765
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.franklin.terminal-brain.control-api")

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            // Existing routes have no authentication; never expose them to the LAN.
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            fputs("Terminal Brain control API failed to start: \(error)\n", stderr)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, Data())
    }

    private func receive(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var next = buffer
            if let data {
                next.append(data)
            }
            if next.count > 20_480 {
                self.send(.json(413, ["error": "Request too large"]), on: connection)
                return
            }
            if let request = HTTPRequest.parse(next) {
                Task {
                    let response = await self.route(request)
                    self.send(response, on: connection)
                }
                return
            }
            if isComplete || error != nil {
                self.send(.json(400, ["error": "Invalid or incomplete HTTP request"]), on: connection)
                return
            }
            self.receive(connection, next)
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .json(200, ["ok": true, "service": "terminal-brain", "port": 8765])
        case ("GET", "/status"):
            return .json(200, await ControlSnapshot.status())
        case ("GET", "/snapshot"):
            return .json(200, await BrainSnapshot.snapshot())
        case ("GET", "/snapshot/markdown"):
            return .text(200, await BrainSnapshot.markdown())
        case ("GET", "/handoff/markdown"):
            return .text(200, await BrainHandoffSnapshot.markdown())
        case ("GET", "/agent-prompt/markdown"):
            return .text(200, await AgentPromptSnapshot.markdown())
        case ("GET", "/now"):
            return .json(200, await NowSnapshot.now())
        case ("GET", "/now/markdown"):
            return .text(200, await NowSnapshot.markdown())
        case ("GET", "/what-now/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain What Now", scriptName: "what-now.zsh", makeTarget: "make what-now"))
        case ("GET", "/use-now/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain Use Now", scriptName: "use-now.zsh", makeTarget: "make use-now"))
        case ("GET", "/first-minute/markdown"):
            return .text(200, await FirstMinuteSnapshot.markdown())
        case ("GET", "/demo/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain Demo", scriptName: "demo.zsh", makeTarget: "make demo"))
        case ("GET", "/playbook/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain Playbook", scriptName: "playbook.zsh", makeTarget: "make playbook"))
        case ("GET", "/value-audit/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain Value Audit", scriptName: "value-audit.zsh", makeTarget: "make value-audit"))
        case ("GET", "/completion-audit/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(
                title: "Terminal Brain Completion Audit",
                scriptName: "completion-audit.zsh",
                makeTarget: "make completion-audit",
                environment: ["TERMINAL_BRAIN_COMPLETION_AUDIT_SKIP_VERIFY": "1"]
            ))
        case ("GET", "/visual-review-plan/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain Visual Review Plan", scriptName: "visual-review-plan.zsh", makeTarget: "make visual-review-plan"))
        case ("GET", "/cleanup-plan/markdown"):
            return .text(200, await CleanupPlanSnapshot.markdown())
        case ("GET", "/process-map/markdown"):
            return .text(200, await ProcessMapSnapshot.markdown())
        case ("GET", "/support-bundle/markdown"):
            return .text(200, await SupportBundleSnapshot.markdown())
        case ("GET", "/work-block/markdown"):
            return .text(200, await WorkBlockSnapshot.markdown())
        case ("GET", "/value-proof/markdown"):
            return .text(200, await ValueProofSnapshot.markdown())
        case ("GET", "/start-here/markdown"):
            return .text(200, await StartHereSnapshot.markdown())
        case ("GET", "/sources"):
            return .json(200, await ControlSnapshot.sources())
        case ("GET", "/sources/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain Source Inventory", scriptName: "sources.zsh", makeTarget: "make sources"))
        case ("GET", "/memory/markdown"):
            return .text(200, await ScriptMarkdownSnapshot.markdown(title: "Terminal Brain Memory Brief", scriptName: "memory.zsh", makeTarget: "make memory"))
        case ("POST", "/memory/promote"):
            let index = request.jsonBody?["index"] as? Int ?? Int(request.jsonBody?["index"] as? Double ?? 0)
            let project = (request.jsonBody?["project"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dryRun = request.jsonBody?["dryRun"] as? Bool ?? false
            guard index > 0 else {
                return .json(400, ["ok": false, "error": "index must be greater than zero"])
            }
            var args = [
                "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/memory-promote.zsh",
                "--index",
                "\(index)"
            ]
            if !project.isEmpty {
                args.append(contentsOf: ["--project", project])
            }
            if dryRun {
                args.append("--dry-run")
            }
            let result = await CommandRunner.run("/bin/zsh", args)
            if let data = result.stdout.data(using: .utf8),
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return .json(result.succeeded ? 200 : 500, payload)
            }
            return .json(result.succeeded ? 200 : 500, [
                "ok": result.succeeded,
                "status": result.status,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "guardrail": "memory promotion route did not launch or foreground Terminal Brain"
            ])
        case ("POST", "/recent-work/promote"):
            let index = request.jsonBody?["index"] as? Int ?? Int(request.jsonBody?["index"] as? Double ?? 1)
            let project = (request.jsonBody?["project"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dryRun = request.jsonBody?["dryRun"] as? Bool ?? false
            guard index > 0 else {
                return .json(400, ["ok": false, "error": "index must be greater than zero"])
            }
            var args = [
                "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/recent-work.zsh",
                "--index",
                "\(index)"
            ]
            if !project.isEmpty {
                args.append(contentsOf: ["--project", project])
            }
            if dryRun {
                args.append("--dry-run")
            }
            let result = await CommandRunner.run("/bin/zsh", args)
            if let data = result.stdout.data(using: .utf8),
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return .json(result.succeeded ? 200 : 500, payload)
            }
            return .json(result.succeeded ? 200 : 500, [
                "ok": result.succeeded,
                "status": result.status,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "guardrail": "recent work promotion route did not launch or foreground Terminal Brain"
            ])
        case ("GET", "/setup"):
            return .json(200, await SetupSnapshot.setup())
        case ("GET", "/projects"):
            return .json(200, ProjectSnapshot.projects())
        case ("GET", "/projects/markdown"):
            return .text(200, ProjectSnapshot.markdown())
        case ("GET", "/context-packs/latest"):
            return .json(200, ControlSnapshot.latestContextPack())
        case ("GET", "/context-packs/latest/markdown"):
            return .text(200, ControlSnapshot.latestContextPackMarkdown())
        case ("GET", "/today"):
            return .json(200, await TodaySnapshot.today())
        case ("GET", "/today/markdown"):
            return .text(200, await TodaySnapshot.markdown())
        case ("GET", "/focus"):
            return .json(200, await FocusSnapshot.focus())
        case ("GET", "/blindspots"):
            return .json(200, await BlindspotSnapshot.blindspots())
        case ("GET", "/blindspots/markdown"):
            return .text(200, await BlindspotSnapshot.markdown())
        case ("GET", "/ideas"):
            return .json(200, await IdeaPulseSnapshot.ideas())
        case ("GET", "/ideas/markdown"):
            return .text(200, await IdeaPulseSnapshot.markdown())
        case ("POST", "/ideas/ask"):
            let id = (request.jsonBody?["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let question = (request.jsonBody?["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .json(200, await IdeaPulseSnapshot.ask(id: id, question: question))
        case ("POST", "/blindspots/ask"):
            let id = (request.jsonBody?["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let question = (request.jsonBody?["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .json(200, await BlindspotSnapshot.ask(id: id, question: question))
        case ("POST", "/blindspots/action"):
            let id = (request.jsonBody?["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (request.jsonBody?["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let disposition = (request.jsonBody?["disposition"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                return .json(400, ["ok": false, "error": "id is required"])
            }
            return .json(200, await BlindspotSnapshot.applyAction(id: id, status: status, disposition: disposition))
        case ("GET", "/operator-brief"):
            return .json(200, await OperatorBriefSnapshot.brief())
        case ("GET", "/operator-brief/markdown"):
            return .text(200, await OperatorBriefSnapshot.markdown())
        case ("GET", "/value-brief"):
            return .json(200, await ValueBriefSnapshot.brief())
        case ("GET", "/value-brief/markdown"):
            return .text(200, await ValueBriefSnapshot.markdown())
        case ("GET", "/oracle-digest"):
            return .json(200, await OracleDigestSnapshot.digest())
        case ("GET", "/oracle-digest/markdown"):
            return .text(200, await OracleDigestSnapshot.markdown())
        case ("GET", "/operator-deck"):
            return .json(200, await OperatorDeckSnapshot.deck())
        case ("GET", "/operator-deck/markdown"):
            return .text(200, await OperatorDeckSnapshot.markdown())
        case ("POST", "/operator-deck/action"):
            let sourceType = (request.jsonBody?["sourceType"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceID = (request.jsonBody?["sourceID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let disposition = (request.jsonBody?["disposition"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (request.jsonBody?["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceType.isEmpty, !sourceID.isEmpty else {
                return .json(400, ["ok": false, "error": "sourceType and sourceID are required"])
            }
            return .json(200, await OperatorDeckSnapshot.applyAction(sourceType: sourceType, sourceID: sourceID, disposition: disposition, status: status))
        case ("POST", "/focus/ask"):
            let question = (request.jsonBody?["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .json(200, await FocusSnapshot.ask(question: question))
        case ("GET", "/radar"):
            return .json(200, await RadarSnapshot.radar())
        case ("POST", "/radar/disposition"):
            let id = (request.jsonBody?["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let disposition = (request.jsonBody?["disposition"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !disposition.isEmpty else {
                return .json(400, ["ok": false, "error": "id and disposition are required"])
            }
            return .json(200, await RadarSnapshot.setDisposition(id: id, disposition: disposition))
        case ("GET", "/briefing"):
            return .json(200, await ControlSnapshot.briefing())
        case ("GET", "/permissions"):
            return .json(200, ControlSnapshot.permissions())
        case ("GET", "/oracle/brief"):
            return .json(200, await OracleSnapshot.brief())
        case ("GET", "/oracle/brief/markdown"):
            return .text(200, await OracleSnapshot.markdown())
        case ("GET", "/oracle/items"):
            return .json(200, await OracleSnapshot.items())
        case ("GET", "/oracle/commits"):
            return .json(200, OracleSnapshot.commits())
        case ("POST", "/oracle/review-status"):
            let id = (request.jsonBody?["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (request.jsonBody?["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !status.isEmpty else {
                return .json(400, ["ok": false, "error": "id and status are required"])
            }
            return .json(200, OracleSnapshot.setReviewStatus(id: id, status: status))
        case ("POST", "/oracle/ask"):
            let question = (request.jsonBody?["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else {
                return .json(400, ["ok": false, "error": "question is required"])
            }
            return .json(200, await OracleSnapshot.ask(question: question))
        case ("POST", "/oracle/commit"):
            let title = (request.jsonBody?["title"] as? String ?? "Oracle Read").trimmingCharacters(in: .whitespacesAndNewlines)
            let content = (request.jsonBody?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                return .json(400, ["ok": false, "error": "content is required"])
            }
            return .json(200, OracleSnapshot.commit(
                title: title.isEmpty ? "Oracle Read" : title,
                content: content,
                question: request.jsonBody?["question"] as? String ?? "",
                source: request.jsonBody?["source"] as? String ?? "Terminal Brain Oracle",
                project: request.jsonBody?["project"] as? String ?? "",
                tags: request.jsonBody?["tags"] as? [String] ?? []
            ))
        case ("POST", "/outcomes/commit"):
            let title = (request.jsonBody?["title"] as? String ?? "Outcome").trimmingCharacters(in: .whitespacesAndNewlines)
            let outcome = (request.jsonBody?["outcome"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let nextAction = (request.jsonBody?["nextAction"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = request.jsonBody?["evidence"] as? [String] ?? []
            guard !outcome.isEmpty else {
                return .json(400, ["ok": false, "error": "outcome is required"])
            }
            let evidenceBlock = evidence
                .map { "- \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
                .filter { $0 != "- " }
                .joined(separator: "\n")
            let body = [
                "## Outcome",
                "",
                outcome,
                "",
                "## Evidence",
                "",
                evidenceBlock.ifEmpty("- No evidence supplied."),
                "",
                "## Next Action",
                "",
                nextAction.ifEmpty("Review and decide the next concrete action.")
            ].joined(separator: "\n")
            let tags = Array(Set((request.jsonBody?["tags"] as? [String] ?? []) + ["terminal-brain", "outcome"])).sorted()
            return .json(200, OracleSnapshot.commit(
                title: title.isEmpty ? "Outcome" : "Outcome - \(title)",
                content: body,
                question: "What changed, why does it matter, and what should happen next?",
                source: request.jsonBody?["source"] as? String ?? "Terminal Brain Outcome",
                project: request.jsonBody?["project"] as? String ?? "",
                tags: tags,
                reviewStatus: "accepted"
            ))
        case ("POST", "/ideas/capture"):
            let content = (request.jsonBody?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                return .json(400, ["ok": false, "error": "content is required"])
            }
            let title = (request.jsonBody?["title"] as? String ?? "Captured Idea").trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = (request.jsonBody?["tags"] as? [String] ?? []) + ["terminal-brain", "idea"]
            let body = [
                content,
                "",
                "## Cheap Test",
                "",
                "- Smallest test:",
                "- Expected signal:",
                "",
                "## Kill Criteria",
                "",
                "- Stop if:",
                "",
                "## Next Action",
                "",
                "- [ ] Decide the next action before this becomes passive memory."
            ].joined(separator: "\n")
            return .json(200, OracleSnapshot.commit(
                title: title.isEmpty ? "Captured Idea" : title,
                content: body,
                question: "Captured from Terminal Brain Focus",
                source: request.jsonBody?["source"] as? String ?? "Terminal Brain Idea Capture",
                project: request.jsonBody?["project"] as? String ?? "",
                tags: Array(Set(tags)).sorted()
            ))
        case ("POST", "/iphone/intake"):
            return IPhoneIntake.accept(request)
        case ("POST", "/sync"):
            let includeNotes = request.jsonBody?["includeAppleNotes"] as? Bool ?? false
            let result = await CommandRunner.run(
                "/bin/zsh",
                [Paths.syncScript],
                environment: ["EDGE_BRAIN_INCLUDE_APPLE_NOTES": includeNotes ? "1" : "0"]
            )
            return .json(200, [
                "ok": result.succeeded,
                "status": result.status,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "includeAppleNotes": includeNotes
            ])
        case ("POST", "/start-work"):
            let query = (request.jsonBody?["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                return .json(400, ["ok": false, "error": "query is required"])
            }
            let result = await CommandRunner.run("/usr/bin/env", ["node", Paths.brainCLI, "context-pack-save", query, Paths.workspace])
            return .json(200, [
                "ok": result.succeeded,
                "query": query,
                "status": result.status,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "latestContextPack": ControlSnapshot.newestContextPackPath()
            ])
        default:
            return .json(404, ["error": "Unknown route", "path": request.path])
        }
    }
}

enum OracleSnapshot {
    static func brief() async -> [String: Any] {
        let status = await ControlSnapshot.status()
        let items = oracleItems()
        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "mode": "deterministic-local",
            "brief": briefLines(status: status, items: items)
        ]
    }

    static func items() async -> [String: Any] {
        [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "mode": "deterministic-local",
            "items": oracleItems()
        ]
    }

    static func markdown() async -> String {
        let briefPayload = await brief()
        let digestPayload = await OracleDigestSnapshot.digest()
        let valuePayload = await ValueBriefSnapshot.brief()
        let focusPayload = await FocusSnapshot.focus()
        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let brief = (briefPayload["brief"] as? [String]) ?? []
        let digestSections = (digestPayload["sections"] as? [[String: Any]]) ?? []
        let actions = (digestPayload["actions"] as? [String]) ?? []
        let questions = (digestPayload["questions"] as? [String]) ?? []
        let drivers = (valuePayload["drivers"] as? [[String: Any]]) ?? []
        let decide = digestSections.first { ($0["id"] as? String) == "decide" }
        let avoid = digestSections.first { ($0["id"] as? String) == "avoid" }
        let test = digestSections.first { ($0["id"] as? String) == "test" }
        let create = digestSections.first { ($0["id"] as? String) == "create" }
        let focusTitle = focus["title"] as? String ?? digestPayload["headline"] as? String ?? "Start with the strongest current signal"
        let project = focus["project"] as? String ?? create?["project"] as? String ?? "General Brain"
        let agentTask = create?["detail"] as? String ?? drivers.first { ($0["id"] as? String) == "artifact" }?["detail"] as? String ?? "Create one durable artifact from the current focus."

        var lines: [String] = [
            "# Terminal Brain Oracle Brief",
            "",
            "Generated: \(briefPayload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Direct Read",
            "",
            "\(digestPayload["headline"] as? String ?? "Notice \(focusTitle)")",
            "",
            "\(digestPayload["thesis"] as? String ?? "Use the next block to produce one concrete artifact and commit the outcome.")",
            "",
            "## Do This Next",
            ""
        ]

        for (index, action) in actions.prefix(3).enumerated() {
            lines.append("\(index + 1). \(action)")
        }
        if actions.isEmpty {
            lines.append("1. Start Work for \(project).")
            lines.append("2. Build or attach a context pack before handing work to an agent.")
            lines.append("3. Commit the outcome when the artifact exists.")
        }

        lines.append("")
        lines.append("## What You May Be Missing")
        lines.append("")
        lines.append("- Decision: \(decide?["title"] as? String ?? "No unresolved decision visible")")
        lines.append("- Avoid: \(avoid?["title"] as? String ?? "Avoid collecting signals without closure")")
        lines.append("- Question: \(avoid?["question"] as? String ?? decide?["question"] as? String ?? "What am I avoiding because it is ambiguous or annoying?")")
        lines.append("")
        lines.append("## Cheap Test")
        lines.append("")
        lines.append("- \(test?["title"] as? String ?? "No idea test visible")")
        lines.append("- \(test?["question"] as? String ?? "What cheap test would prove this is worth more attention?")")
        lines.append("")
        lines.append("## Agent Handoff")
        lines.append("")
        lines.append("- Project: \(project)")
        lines.append("- Task: \(agentTask)")
        lines.append("- Prompt: Copy Agent Prompt or Start Here, attach the latest context pack, and require one concrete artifact.")
        lines.append("- Done means: artifact exists, evidence is named, and `/outcomes/commit` or `terminal_brain_commit_outcome` records the result.")

        if !questions.isEmpty {
            lines.append("")
            lines.append("## Questions To Ask")
            lines.append("")
            for question in questions.prefix(5) {
                lines.append("- \(question)")
            }
        }

        if !brief.isEmpty {
            lines.append("")
            lines.append("## Supporting Signals")
            lines.append("")
            for line in brief {
                lines.append("- \(line)")
            }
        }

        lines.append("")
        lines.append("## Guardrail")
        lines.append("")
        lines.append("- This artifact is read-only and does not launch, foreground, quit, kill, or control other apps.")

        return lines.joined(separator: "\n")
    }

    static func ask(question: String) async -> [String: Any] {
        let status = await ControlSnapshot.status()
        let items = oracleItems()
        let retrieval = await missionSearch(question: question)
        let localAnswer = answer(question: question, status: status, items: items)
        let synthesis = await missionSynthesis(
            question: question,
            status: status,
            items: Array(items.prefix(8)),
            retrieval: retrieval,
            localAnswer: localAnswer
        )
        let answerText: String
        let mode: String
        if let synthesis, !synthesis.isEmpty {
            answerText = synthesis
            mode = "mission-synthesis"
        } else if !retrieval.isEmpty {
            answerText = retrievalAnswer(question: question, localAnswer: localAnswer, retrieval: retrieval)
            mode = "mission-retrieval"
        } else {
            answerText = localAnswer
            mode = "deterministic-local"
        }
        return [
            "ok": true,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "mode": mode,
            "question": question,
            "answer": answerText,
            "supportingItems": Array(items.prefix(5)),
            "citations": citations(from: retrieval),
            "retrieval": retrieval,
            "suggestedActions": [
                "Build a context pack for the strongest surfaced item",
                "Commit useful Oracle answers into Obsidian",
                "Run sync after durable notes change",
                "Use Mission Control for heavier synthesis"
            ]
        ]
    }

    static func commit(title: String, content: String, question: String, source: String, project: String, tags: [String], reviewStatus: String = "new") -> [String: Any] {
        let directory = URL(fileURLWithPath: Paths.workspace).appendingPathComponent("Oracle Inbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let fileSafeTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
            let safeTitle = slug(from: title)
            let fileURL = directory.appendingPathComponent("\(fileSafeTimestamp)-\(safeTitle.isEmpty ? "oracle-read" : safeTitle).md")
            var mergedTags = ["terminal-brain", "oracle"]
            mergedTags.append(contentsOf: tags.map { slug(from: $0) }.filter { !$0.isEmpty })
            mergedTags = Array(Set(mergedTags)).sorted()
            let tagLines = mergedTags.map { "  - \($0)" }.joined(separator: "\n")
            let questionBlock = question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n## Question\n\n\(question.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            let resolvedProject = project.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(ProjectSnapshot.projectName(from: "\(title) \(question) \(content) \(tags.joined(separator: " "))"))
            let allowedStatuses = ["new", "accepted", "linked", "delegated", "dismissed"]
            let resolvedStatus = allowedStatuses.contains(reviewStatus) ? reviewStatus : "new"
            let body = """
            ---
            type: oracle_commit
            source: \(source)
            project: \(resolvedProject)
            created: \(timestamp)
            reviewStatus: \(resolvedStatus)
            tags:
            \(tagLines)
            ---

            # \(title)
            \(questionBlock)
            ## Read

            \(content)

            ## Follow Up

            - [ ] Review and link this note to the relevant project or daily note.
            - [ ] Run Terminal Brain sync after edits are final.
            """
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
            return [
                "ok": true,
                "path": fileURL.path,
                "title": title,
                "project": resolvedProject,
                "reviewStatus": resolvedStatus,
                "tags": mergedTags,
                "created": timestamp
            ]
        } catch {
            return [
                "ok": false,
                "error": error.localizedDescription
            ]
        }
    }

    static func commits() -> [String: Any] {
        try? FileManager.default.createDirectory(atPath: Paths.oracleInbox, withIntermediateDirectories: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: Paths.oracleInbox),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ["items": []]
        }

        let items: [[String: Any]] = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> (Date, [String: Any])? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let parsed = parseCommit(text)
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let created = parsed.created.flatMap { ISO8601DateFormatter().date(from: $0) } ?? modified
                return (
                    created,
                    [
                        "id": url.path,
                        "title": parsed.title.isEmpty ? url.deletingPathExtension().lastPathComponent : parsed.title,
                        "question": parsed.question,
                        "preview": parsed.preview,
                        "status": parsed.frontmatter["reviewStatus"] ?? parsed.frontmatter["status"] ?? "new",
                        "project": (parsed.frontmatter["project"] ?? "").ifEmpty(ProjectSnapshot.projectName(from: "\(parsed.title) \(parsed.question) \(parsed.preview) \(parsed.tags.joined(separator: " "))")),
                        "source": parsed.frontmatter["source"] ?? "Oracle Inbox",
                        "created": ISO8601DateFormatter().string(from: created),
                        "path": url.path,
                        "tags": parsed.tags
                    ]
                )
            }
            .sorted { $0.0 > $1.0 }
            .map { $0.1 }

        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "items": items
        ]
    }

    static func setReviewStatus(id: String, status: String) -> [String: Any] {
        let allowed = ["new", "accepted", "linked", "delegated", "dismissed"]
        guard allowed.contains(status) else {
            return ["ok": false, "error": "Invalid status", "allowed": allowed]
        }
        let standardizedInbox = (Paths.oracleInbox as NSString).standardizingPath
        let standardizedPath = (id as NSString).standardizingPath
        guard standardizedPath.hasPrefix(standardizedInbox), standardizedPath.hasSuffix(".md") else {
            return ["ok": false, "error": "Commit id must be a note path inside the Oracle Inbox"]
        }

        let url = URL(fileURLWithPath: standardizedPath)
        guard var text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["ok": false, "error": "Unable to read Oracle commit"]
        }

        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            var frontmatter = String(text[..<end.lowerBound])
            let remainder = String(text[end.upperBound...])
            let lines = frontmatter.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var replaced = false
            let nextLines = lines.map { line -> String in
                if line.hasPrefix("reviewStatus:") {
                    replaced = true
                    return "reviewStatus: \(status)"
                }
                return line
            }
            frontmatter = nextLines.joined(separator: "\n")
            if !replaced {
                frontmatter += "\nreviewStatus: \(status)"
            }
            text = "\(frontmatter)\n---\n\(remainder)"
        } else {
            text = """
            ---
            reviewStatus: \(status)
            ---

            \(text)
            """
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return [
                "ok": true,
                "id": standardizedPath,
                "status": status
            ]
        } catch {
            return ["ok": false, "error": error.localizedDescription]
        }
    }

    private static func oracleItems() -> [[String: Any]] {
        var output: [[String: Any]] = [
            [
                "id": "oracle-review-queue",
                "title": "Oracle Review Queue",
                "detail": "Ask and commit now work. The next layer is a review surface that turns committed reads into linked decisions, project notes, and daily priorities.",
                "kind": "opportunity",
                "source": "Current app",
                "confidence": "High",
                "symbol": "tray.and.arrow.down.fill",
                "path": "\(Paths.workspace)/Oracle Inbox"
            ]
        ]
        for pack in recentContextPackDocuments(limit: 8) {
            output.append([
                "id": "context-\(pack.url.lastPathComponent)",
                "title": contextPackTitle(from: pack.url),
                "detail": contextPackPreview(from: pack.text),
                "kind": "opportunity",
                "source": "Context pack",
                "confidence": "High",
                "symbol": "shippingbox.fill",
                "path": pack.url.path
            ])
        }

        let agent = CommandRunner.readJSON(Paths.agentHistoryStatsJSON)
        let records = agent["records"] as? Int ?? 0
        let sessions = agent["sessions"] as? Int ?? 0
        if records > 0 {
            output.append([
                "id": "agent-history",
                "title": "Agent work memory",
                "detail": "\(records) derived Codex/Claude records across \(sessions) sessions are available for continuity.",
                "kind": "bubbling",
                "source": "Agent histories",
                "confidence": "Medium",
                "symbol": "bubble.left.and.text.bubble.right",
                "path": Paths.agentHistoryStatsJSON
            ])
        }

        output.append(contentsOf: extractedItems(limit: 14))
        return dedupe(output).prefix(18).map { $0 }
    }

    private static func briefLines(status: [String: Any], items: [[String: Any]]) -> [String] {
        let indexes = status["indexes"] as? [String: Any] ?? [:]
        let promptSafe = status["promptSafe"] as? Bool ?? false
        let top = items.first?["title"] as? String ?? "no surfaced item yet"
        let openLoop = items.first { ($0["kind"] as? String) == "openLoop" }?["title"] as? String
        return [
            "Durable memory is active: \(indexes["obsidianNotes"] ?? 0) notes, \(indexes["entities"] ?? 0) entities, and \(indexes["agentRecords"] ?? 0) agent-memory records.",
            "The strongest current signal is \(top).",
            promptSafe ? "Permission posture is quiet: prompt-prone Apple Notes and Drafts bridges are not auto-running." : "One or more prompt-prone bridge is active; review source policy before automation.",
            openLoop.map { "The open loop to resolve first is \($0)." } ?? "No urgent open loop was detected in the current local scan."
        ]
    }

    private static func answer(question: String, status: [String: Any], items: [[String: Any]]) -> String {
        let query = question.lowercased()
        let openLoop = items.first { ($0["kind"] as? String) == "openLoop" }?["title"] as? String
        let idea = items.first { ["idea", "opportunity"].contains($0["kind"] as? String ?? "") }?["title"] as? String
        if query.contains("missing") || query.contains("consider") {
            return "What may be missing is \(openLoop ?? "a clearly promoted next action"). The adjacent idea to revisit is \(idea ?? "the latest context pack"). Treat the surfaced cards as review candidates, then promote the useful ones into Obsidian so they become durable memory."
        }
        if query.contains("today") || query.contains("next") || query.contains("work") {
            return "Use \(idea ?? "the freshest context pack") as the working frame. Build a narrow context pack, delegate only the bounded implementation, then write the outcome back into Obsidian."
        }
        if query.contains("safe") || query.contains("permission") || query.contains("prompt") {
            let promptSafe = status["promptSafe"] as? Bool ?? false
            return promptSafe ? "The system is prompt-safe right now: Apple Notes and Drafts bridges are off and the hourly sync agent is unloaded." : "Prompt safety is degraded. Review Apple Notes, Drafts, and LaunchAgent state before enabling automation."
        }
        return items.prefix(4).map {
            let kind = $0["kind"] as? String ?? "signal"
            let title = $0["title"] as? String ?? "Untitled"
            let detail = $0["detail"] as? String ?? ""
            return "\(kind): \(title). \(detail)"
        }.joined(separator: "\n\n")
    }

    private static func missionSearch(question: String) async -> [[String: Any]] {
        async let brain = missionSearchEndpoint(path: "/api/brain/search", label: "Mission Brain", question: question, limit: 3)
        async let edge = missionSearchEndpoint(path: "/api/edge-brain/search", label: "Edge Brain", question: question, limit: 4)
        async let knowledge = missionSearchEndpoint(path: "/api/knowledge/search", label: "Knowledge", question: question, limit: 3)

        let combined = await brain + edge + knowledge
        return dedupe(combined).prefix(8).map { $0 }
    }

    private static func missionSearchEndpoint(path: String, label: String, question: String, limit: Int) async -> [[String: Any]] {
        guard var components = URLComponents(url: Paths.missionURL, resolvingAgainstBaseURL: false) else {
            return []
        }
        components.path = path
        components.queryItems = [URLQueryItem(name: "q", value: question)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["available"] as? Bool != false,
                  let results = json["results"] as? [[String: Any]] else {
                return []
            }
            return results.prefix(limit).map { item in
                normalizedMissionResult(item, endpoint: label)
            }
        } catch {
            return []
        }
    }

    private static func missionSynthesis(
        question: String,
        status: [String: Any],
        items: [[String: Any]],
        retrieval: [[String: Any]],
        localAnswer: String
    ) async -> String? {
        guard !retrieval.isEmpty else { return nil }
        guard var components = URLComponents(url: Paths.missionURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/api/workbench/chat"
        guard let url = components.url else { return nil }

        let payload: [String: Any] = [
            "provider": "gptoss",
            "model": "qwen3.6-27b",
            "temperature": 0.2,
            "max_tokens": 520,
            "context_bundle": missionContextBundle(
                question: question,
                status: status,
                items: items,
                retrieval: retrieval,
                localAnswer: localAnswer
            ),
            "messages": [
                [
                    "role": "user",
                    "content": """
                    Answer as Terminal Brain's Oracle for John. Be specific, grounded in the supplied context, and concise.
                    Treat the Current Terminal Brain implementation section as authoritative over older retrieved context.

                    Question: \(question)

                    Format:
                    - Direct read
                    - Why this matters
                    - Next 3 moves
                    """
                ]
            ]
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "X-Mission-Request")
            request.setValue(missionOrigin(), forHTTPHeaderField: "Origin")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            let stripped = stripReasoning(content).trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? nil : stripped
        } catch {
            return nil
        }
    }

    private static func missionContextBundle(
        question: String,
        status: [String: Any],
        items: [[String: Any]],
        retrieval: [[String: Any]],
        localAnswer: String
    ) -> String {
        let indexes = status["indexes"] as? [String: Any] ?? [:]
        let mission = status["mission"] as? [String: Any] ?? [:]
        let promptSafe = status["promptSafe"] as? Bool ?? false

        var lines: [String] = [
            "Question: \(question)",
            "",
            "System posture:",
            "- Obsidian notes: \(indexes["obsidianNotes"] ?? 0)",
            "- Entities: \(indexes["entities"] ?? 0)",
            "- Agent memory records: \(indexes["agentRecords"] ?? 0)",
            "- Mission points: \(mission["points"] ?? 0)",
            "- Prompt-safe: \(promptSafe ? "yes" : "no")",
            "",
            "Current Terminal Brain implementation:",
            "- Native macOS app with local control API on http://127.0.0.1:8765.",
            "- Current API routes include /now/markdown, /start-here/markdown, /value-proof/markdown, /value-brief/markdown, /oracle-digest/markdown, /handoff/markdown, /agent-prompt/markdown, /outcomes/commit, /context-packs/latest/markdown, /radar, /sources, /permissions, /oracle/ask, /oracle/commit, /sync, and /start-work.",
            "- Oracle ask already combines local deterministic signals, Mission retrieval, Mission workbench synthesis, citations, supporting items, and fallback behavior.",
            "- Oracle commit can write synthesized decisions and outcomes into the Obsidian-backed Oracle Inbox.",
            "- MCP proxy can call Terminal Brain status, setup, focus, blindspots, blindspot ask/commit/action, operator deck, operator deck action, radar, radar triage, sources, briefing, permissions, sync, start work, oracle brief, oracle items, oracle ask, oracle commit, and oracle review status.",
            "- Do not describe these implemented capabilities as missing. Recommend what should come after them.",
            "",
            "Local deterministic read:",
            localAnswer.prefixString(maxLength: 1200),
            "",
            "Local Oracle cards:"
        ]

        for item in items.prefix(8) {
            let title = item["title"] as? String ?? "Untitled"
            let kind = item["kind"] as? String ?? "signal"
            let source = item["source"] as? String ?? "local"
            let detail = item["detail"] as? String ?? ""
            lines.append("- [\(kind)] \(title) (\(source)): \(detail.prefixString(maxLength: 420))")
        }

        lines.append("")
        lines.append("Mission retrieval:")
        for result in retrieval.prefix(8) {
            let title = result["title"] as? String ?? "Untitled"
            let source = result["source"] as? String ?? result["endpoint"] as? String ?? "Mission"
            let reference = result["reference"] as? String ?? ""
            let text = result["text"] as? String ?? ""
            lines.append("- \(title) [\(source)] \(reference): \(text.prefixString(maxLength: 700))")
        }

        return lines.joined(separator: "\n").prefixString(maxLength: 9000)
    }

    private static func retrievalAnswer(question: String, localAnswer: String, retrieval: [[String: Any]]) -> String {
        let surfaced = retrieval.prefix(4).map { result in
            let title = result["title"] as? String ?? "Untitled"
            let source = result["source"] as? String ?? result["endpoint"] as? String ?? "Mission"
            let text = result["text"] as? String ?? ""
            return "- \(title) (\(source)): \(text.prefixString(maxLength: 220))"
        }.joined(separator: "\n")

        return """
        \(localAnswer)

        Mission retrieval also surfaced:
        \(surfaced)

        Treat these as grounding references, then ask again when the Mission synthesis lane is available for a more opinionated read.
        """
    }

    private static func normalizedMissionResult(_ item: [String: Any], endpoint: String) -> [String: Any] {
        let title = item["title"] as? String ?? item["record_id"] as? String ?? "Untitled"
        let reference = item["reference"] as? String ?? item["path"] as? String ?? item["source_file"] as? String ?? ""
        let source = item["source_label"] as? String ?? item["source"] as? String ?? endpoint
        let score: Any = item["score"] ?? 0
        let text = item["text"] as? String ?? ""
        return [
            "id": item["record_id"] as? String ?? "\(endpoint)-\(title)-\(reference)",
            "endpoint": endpoint,
            "source": source,
            "title": title.prefixString(maxLength: 140),
            "reference": reference.prefixString(maxLength: 220),
            "score": score,
            "text": text.prefixString(maxLength: 900)
        ]
    }

    private static func citations(from retrieval: [[String: Any]]) -> [[String: Any]] {
        retrieval.prefix(6).map { result in
            [
                "title": result["title"] as? String ?? "Untitled",
                "source": result["source"] as? String ?? result["endpoint"] as? String ?? "Mission",
                "reference": result["reference"] as? String ?? "",
                "score": result["score"] ?? 0
            ]
        }
    }

    private static func missionOrigin() -> String {
        guard let components = URLComponents(url: Paths.missionURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let host = components.host else {
            return Paths.missionURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let port = components.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func stripReasoning(_ text: String) -> String {
        var output = text
        while let start = output.range(of: "<think>", options: .caseInsensitive),
              let end = output.range(of: "</think>", options: .caseInsensitive) {
            output.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return output
    }

    private static func extractedItems(limit: Int) -> [[String: Any]] {
        let markers: [(kind: String, needle: String, symbol: String)] = [
            ("openLoop", "todo", "checklist"),
            ("openLoop", "next", "arrow.right.circle"),
            ("openLoop", "waiting", "hourglass"),
            ("openLoop", "blocked", "exclamationmark.octagon"),
            ("decision", "decision", "checkmark.seal"),
            ("decision", "decided", "checkmark.seal"),
            ("idea", "idea", "lightbulb"),
            ("idea", "maybe", "sparkle.magnifyingglass"),
            ("opportunity", "opportunity", "target"),
            ("bubbling", "should", "bubble.left.and.exclamationmark.bubble.right")
        ]

        var output: [[String: Any]] = []
        for pack in recentContextPackDocuments(limit: 8) {
            let lines = pack.text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
            for line in lines {
                let lowered = line.lowercased()
                guard let marker = markers.first(where: { lowered.contains($0.needle) }) else { continue }
                output.append([
                    "id": "line-\(pack.url.lastPathComponent)-\(output.count)",
                    "title": oracleTitle(from: line),
                    "detail": line.prefixString(maxLength: 260),
                    "kind": marker.kind,
                    "source": pack.url.deletingPathExtension().lastPathComponent,
                    "confidence": "Heuristic",
                    "symbol": marker.symbol,
                    "path": pack.url.path
                ])
                if output.count >= limit {
                    return output
                }
            }
        }
        return output
    }

    private static func recentContextPackDocuments(limit: Int) -> [(url: URL, text: String)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: Paths.contextPacks),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> (Date, URL)? in
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return nil
                }
                return (modified, url)
            }
            .sorted { $0.0 > $1.0 }
            .prefix(limit)
            .compactMap { pair in
                let url = pair.1
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    return nil
                }
                return (url, text)
            }
    }

    private static func contextPackTitle(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let parts = base.split(separator: "-", omittingEmptySubsequences: true)
        let slug = parts.dropFirst(6).joined(separator: " ")
        return slug.isEmpty ? base : slug.capitalized
    }

    private static func contextPackPreview(from text: String) -> String {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
        return lines.prefix(2).joined(separator: " ").prefixString(maxLength: 220)
    }

    private static func oracleTitle(from line: String) -> String {
        var cleaned = line
            .replacingOccurrences(of: "- [ ]", with: "")
            .replacingOccurrences(of: "- [x]", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = cleaned.firstIndex(of: ":"), cleaned.distance(from: cleaned.startIndex, to: colon) < 36 {
            cleaned = String(cleaned[cleaned.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.prefixString(maxLength: 72)
    }

    private static func parseCommit(_ text: String) -> (frontmatter: [String: String], tags: [String], title: String, question: String, preview: String, created: String?) {
        var frontmatter: [String: String] = [:]
        var tags: [String] = []
        var body = text

        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            let rawFrontmatter = String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])
            body = String(text[end.upperBound...])
            var activeKey = ""
            for rawLine in rawFrontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("-"), activeKey == "tags" {
                    var tag = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if tag.hasPrefix("-") {
                        tag.removeFirst()
                    }
                    tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tag.isEmpty { tags.append(tag) }
                    continue
                }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                activeKey = key
                if key != "tags" {
                    frontmatter[key] = value
                }
            }
        }

        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let title = lines.first { $0.hasPrefix("# ") }?
            .replacingOccurrences(of: "# ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let question = sectionText(named: "Question", in: lines).prefixString(maxLength: 240)
        let read = sectionText(named: "Read", in: lines)
        let previewSource = read.isEmpty ? lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }.joined(separator: " ") : read
        return (
            frontmatter,
            tags,
            title,
            question,
            previewSource.prefixString(maxLength: 260),
            frontmatter["created"]
        )
    }

    private static func sectionText(named section: String, in lines: [String]) -> String {
        guard let start = lines.firstIndex(where: { $0 == "## \(section)" }) else { return "" }
        var output: [String] = []
        for line in lines.dropFirst(start + 1) {
            if line.hasPrefix("## ") { break }
            if !line.isEmpty { output.append(line) }
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func slug(from text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(10)
            .joined(separator: "-")
    }

    private static func dedupe(_ items: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var output: [[String: Any]] = []
        for item in items {
            let key = (item["title"] as? String ?? "").lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(item)
        }
        return output
    }
}

enum ProjectSnapshot {
    static func projects() -> [String: Any] {
        let commits = (OracleSnapshot.commits()["items"] as? [[String: Any]]) ?? []
        let packs = contextPacks(limit: 40)
        var buckets: [String: [String: Any]] = [:]

        func ensure(_ name: String) -> String {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("General Brain")
            let id = projectID(from: cleanName)
            if buckets[id] == nil {
                buckets[id] = [
                    "id": id,
                    "name": cleanName,
                    "contextPacks": [],
                    "oracleCommits": [],
                    "openLoops": [],
                    "decisions": []
                ]
            }
            return id
        }

        for pack in packs {
            let name = projectName(from: "\(pack["title"] ?? "") \(pack["detail"] ?? "")")
            let id = ensure(name)
            var existing = buckets[id]?["contextPacks"] as? [[String: Any]] ?? []
            existing.append(pack)
            buckets[id]?["contextPacks"] = existing
        }

        for commit in commits {
            let name = (commit["project"] as? String ?? "").ifEmpty(projectName(from: "\(commit["title"] ?? "") \(commit["question"] ?? "") \(commit["preview"] ?? "") \((commit["tags"] as? [String] ?? []).joined(separator: " "))"))
            let id = ensure(name)
            var existing = buckets[id]?["oracleCommits"] as? [[String: Any]] ?? []
            existing.append(commit)
            buckets[id]?["oracleCommits"] = existing
        }

        var items: [[String: Any]] = []
        for (id, bucket) in buckets {
            let context = bucket["contextPacks"] as? [[String: Any]] ?? []
            let projectCommits = bucket["oracleCommits"] as? [[String: Any]] ?? []
            let name = bucket["name"] as? String ?? "General Brain"
            let signalCount = context.count + projectCommits.count
            let delegated = projectCommits.filter { ($0["status"] as? String) == "delegated" }.count
            let lastActivity = latestDateString(context: context, commits: projectCommits)
            items.append([
                "id": id,
                "name": name,
                "summary": "\(context.count) context pack\(context.count == 1 ? "" : "s") and \(projectCommits.count) committed read\(projectCommits.count == 1 ? "" : "s") are attached to \(name).",
                "recommendedAction": recommendedAction(name: name, commits: projectCommits, context: context),
                "signalCount": signalCount,
                "delegatedCount": delegated,
                "lastActivity": lastActivity,
                "symbol": projectSymbol(for: name),
                "contextPacks": Array(context.prefix(6)),
                "oracleCommits": Array(projectCommits.prefix(8))
            ])
        }

        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "items": items.sorted {
                (($0["signalCount"] as? Int) ?? 0) > (($1["signalCount"] as? Int) ?? 0)
            }
        ]
    }

    static func markdown() -> String {
        let payload = projects()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        var lines: [String] = [
            "# Terminal Brain Project Memory",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "Use this as the current map of active work surfaces, durable context, and recommended project actions.",
            ""
        ]

        for project in items.prefix(10) {
            lines.append("## \(project["name"] as? String ?? "Project")")
            lines.append("- Summary: \(project["summary"] as? String ?? "")")
            lines.append("- Recommended action: \(project["recommendedAction"] as? String ?? "")")
            lines.append("- Signal count: \(project["signalCount"] as? Int ?? 0)")
            lines.append("- Delegated reads: \(project["delegatedCount"] as? Int ?? 0)")
            if let lastActivity = project["lastActivity"] as? String, !lastActivity.isEmpty {
                lines.append("- Last activity: \(lastActivity)")
            }

            let context = (project["contextPacks"] as? [[String: Any]]) ?? []
            if !context.isEmpty {
                lines.append("- Fresh context:")
                for pack in context.prefix(3) {
                    lines.append("  - \(pack["title"] as? String ?? "Context pack"): \(pack["detail"] as? String ?? "")")
                    if let path = pack["path"] as? String, !path.isEmpty {
                        lines.append("    Path: \(path)")
                    }
                }
            }

            let commits = (project["oracleCommits"] as? [[String: Any]]) ?? []
            if !commits.isEmpty {
                lines.append("- Oracle reads:")
                for commit in commits.prefix(3) {
                    lines.append("  - \(commit["title"] as? String ?? "Oracle read") (\(commit["status"] as? String ?? "new"))")
                    if let path = commit["path"] as? String, !path.isEmpty {
                        lines.append("    Path: \(path)")
                    }
                }
            }
            lines.append("")
        }

        if items.isEmpty {
            lines.append("- No project memory pages are available yet.")
        }

        return lines.joined(separator: "\n")
    }

    private static func contextPacks(limit: Int) -> [[String: Any]] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: Paths.contextPacks),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> (Date, [String: Any])? in
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return nil
                }
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return (
                    modified,
                    [
                        "id": "context-\(url.lastPathComponent)",
                        "title": contextPackTitle(from: url),
                        "detail": contextPackPreview(from: text),
                        "path": url.path,
                        "modifiedAt": ISO8601DateFormatter().string(from: modified)
                    ]
                )
            }
            .sorted { $0.0 > $1.0 }
            .prefix(limit)
            .map { $0.1 }
    }

    static func projectName(from text: String) -> String {
        let lowered = text.lowercased()
        let known: [(needle: String, name: String)] = [
            ("terminal brain", "Terminal Brain"),
            ("mission control", "Mission Control"),
            ("centrexai", "centrexAI"),
            ("centrex ai", "centrexAI"),
            ("franklin", "Franklin Systems"),
            ("drafts", "Drafts"),
            ("apple notes", "Apple Notes"),
            ("obsidian", "Obsidian"),
            ("rewst", "Rewst"),
            ("mcp", "MCP Platform")
        ]
        if let match = known.first(where: { lowered.contains($0.needle) }) {
            return match.name
        }
        let words = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .filter { !["context", "pack", "oracle", "brain", "work", "with", "from", "local", "memory", "generated", "start"].contains($0) }
        return words.prefix(2).joined(separator: " ").capitalized.ifEmpty("General Brain")
    }

    private static func projectID(from name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .ifEmpty("general-brain")
    }

    private static func projectSymbol(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("terminal") { return "terminal.fill" }
        if lowered.contains("mission") { return "display" }
        if lowered.contains("centrex") { return "building.2.fill" }
        if lowered.contains("draft") { return "square.and.pencil" }
        if lowered.contains("notes") { return "note.text" }
        if lowered.contains("obsidian") { return "doc.text.magnifyingglass" }
        if lowered.contains("mcp") { return "antenna.radiowaves.left.and.right" }
        return "folder.fill"
    }

    private static func recommendedAction(name: String, commits: [[String: Any]], context: [[String: Any]]) -> String {
        if let delegated = commits.first(where: { ($0["status"] as? String) == "delegated" }) {
            return "Turn delegated read into a Start Work pack: \(delegated["title"] as? String ?? name)."
        }
        if let unread = commits.first(where: { ($0["status"] as? String) == "new" }) {
            return "Review and classify the newest Oracle read: \(unread["title"] as? String ?? name)."
        }
        if let fresh = context.first {
            return "Use the freshest context pack as the working frame: \(fresh["title"] as? String ?? name)."
        }
        return "Ask Oracle what changed for \(name), then commit the useful read."
    }

    private static func latestDateString(context: [[String: Any]], commits: [[String: Any]]) -> String {
        let values = context.compactMap { $0["modifiedAt"] as? String } + commits.compactMap { $0["created"] as? String }
        return values.sorted().last ?? ""
    }

    private static func contextPackTitle(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let parts = base.split(separator: "-", omittingEmptySubsequences: true)
        let slug = parts.dropFirst(6).joined(separator: " ")
        return slug.isEmpty ? base : slug.capitalized
    }

    private static func contextPackPreview(from text: String) -> String {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
        return lines.prefix(2).joined(separator: " ").prefixString(maxLength: 220)
    }
}

enum TodaySnapshot {
    static func today() async -> [String: Any] {
        let projects = (ProjectSnapshot.projects()["items"] as? [[String: Any]]) ?? []
        let commits = (OracleSnapshot.commits()["items"] as? [[String: Any]]) ?? []
        let radarPayload = await RadarSnapshot.radar()
        let radar = (radarPayload["items"] as? [[String: Any]]) ?? []
        var commands: [[String: Any]] = []

        for item in radar.prefix(2) {
            commands.append(command(
                id: "radar-\(item["id"] ?? "")",
                title: item["title"] as? String ?? "Radar signal",
                detail: item["detail"] as? String ?? "",
                priority: item["urgency"] as? String ?? "Next",
                action: item["action"] as? String ?? "Open Radar",
                project: item["project"] as? String ?? "",
                symbol: item["symbol"] as? String ?? "scope",
                query: item["query"] as? String ?? ""
            ))
        }

        for commit in commits.filter({ ($0["status"] as? String) == "delegated" }).prefix(3) {
            commands.append(command(
                id: "delegated-\(commit["id"] ?? "")",
                title: "Execute delegated read",
                detail: commit["title"] as? String ?? "Delegated Oracle read",
                priority: "Now",
                action: "Start Work",
                project: commit["project"] as? String ?? "",
                symbol: "paperplane.fill",
                query: [commit["project"] as? String ?? "", commit["title"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " - ")
            ))
        }

        for commit in commits.filter({ ($0["status"] as? String) == "new" }).prefix(3) {
            commands.append(command(
                id: "review-\(commit["id"] ?? "")",
                title: "Review new Oracle read",
                detail: commit["preview"] as? String ?? "",
                priority: "Review",
                action: "Open Review",
                project: commit["project"] as? String ?? "",
                symbol: "tray.and.arrow.down.fill",
                query: commit["title"] as? String ?? ""
            ))
        }

        for project in projects.prefix(4) {
            commands.append(command(
                id: "project-\(project["id"] ?? "")",
                title: "Move \(project["name"] as? String ?? "Project") forward",
                detail: project["recommendedAction"] as? String ?? "",
                priority: ((project["delegatedCount"] as? Int) ?? 0) > 0 ? "Now" : "Next",
                action: "Open Project",
                project: project["name"] as? String ?? "",
                symbol: project["symbol"] as? String ?? "folder.fill",
                query: project["name"] as? String ?? ""
            ))
        }

        if commands.isEmpty {
            commands.append(command(
                id: "ask-oracle",
                title: "Ask what changed",
                detail: "No urgent queue is visible. Ask Oracle to surface the next useful move.",
                priority: "Start",
                action: "Ask Oracle",
                project: "General Brain",
                symbol: "sparkle.magnifyingglass",
                query: "What changed and what should I do first?"
            ))
        }

        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "commands": Array(commands.prefix(8)),
            "projects": projects,
            "reviewCount": commits.filter { ($0["status"] as? String) == "new" }.count,
            "delegatedCount": commits.filter { ($0["status"] as? String) == "delegated" }.count
        ]
    }

    static func markdown() async -> String {
        let payload = await today()
        let commands = (payload["commands"] as? [[String: Any]]) ?? []
        let projects = (payload["projects"] as? [[String: Any]]) ?? []
        var lines: [String] = [
            "# Terminal Brain Decision Lane",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "Use this as the ranked action queue. Prefer the first item unless new evidence changes the priority.",
            ""
        ]

        lines.append("## Ranked Decisions")
        for (index, command) in commands.prefix(8).enumerated() {
            lines.append("### \(index + 1). \(command["title"] as? String ?? "Decision")")
            lines.append("- Priority: \(command["priority"] as? String ?? "Next")")
            lines.append("- Action: \(command["action"] as? String ?? "Act")")
            lines.append("- Project: \(command["project"] as? String ?? "General Brain")")
            lines.append("- Detail: \(command["detail"] as? String ?? "")")
            if let query = command["query"] as? String, !query.isEmpty {
                lines.append("- Query: \(query)")
            }
            lines.append("")
        }
        if commands.isEmpty {
            lines.append("- No command items are available. Ask the Focus Oracle what changed.")
            lines.append("")
        }

        lines.append("## Project Signals")
        for project in projects.prefix(5) {
            lines.append("- \(project["name"] as? String ?? "Project"): \(project["recommendedAction"] as? String ?? "Open project memory.")")
        }
        if projects.isEmpty {
            lines.append("- No project memory pages are available yet.")
        }

        return lines.joined(separator: "\n")
    }

    private static func command(id: String, title: String, detail: String, priority: String, action: String, project: String, symbol: String, query: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "detail": detail,
            "priority": priority,
            "action": action,
            "project": project,
            "symbol": symbol,
            "query": query
        ]
    }
}

enum OperatorBriefSnapshot {
    static func brief() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let radarPayload = await RadarSnapshot.radar()
        let oraclePayload = await OracleSnapshot.items()
        let commitsPayload = OracleSnapshot.commits()
        let projectsPayload = ProjectSnapshot.projects()
        let setupPayload = await SetupSnapshot.setup()

        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let radar = (radarPayload["items"] as? [[String: Any]]) ?? []
        let oracleItems = (oraclePayload["items"] as? [[String: Any]]) ?? []
        let commits = (commitsPayload["items"] as? [[String: Any]]) ?? []
        let projects = (projectsPayload["items"] as? [[String: Any]]) ?? []
        let setupSteps = (setupPayload["steps"] as? [[String: Any]]) ?? []

        let focusTitle = focus["title"] as? String ?? "Ask what changed"
        let focusProject = focus["project"] as? String ?? "General Brain"
        let focusDetail = focus["detail"] as? String ?? "No active signal is available yet."
        let focusReason = focus["reason"] as? String ?? "Run sync or ask Oracle to create a useful starting point."
        let focusAction = focus["action"] as? String ?? "Ask Oracle"
        let focusScore = focus["score"] as? Int ?? 0

        var items: [[String: Any]] = [
            item(
                id: "matters",
                label: "What matters",
                title: focusTitle,
                detail: focusDetail,
                action: focusAction,
                project: focusProject,
                symbol: focus["symbol"] as? String ?? "target",
                state: focus["state"] as? String ?? "Ready",
                query: focus["query"] as? String ?? ""
            ),
            item(
                id: "why",
                label: "Why it matters",
                title: focusScore > 0 ? "Signal score \(focusScore)" : "Top visible queue item",
                detail: focusReason,
                action: "Ask Oracle",
                project: focusProject,
                symbol: "list.bullet.clipboard",
                state: focus["state"] as? String ?? "Ready",
                query: "Why does \(focusTitle) matter right now?"
            )
        ]

        if let review = commits.first(where: { ($0["status"] as? String) == "new" }) {
            items.append(item(
                id: "missed-\(review["id"] as? String ?? "review")",
                label: "Do not miss",
                title: "Unreviewed Oracle read",
                detail: review["preview"] as? String ?? review["title"] as? String ?? "Review the newest committed read.",
                action: "Open Review",
                project: review["project"] as? String ?? "General Brain",
                symbol: "tray.and.arrow.down.fill",
                state: "Attention",
                query: review["title"] as? String ?? ""
            ))
        } else if let oracle = oracleItems.first {
            let title = oracle["title"] as? String ?? "Oracle surfaced item"
            items.append(item(
                id: "missed-\(oracle["id"] as? String ?? "oracle")",
                label: "Do not miss",
                title: title,
                detail: oracle["detail"] as? String ?? "Ask what changed and whether this matters.",
                action: "Ask Oracle",
                project: ProjectSnapshot.projectName(from: "\(title) \(oracle["detail"] ?? "")"),
                symbol: oracle["symbol"] as? String ?? "sparkle.magnifyingglass",
                state: "Ready",
                query: "What should I notice about \(title)?"
            ))
        } else if let warning = setupSteps.first(where: { ($0["state"] as? String) == "Attention" }) {
            items.append(item(
                id: "missed-\(warning["id"] as? String ?? "setup")",
                label: "Do not miss",
                title: warning["title"] as? String ?? "Setup item needs attention",
                detail: warning["detail"] as? String ?? "Review setup before trusting automation.",
                action: "Open System",
                project: "System",
                symbol: warning["symbol"] as? String ?? "exclamationmark.triangle.fill",
                state: "Attention",
                query: warning["title"] as? String ?? ""
            ))
        }

        if let delegated = commits.first(where: { ($0["status"] as? String) == "delegated" }) {
            let title = delegated["title"] as? String ?? "Delegated Oracle read"
            items.append(item(
                id: "artifact-\(delegated["id"] as? String ?? "delegated")",
                label: "Next artifact",
                title: "Build a handoff",
                detail: title,
                action: "Start Work",
                project: delegated["project"] as? String ?? "General Brain",
                symbol: "shippingbox.fill",
                state: "Running",
                query: [delegated["project"] as? String ?? "", title].filter { !$0.isEmpty }.joined(separator: " - ")
            ))
        } else if let project = projects.first {
            let name = project["name"] as? String ?? "Project memory"
            items.append(item(
                id: "artifact-\(project["id"] as? String ?? "project")",
                label: "Next artifact",
                title: name,
                detail: project["recommendedAction"] as? String ?? "Open the project memory page.",
                action: "Open Project",
                project: name,
                symbol: project["symbol"] as? String ?? "folder.fill",
                state: ((project["delegatedCount"] as? Int) ?? 0) > 0 ? "Running" : "Ready",
                query: name
            ))
        } else if let firstRadar = radar.first {
            items.append(item(
                id: "artifact-\(firstRadar["id"] as? String ?? "radar")",
                label: "Next artifact",
                title: "Turn signal into handoff",
                detail: firstRadar["reason"] as? String ?? "Build a focused context pack from the top signal.",
                action: firstRadar["action"] as? String ?? "Start Work",
                project: firstRadar["project"] as? String ?? "General Brain",
                symbol: firstRadar["symbol"] as? String ?? "scope",
                state: firstRadar["state"] as? String ?? "Ready",
                query: firstRadar["query"] as? String ?? ""
            ))
        }

        return [
            "generatedAt": generatedAt,
            "headline": "Do \(focusTitle)",
            "mode": "operator-brief",
            "items": Array(items.prefix(4))
        ]
    }

    static func markdown() async -> String {
        let payload = await brief()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        var lines: [String] = [
            "# Terminal Brain Operator Brief",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "\(payload["headline"] as? String ?? "Start with the top visible signal.")",
            ""
        ]

        for item in items {
            lines.append("## \(item["label"] as? String ?? "Signal"): \(item["title"] as? String ?? "Untitled")")
            lines.append("- Action: \(item["action"] as? String ?? "Act")")
            lines.append("- Project: \(item["project"] as? String ?? "General Brain")")
            if let detail = item["detail"] as? String, !detail.isEmpty {
                lines.append("- Detail: \(detail)")
            }
            if let query = item["query"] as? String, !query.isEmpty {
                lines.append("- Query: \(query)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func item(id: String, label: String, title: String, detail: String, action: String, project: String, symbol: String, state: String, query: String) -> [String: Any] {
        [
            "id": id,
            "label": label,
            "title": title,
            "detail": detail,
            "action": action,
            "project": project,
            "symbol": symbol,
            "state": state,
            "query": query
        ]
    }
}

enum ValueBriefSnapshot {
    static func brief() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let ideaPayload = await IdeaPulseSnapshot.ideas()
        let blindspotPayload = await BlindspotSnapshot.blindspots()
        let projectsPayload = ProjectSnapshot.projects()
        let todayPayload = await TodaySnapshot.today()

        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let ideas = (ideaPayload["items"] as? [[String: Any]]) ?? []
        let blindspots = (blindspotPayload["items"] as? [[String: Any]]) ?? []
        let projects = (projectsPayload["items"] as? [[String: Any]]) ?? []
        let commands = (todayPayload["commands"] as? [[String: Any]]) ?? []

        let focusTitle = focus["title"] as? String ?? "Ask what changed"
        let focusProject = focus["project"] as? String ?? "General Brain"
        let focusAction = focus["action"] as? String ?? "Ask Oracle"
        let focusReason = focus["reason"] as? String ?? focus["detail"] as? String ?? "No focus signal is available yet."
        let idea = ideas.first
        let blindspot = blindspots.first
        let project = projects.first

        let drivers = [
            driver(
                id: "focus",
                label: "Immediate value",
                title: focusTitle,
                detail: focusReason,
                action: focusAction,
                project: focusProject,
                symbol: focus["symbol"] as? String ?? "target",
                score: focus["score"] as? Int ?? 0,
                source: "Focus"
            ),
            driver(
                id: "idea",
                label: "Upside to test",
                title: idea?["title"] as? String ?? "No idea test visible",
                detail: idea?["nextPrompt"] as? String ?? "Capture or sync more material to surface an idea worth testing.",
                action: "Pressure Test",
                project: idea?["project"] as? String ?? "General Brain",
                symbol: idea?["symbol"] as? String ?? "lightbulb.fill",
                score: idea?["score"] as? Int ?? 0,
                source: "Idea Pulse"
            ),
            driver(
                id: "risk",
                label: "Risk to reduce",
                title: blindspot?["title"] as? String ?? "No strong blindspot visible",
                detail: blindspot?["question"] as? String ?? "Ask what is not represented in durable memory.",
                action: blindspot?["nextAction"] as? String ?? "Ask Oracle",
                project: blindspot?["project"] as? String ?? "General Brain",
                symbol: blindspot?["symbol"] as? String ?? "eye.fill",
                score: blindspot?["score"] as? Int ?? 0,
                source: "Blindspot Brief"
            ),
            driver(
                id: "artifact",
                label: "Artifact to create",
                title: project?["name"] as? String ?? commands.first?["title"] as? String ?? "Build a context pack",
                detail: project?["recommendedAction"] as? String ?? commands.first?["detail"] as? String ?? "Create one durable artifact from the current focus.",
                action: "Start Work",
                project: project?["name"] as? String ?? commands.first?["project"] as? String ?? "General Brain",
                symbol: project?["symbol"] as? String ?? "shippingbox.fill",
                score: project?["signalCount"] as? Int ?? 0,
                source: "Project Memory"
            )
        ]

        return [
            "generatedAt": generatedAt,
            "mode": "value-brief",
            "headline": "Do \(focusTitle)",
            "thesis": "The highest-value move is \(focusAction.lowercased()) for \(focusProject). It has an execution signal, an upside test, a risk check, and a next artifact path.",
            "drivers": drivers
        ]
    }

    static func markdown() async -> String {
        let payload = await brief()
        let drivers = (payload["drivers"] as? [[String: Any]]) ?? []
        var lines: [String] = [
            "# Terminal Brain Value Brief",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "\(payload["headline"] as? String ?? "Start with the top visible signal.")",
            "",
            "\(payload["thesis"] as? String ?? "")",
            ""
        ]

        for item in drivers {
            lines.append("## \(item["label"] as? String ?? "Value"): \(item["title"] as? String ?? "Untitled")")
            lines.append("- Action: \(item["action"] as? String ?? "Act")")
            lines.append("- Project: \(item["project"] as? String ?? "General Brain")")
            lines.append("- Source: \(item["source"] as? String ?? "")")
            lines.append("- Score: \(item["score"] as? Int ?? 0)")
            if let detail = item["detail"] as? String, !detail.isEmpty {
                lines.append("- Detail: \(detail)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func driver(id: String, label: String, title: String, detail: String, action: String, project: String, symbol: String, score: Int, source: String) -> [String: Any] {
        [
            "id": id,
            "label": label,
            "title": title,
            "detail": detail,
            "action": action,
            "project": project,
            "symbol": symbol,
            "score": score,
            "source": source
        ]
    }
}

enum NowSnapshot {
    static func now() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let title = focus["title"] as? String ?? "Start with the top visible signal"
        let action = focus["action"] as? String ?? "Act"
        let project = focus["project"] as? String ?? "General Brain"
        let reason = (focus["reason"] as? String ?? focus["detail"] as? String ?? "").ifEmpty("Use the top signal as the next work block unless newer evidence changes priority.")
        let query = (focus["query"] as? String ?? title).ifEmpty(title)
        let setup = await SetupSnapshot.setup()
        let steps = (setup["steps"] as? [[String: Any]]) ?? []
        let warningCount = steps.filter { ($0["state"] as? String ?? "").lowercased() == "warn" }.count
        let readiness = warningCount == 0 ? "ready" : "\(warningCount) setup item\(warningCount == 1 ? "" : "s") need attention"
        return [
            "generatedAt": generatedAt,
            "mode": "now",
            "bottomLine": "Do \(title).",
            "reason": reason,
            "focus": focus,
            "doThis": [
                [
                    "title": action,
                    "detail": "Do \(action.lowercased()) for \(project).",
                    "project": project,
                    "query": query
                ],
                [
                    "title": "Attach memory",
                    "detail": "Build or attach a context pack before handing deeper work to an agent.",
                    "project": project,
                    "query": query
                ],
                [
                    "title": "Commit outcome",
                    "detail": "Write what changed, why it matters, evidence, and the next action into durable memory.",
                    "project": project,
                    "query": ""
                ]
            ],
            "processTruth": [
                "api": "reachable at 127.0.0.1:8765",
                "appBackedTools": "ready while Terminal Brain remains open",
                "setupReadiness": readiness,
                "warningCount": warningCount,
                "guardrail": "read-only; does not launch, foreground, quit, kill, or control other apps"
            ],
            "closeLoop": [
                "api": "/outcomes/commit",
                "mcp": "terminal_brain_commit_outcome",
                "app": "Commit Outcome panel"
            ]
        ]
    }

    static func markdown() async -> String {
        let payload = await now()
        let focus = (payload["focus"] as? [String: Any]) ?? [:]
        let title = (payload["bottomLine"] as? String ?? "Start with the top visible signal.").replacingOccurrences(of: ".", with: "")
        let action = focus["action"] as? String ?? "Act"
        let project = focus["project"] as? String ?? "General Brain"
        let reason = payload["reason"] as? String ?? ""
        let query = (focus["query"] as? String ?? focus["title"] as? String ?? "").ifEmpty(focus["title"] as? String ?? "current focus")
        let processTruth = (payload["processTruth"] as? [String: Any]) ?? [:]
        let readiness = processTruth["setupReadiness"] as? String ?? "unknown"
        let oracle = await OracleSnapshot.markdown()
        let value = await ValueBriefSnapshot.markdown()

        return [
            "# Terminal Brain Now",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Bottom Line",
            "",
            "\(title).",
            "",
            reason,
            "",
            "## Do This",
            "",
            "1. \(action) for \(project).",
            "2. Build or attach a context pack for `\(query)` before handing deeper work to an agent.",
            "3. Commit the outcome with what changed, why it matters, evidence, and the next action.",
            "",
            "## Process Truth",
            "",
            "- API: reachable at 127.0.0.1:8765",
            "- App-backed tools: ready while Terminal Brain remains open",
            "- Setup readiness: \(readiness)",
            "- Guardrail: this artifact is read-only and does not launch, foreground, quit, kill, or control other apps.",
            "",
            "## Close Loop",
            "",
            "Use `/outcomes/commit`, `terminal_brain_commit_outcome`, or the app's Commit Outcome panel after useful work happens.",
            "",
            "---",
            "",
            demote(oracle),
            "",
            "---",
            "",
            demote(value),
        ].joined(separator: "\n")
    }

    private static func demote(_ markdown: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.hasPrefix("### ") { return "##### " + String(line.dropFirst(4)) }
                if line.hasPrefix("## ") { return "#### " + String(line.dropFirst(3)) }
                if line.hasPrefix("# ") { return "### " + String(line.dropFirst(2)) }
                return String(line)
            }
            .joined(separator: "\n")
    }
}

enum CleanupPlanSnapshot {
    static func markdown() async -> String {
        let script = "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/cleanup-plan.zsh"
        guard FileManager.default.fileExists(atPath: script) else {
            return [
                "# Terminal Brain Cleanup Plan",
                "",
                "The cleanup-plan script is not available at:",
                "",
                "```text",
                script,
                "```",
                "",
                "Open the TerminalBrain repo and run:",
                "",
                "```zsh",
                "make cleanup-plan",
                "```",
                "",
                "Guardrail: this API response did not launch, foreground, quit, kill, or control anything."
            ].joined(separator: "\n")
        }

        let result = await CommandRunner.run("/bin/zsh", [script])
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !output.isEmpty {
            return output
        }

        return [
            "# Terminal Brain Cleanup Plan",
            "",
            "Cleanup plan failed before completing.",
            "",
            "## Status",
            "",
            "- Exit: \(result.status)",
            "",
            "## Output",
            "",
            output.ifEmpty("(no stdout)"),
            "",
            "## Error",
            "",
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stderr)"),
            "",
            "## Guardrail",
            "",
            "- This API response did not launch, foreground, quit, kill, or control anything."
        ].joined(separator: "\n")
    }
}

enum FirstMinuteSnapshot {
    static func markdown() async -> String {
        let script = "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/first-minute.zsh"
        guard FileManager.default.fileExists(atPath: script) else {
            return [
                "# Terminal Brain First Minute",
                "",
                "The first-minute script is not available at:",
                "",
                "```text",
                script,
                "```",
                "",
                "Open the TerminalBrain repo and run:",
                "",
                "```zsh",
                "make first-minute",
                "```",
                "",
                "Guardrail: this API response did not launch, foreground, quit, kill, or control anything."
            ].joined(separator: "\n")
        }

        let result = await CommandRunner.run("/bin/zsh", [script])
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !output.isEmpty {
            return output
        }

        return [
            "# Terminal Brain First Minute",
            "",
            "First-minute artifact failed before completing.",
            "",
            "## Status",
            "",
            "- Exit: \(result.status)",
            "",
            "## Output",
            "",
            output.ifEmpty("(no stdout)"),
            "",
            "## Error",
            "",
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stderr)"),
            "",
            "## Guardrail",
            "",
            "- This API response did not launch, foreground, quit, kill, or control anything."
        ].joined(separator: "\n")
    }
}

enum ScriptMarkdownSnapshot {
    static func markdown(title: String, scriptName: String, makeTarget: String, environment: [String: String] = [:]) async -> String {
        let script = "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/\(scriptName)"
        guard FileManager.default.fileExists(atPath: script) else {
            return [
                "# \(title)",
                "",
                "The script is not available at:",
                "",
                "```text",
                script,
                "```",
                "",
                "Open the TerminalBrain repo and run:",
                "",
                "```zsh",
                makeTarget,
                "```",
                "",
                "Guardrail: this API response did not launch, foreground, quit, kill, or control anything."
            ].joined(separator: "\n")
        }

        let result = await CommandRunner.run("/bin/zsh", [script], environment: environment)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !output.isEmpty {
            return output
        }

        return [
            "# \(title)",
            "",
            "\(title) failed before completing.",
            "",
            "## Status",
            "",
            "- Exit: \(result.status)",
            "",
            "## Output",
            "",
            output.ifEmpty("(no stdout)"),
            "",
            "## Error",
            "",
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stderr)"),
            "",
            "## Guardrail",
            "",
            "- This API response did not launch, foreground, quit, kill, or control anything."
        ].joined(separator: "\n")
    }
}

enum ProcessMapSnapshot {
    static func markdown() async -> String {
        let script = "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/processes.zsh"
        guard FileManager.default.fileExists(atPath: script) else {
            return [
                "# Terminal Brain Process Map",
                "",
                "The process-map script is not available at:",
                "",
                "```text",
                script,
                "```",
                "",
                "Open the TerminalBrain repo and run:",
                "",
                "```zsh",
                "make processes",
                "```",
                "",
                "Guardrail: this API response did not launch, foreground, quit, kill, or control anything."
            ].joined(separator: "\n")
        }

        let result = await CommandRunner.run("/bin/zsh", [script, "--details"])
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !output.isEmpty {
            return output
        }

        return [
            "# Terminal Brain Process Map",
            "",
            "Process map failed before completing.",
            "",
            "## Status",
            "",
            "- Exit: \(result.status)",
            "",
            "## Output",
            "",
            output.ifEmpty("(no stdout)"),
            "",
            "## Error",
            "",
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stderr)"),
            "",
            "## Guardrail",
            "",
            "- This API response did not launch, foreground, quit, kill, or control anything."
        ].joined(separator: "\n")
    }
}

enum SupportBundleSnapshot {
    static func markdown() async -> String {
        let script = "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/support-bundle.zsh"
        let output = "/tmp/terminal-brain-app-support-bundle.md"
        guard FileManager.default.fileExists(atPath: script) else {
            return [
                "# Terminal Brain Support Bundle",
                "",
                "The support-bundle script is not available at:",
                "",
                "```text",
                script,
                "```",
                "",
                "Open the TerminalBrain repo and run:",
                "",
                "```zsh",
                "make support-bundle",
                "```",
                "",
                "Guardrail: this API response did not launch, foreground, quit, kill, or control anything."
            ].joined(separator: "\n")
        }

        let result = await CommandRunner.run("/bin/zsh", [script], environment: ["OUTPUT": output])
        let bundle = CommandRunner.readText(output).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !bundle.isEmpty {
            return bundle
        }

        return [
            "# Terminal Brain Support Bundle",
            "",
            "Support bundle failed before completing.",
            "",
            "## Status",
            "",
            "- Exit: \(result.status)",
            "",
            "## Output",
            "",
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stdout)"),
            "",
            "## Error",
            "",
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stderr)"),
            "",
            "## Guardrail",
            "",
            "- This API response did not launch, foreground, quit, kill, or control anything."
        ].joined(separator: "\n")
    }
}

enum WorkBlockSnapshot {
    static func markdown() async -> String {
        let script = "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/work-block.zsh"
        guard FileManager.default.fileExists(atPath: script) else {
            return [
                "# Terminal Brain Work Block",
                "",
                "The work-block script is not available at:",
                "",
                "```text",
                script,
                "```",
                "",
                "Open the TerminalBrain repo and run:",
                "",
                "```zsh",
                "make work-block",
                "```",
                "",
                "Guardrail: this API response did not launch, foreground, quit, kill, or control anything."
            ].joined(separator: "\n")
        }

        let result = await CommandRunner.run("/bin/zsh", [script])
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !output.isEmpty {
            return output
        }

        return [
            "# Terminal Brain Work Block",
            "",
            "Work Block failed before completing.",
            "",
            "## Status",
            "",
            "- Exit: \(result.status)",
            "",
            "## Output",
            "",
            output.ifEmpty("(no stdout)"),
            "",
            "## Error",
            "",
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stderr)"),
            "",
            "## Guardrail",
            "",
            "- This API response did not launch, foreground, quit, kill, or control anything."
        ].joined(separator: "\n")
    }
}

enum ValueProofSnapshot {
    static func markdown() async -> String {
        let script = "\(Paths.home)/Git/TerminalBrain/mac-app/scripts/prove-value.zsh"
        guard FileManager.default.fileExists(atPath: script) else {
            return [
                "# Terminal Brain Value Proof",
                "",
                "The value proof script is not available at:",
                "",
                "```text",
                script,
                "```",
                "",
                "Open the TerminalBrain repo and run:",
                "",
                "```zsh",
                "make prove-value",
                "```",
                "",
                "Guardrail: this API response did not launch, foreground, quit, kill, or control anything."
            ].joined(separator: "\n")
        }

        let result = await CommandRunner.run("/bin/zsh", [script])
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.succeeded, !output.isEmpty {
            return output
        }

        return [
            "# Terminal Brain Value Proof",
            "",
            "Value proof failed before completing.",
            "",
            "## Status",
            "",
            "- Exit: \(result.status)",
            "",
            "## Output",
            "",
            output.ifEmpty("(no stdout)"),
            "",
            "## Error",
            "",
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("(no stderr)"),
            "",
            "## Guardrail",
            "",
            "- This API response did not launch, foreground, quit, kill, or control anything."
        ].joined(separator: "\n")
    }
}

enum OracleDigestSnapshot {
    static func digest() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let todayPayload = await TodaySnapshot.today()
        let radarPayload = await RadarSnapshot.radar()
        let blindspotPayload = await BlindspotSnapshot.blindspots()
        let ideaPayload = await IdeaPulseSnapshot.ideas()
        let projectsPayload = ProjectSnapshot.projects()
        let commitsPayload = OracleSnapshot.commits()

        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let commands = (todayPayload["commands"] as? [[String: Any]]) ?? []
        let radar = (radarPayload["items"] as? [[String: Any]]) ?? []
        let blindspots = (blindspotPayload["items"] as? [[String: Any]]) ?? []
        let ideas = (ideaPayload["items"] as? [[String: Any]]) ?? []
        let projects = (projectsPayload["items"] as? [[String: Any]]) ?? []
        let commits = (commitsPayload["items"] as? [[String: Any]]) ?? []

        let focusTitle = focus["title"] as? String ?? "Ask what changed"
        let focusProject = focus["project"] as? String ?? "General Brain"
        let focusAction = focus["action"] as? String ?? "Ask Oracle"
        let focusReason = focus["reason"] as? String ?? focus["detail"] as? String ?? "No focus signal is available yet."
        let commit = commits.first { ["new", "delegated"].contains($0["status"] as? String ?? "") }
        let blindspot = blindspots.first
        let idea = ideas.first
        let project = projects.first
        let command = commands.first
        let radarSignal = radar.first

        let decideTitle = commit?["title"] as? String ?? blindspot?["title"] as? String ?? "No unresolved decision visible"
        let decideDetail = commit?["preview"] as? String ?? blindspot?["question"] as? String ?? "Ask what should be accepted, linked, delegated, or dismissed."
        let decideProject = commit?["project"] as? String ?? blindspot?["project"] as? String ?? focusProject

        let createTitle = project?["name"] as? String ?? command?["title"] as? String ?? focusTitle
        let createDetail = project?["recommendedAction"] as? String ?? command?["detail"] as? String ?? "Create one durable artifact from the current focus."
        let createProject = project?["name"] as? String ?? command?["project"] as? String ?? focusProject

        let sections = [
            section(
                id: "notice",
                label: "Notice",
                title: focusTitle,
                detail: focusReason,
                action: focusAction,
                project: focusProject,
                symbol: focus["symbol"] as? String ?? "target",
                source: "Focus",
                question: "What changed that makes \(focusTitle) the thing to notice right now?"
            ),
            section(
                id: "decide",
                label: "Decide",
                title: decideTitle,
                detail: decideDetail,
                action: commit == nil ? "Ask Oracle" : "Open Review",
                project: decideProject,
                symbol: commit?["status"] as? String == "delegated" ? "paperplane.fill" : "tray.and.arrow.down.fill",
                source: commit == nil ? "Blindspot Brief" : "Oracle Review",
                question: "Should this be accepted, linked, delegated, dismissed, or turned into a concrete task?"
            ),
            section(
                id: "test",
                label: "Test",
                title: idea?["title"] as? String ?? "No idea test visible",
                detail: idea?["nextPrompt"] as? String ?? "Capture one rough thought or sync more material to surface a cheap test.",
                action: "Pressure Test",
                project: idea?["project"] as? String ?? focusProject,
                symbol: idea?["symbol"] as? String ?? "lightbulb.fill",
                source: "Idea Pulse",
                question: idea?["nextPrompt"] as? String ?? "What cheap test would prove this is worth more attention?"
            ),
            section(
                id: "create",
                label: "Create",
                title: createTitle,
                detail: createDetail,
                action: "Start Work",
                project: createProject,
                symbol: project?["symbol"] as? String ?? "shippingbox.fill",
                source: "Project Memory",
                question: "What artifact would make this useful by the end of the next work block?"
            ),
            section(
                id: "avoid",
                label: "Avoid",
                title: blindspot?["title"] as? String ?? radarSignal?["title"] as? String ?? "Avoid collecting signals without closure",
                detail: blindspot?["why"] as? String ?? radarSignal?["reason"] as? String ?? "Do not let asks, reviews, and ideas pile up without a committed outcome.",
                action: blindspot?["nextAction"] as? String ?? radarSignal?["action"] as? String ?? "Commit Outcome",
                project: blindspot?["project"] as? String ?? radarSignal?["project"] as? String ?? focusProject,
                symbol: blindspot?["symbol"] as? String ?? "eye.fill",
                source: blindspot == nil ? "Radar" : "Blindspot Brief",
                question: blindspot?["question"] as? String ?? "What am I avoiding because it is ambiguous or annoying?"
            )
        ]

        return [
            "generatedAt": generatedAt,
            "mode": "oracle-digest",
            "headline": "Notice \(focusTitle)",
            "thesis": "Use the next block to \(focusAction.lowercased()) for \(focusProject), decide the review queue, pressure-test one idea, and finish with a written outcome.",
            "sections": sections,
            "questions": sections.map { $0["question"] as? String ?? "" }.filter { !$0.isEmpty },
            "actions": sections.map { item in
                "\(item["action"] as? String ?? "Act"): \(item["title"] as? String ?? "Untitled")"
            }
        ]
    }

    static func markdown() async -> String {
        let payload = await digest()
        let sections = (payload["sections"] as? [[String: Any]]) ?? []
        let questions = (payload["questions"] as? [String]) ?? []
        let actions = (payload["actions"] as? [String]) ?? []

        var lines: [String] = [
            "# Terminal Brain Oracle Digest",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "\(payload["headline"] as? String ?? "Notice the strongest current signal.")",
            "",
            "\(payload["thesis"] as? String ?? "")",
            ""
        ]

        for item in sections {
            lines.append("## \(item["label"] as? String ?? "Signal"): \(item["title"] as? String ?? "Untitled")")
            lines.append("- Action: \(item["action"] as? String ?? "Act")")
            lines.append("- Project: \(item["project"] as? String ?? "General Brain")")
            lines.append("- Source: \(item["source"] as? String ?? "")")
            lines.append("- Question: \(item["question"] as? String ?? "What should I notice?")")
            if let detail = item["detail"] as? String, !detail.isEmpty {
                lines.append("- Detail: \(detail)")
            }
            lines.append("")
        }

        lines.append("## Next Questions")
        lines.append(contentsOf: questions.prefix(5).map { "- \($0)" })
        if questions.isEmpty { lines.append("- Ask what changed and what deserves attention now.") }
        lines.append("")

        lines.append("## Closure Actions")
        lines.append(contentsOf: actions.prefix(5).map { "- \($0)" })
        if actions.isEmpty { lines.append("- Commit one outcome before switching context.") }

        return lines.joined(separator: "\n")
    }

    private static func section(id: String, label: String, title: String, detail: String, action: String, project: String, symbol: String, source: String, question: String) -> [String: Any] {
        [
            "id": id,
            "label": label,
            "title": title,
            "detail": detail,
            "action": action,
            "project": project,
            "symbol": symbol,
            "source": source,
            "question": question
        ]
    }
}

enum OperatorDeckSnapshot {
    static func deck() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let oraclePayload = await OracleSnapshot.items()
        let radarPayload = await RadarSnapshot.radar()
        let commitsPayload = OracleSnapshot.commits()
        let projectsPayload = ProjectSnapshot.projects()

        let focusItem = (focusPayload["item"] as? [String: Any]) ?? [:]
        let oracleItems = (oraclePayload["items"] as? [[String: Any]]) ?? []
        let radarItems = (radarPayload["items"] as? [[String: Any]]) ?? []
        let commits = (commitsPayload["items"] as? [[String: Any]]) ?? []
        let projects = (projectsPayload["items"] as? [[String: Any]]) ?? []

        var items: [[String: Any]] = []
        items.append(card(
            slot: "doFirst",
            kicker: "Do First",
            title: focusItem["title"] as? String ?? "Ask Terminal Brain what to do first",
            detail: focusItem["reason"] as? String ?? "No focus signal is available yet.",
            action: focusItem["action"] as? String ?? "Ask Oracle",
            project: focusItem["project"] as? String ?? "General Brain",
            query: focusItem["query"] as? String ?? "",
            symbol: focusItem["symbol"] as? String ?? "target",
            sourceID: focusItem["id"] as? String ?? "focus",
            sourceType: (focusPayload["mode"] as? String) == "radar" ? "radar" : "focus"
        ))

        if let bubble = oracleItems.first {
            items.append(card(
                slot: "askAbout",
                kicker: bubble["kind"] as? String ?? "Oracle",
                title: bubble["title"] as? String ?? "Oracle surfaced item",
                detail: bubble["detail"] as? String ?? "Ask what changed and whether this matters.",
                action: "Ask Oracle",
                project: ProjectSnapshot.projectName(from: "\(bubble["title"] ?? "") \(bubble["detail"] ?? "")"),
                query: "What should I notice about \(bubble["title"] as? String ?? "this surfaced item")?",
                symbol: bubble["symbol"] as? String ?? "sparkle.magnifyingglass",
                sourceID: bubble["id"] as? String ?? "oracle",
                sourceType: "oracleItem"
            ))
        } else if let radar = radarItems.first {
            items.append(card(
                slot: "askAbout",
                kicker: "Radar",
                title: radar["title"] as? String ?? "Radar signal",
                detail: radar["reason"] as? String ?? "Review the strongest visible radar signal.",
                action: radar["action"] as? String ?? "Ask Oracle",
                project: radar["project"] as? String ?? "General Brain",
                query: radar["query"] as? String ?? "",
                symbol: radar["symbol"] as? String ?? "scope",
                sourceID: radar["id"] as? String ?? "radar",
                sourceType: "radar"
            ))
        }

        if let review = commits.first(where: { ($0["status"] as? String) == "new" }) ?? commits.first {
            items.append(card(
                slot: "review",
                kicker: review["status"] as? String ?? "Review",
                title: review["title"] as? String ?? "Committed memory",
                detail: review["preview"] as? String ?? "Classify this committed read so it stops lingering.",
                action: "Review",
                project: review["project"] as? String ?? "General Brain",
                query: review["question"] as? String ?? "",
                symbol: "tray.and.arrow.down.fill",
                sourceID: review["id"] as? String ?? "commit",
                sourceType: "oracleCommit"
            ))
        } else {
            items.append(card(
                slot: "capture",
                kicker: "Capture",
                title: "Save the thought before it disappears",
                detail: "Capture a raw idea or open loop into the Oracle Inbox.",
                action: "Capture Idea",
                project: "General Brain",
                query: "",
                symbol: "lightbulb.fill",
                sourceID: "capture",
                sourceType: "ideaCapture"
            ))
        }

        if let project = projects.first {
            items.append(card(
                slot: "project",
                kicker: "Project",
                title: project["name"] as? String ?? "Project memory",
                detail: project["recommendedAction"] as? String ?? "Open the project memory page.",
                action: "Open Project",
                project: project["name"] as? String ?? "General Brain",
                query: project["name"] as? String ?? "",
                symbol: project["symbol"] as? String ?? "folder.fill",
                sourceID: project["id"] as? String ?? "project",
                sourceType: "project"
            ))
        } else {
            items.append(card(
                slot: "startWork",
                kicker: "Start Work",
                title: "Build the first context pack",
                detail: "Create an agent handoff from local memory and Mission Control.",
                action: "Start Work",
                project: "General Brain",
                query: "",
                symbol: "shippingbox.fill",
                sourceID: "start-work",
                sourceType: "startWork"
            ))
        }

        return [
            "generatedAt": generatedAt,
            "mode": "operator-deck",
            "items": items
        ]
    }

    static func markdown() async -> String {
        let payload = await deck()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        var lines: [String] = [
            "# Terminal Brain Operator Deck",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "Use these cards in order. Act on direct queue items, ask about uncertain items, and capture anything that should not be lost.",
            ""
        ]

        for item in items.prefix(4) {
            let kicker = item["kicker"] as? String ?? "Card"
            let title = item["title"] as? String ?? "Untitled"
            let detail = item["detail"] as? String ?? ""
            let action = item["action"] as? String ?? "Act"
            let project = item["project"] as? String ?? "General Brain"
            let sourceType = item["sourceType"] as? String ?? ""
            let sourceID = item["sourceID"] as? String ?? ""
            lines.append("## \(kicker): \(title)")
            lines.append("- Action: \(action)")
            lines.append("- Project: \(project)")
            lines.append("- Source: \(sourceType) \(sourceID)")
            if !detail.isEmpty {
                lines.append("- Detail: \(detail)")
            }
            lines.append("")
        }

        if items.isEmpty {
            lines.append("- No Operator Deck cards are available.")
        }

        return lines.joined(separator: "\n")
    }

    static func applyAction(sourceType: String, sourceID: String, disposition: String, status: String) async -> [String: Any] {
        switch sourceType {
        case "radar":
            let resolvedDisposition = disposition.isEmpty ? "acted" : disposition
            return await RadarSnapshot.setDisposition(id: sourceID, disposition: resolvedDisposition)
        case "oracleCommit":
            let resolvedStatus = status.isEmpty ? "accepted" : status
            return OracleSnapshot.setReviewStatus(id: sourceID, status: resolvedStatus)
        case "focus":
            return [
                "ok": false,
                "error": "This Focus card is an instruction, not a persistent queue item. Act through the card action or build a context pack.",
                "sourceType": sourceType,
                "sourceID": sourceID
            ]
        default:
            return [
                "ok": false,
                "error": "Operator Deck card type is not directly triageable",
                "sourceType": sourceType,
                "sourceID": sourceID,
                "supportedSourceTypes": ["focus", "radar", "oracleCommit"]
            ]
        }
    }

    private static func card(slot: String, kicker: String, title: String, detail: String, action: String, project: String, query: String, symbol: String, sourceID: String, sourceType: String) -> [String: Any] {
        [
            "slot": slot,
            "kicker": kicker,
            "title": title,
            "detail": detail,
            "action": action,
            "project": project,
            "query": query,
            "symbol": symbol,
            "sourceID": sourceID,
            "sourceType": sourceType
        ]
    }
}

enum IdeaPulseSnapshot {
    static func ideas() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let oraclePayload = await OracleSnapshot.items()
        let commitsPayload = OracleSnapshot.commits()
        let projectsPayload = ProjectSnapshot.projects()
        let latestContext = ControlSnapshot.latestContextPack()
        let oracle = (oraclePayload["items"] as? [[String: Any]]) ?? []
        let commits = (commitsPayload["items"] as? [[String: Any]]) ?? []
        let projects = (projectsPayload["items"] as? [[String: Any]]) ?? []
        var items: [[String: Any]] = []

        for commit in commits.filter({ commit in
            let tags = commit["tags"] as? [String] ?? []
            return tags.contains("idea") || tags.contains("capture")
        }).prefix(8) {
            let status = commit["status"] as? String ?? "new"
            let unresolved = status == "new" || status == "delegated"
            items.append(card(
                id: "commit-\(commit["id"] as? String ?? "")",
                title: commit["title"] as? String ?? "Captured idea",
                detail: commit["preview"] as? String ?? "",
                whyNow: unresolved ? "This captured idea is still unclassified. Decide whether it deserves a test, a project link, or dismissal." : "This idea has been classified, but it may still be useful as project memory.",
                nextPrompt: "What is the cheapest test for this idea, and what would make it not worth pursuing?",
                project: commit["project"] as? String ?? "General Brain",
                source: "Oracle Inbox",
                score: unresolved ? 86 : 58,
                symbol: "lightbulb.fill",
                state: unresolved ? "Attention" : "Ready",
                path: commit["path"] as? String ?? ""
            ))
        }

        for item in oracle.filter({ ["idea", "opportunity", "bubbling"].contains($0["kind"] as? String ?? "") }).prefix(8) {
            let kind = item["kind"] as? String ?? "idea"
            let title = item["title"] as? String ?? "Idea"
            let detail = item["detail"] as? String ?? ""
            items.append(card(
                id: "oracle-\(item["id"] as? String ?? title)",
                title: title,
                detail: detail,
                whyNow: kind == "idea" ? "This surfaced as an idea signal. It needs a small test before it becomes real work." : "This is bubbling up from recent context and may be a useful adjacent opportunity.",
                nextPrompt: kind == "idea" ? "What is the smallest proof that this idea is worth keeping?" : "What decision would turn this opportunity into a useful next action?",
                project: ProjectSnapshot.projectName(from: "\(title) \(detail) \(item["source"] ?? "")"),
                source: item["source"] as? String ?? "Oracle",
                score: kind == "idea" ? 78 : 70,
                symbol: item["symbol"] as? String ?? "lightbulb.fill",
                state: "Ready",
                path: item["path"] as? String ?? ""
            ))
        }

        for project in projects.prefix(8) {
            let signalCount = project["signalCount"] as? Int ?? 0
            let delegatedCount = project["delegatedCount"] as? Int ?? 0
            guard signalCount > 0, delegatedCount == 0 else { continue }
            let name = project["name"] as? String ?? "Project"
            items.append(card(
                id: "project-\(project["id"] as? String ?? name)",
                title: "Untested edge for \(name)",
                detail: project["recommendedAction"] as? String ?? "",
                whyNow: "This project has memory attached but no delegated execution edge. It may need a sharper experiment instead of more browsing.",
                nextPrompt: "What would prove the next useful artifact for \(name) in under an hour?",
                project: name,
                source: "Project Memory",
                score: max(50, min(76, 54 + signalCount * 4)),
                symbol: project["symbol"] as? String ?? "folder.fill",
                state: "Ready",
                path: ((project["contextPacks"] as? [[String: Any]])?.first?["path"] as? String) ?? ""
            ))
        }

        if latestContext["ok"] as? Bool == true {
            let title = latestContext["title"] as? String ?? "Latest context pack"
            let path = latestContext["path"] as? String ?? ""
            items.append(card(
                id: "context-\(path)",
                title: "Fresh context worth mining",
                detail: title,
                whyNow: "The newest context pack may contain a useful idea or open loop before it goes stale.",
                nextPrompt: "What idea, risk, or unresolved question is hidden in \(title)?",
                project: ProjectSnapshot.projectName(from: title),
                source: "Context pack",
                score: 62,
                symbol: "shippingbox.fill",
                state: "Ready",
                path: path
            ))
        }

        if items.isEmpty {
            items.append(card(
                id: "fallback",
                title: "Capture the next raw thought",
                detail: "No strong idea signal is visible yet.",
                whyNow: "The system needs captured material before it can surface surprising connections.",
                nextPrompt: "What rough idea keeps returning, even if it is not ready?",
                project: "General Brain",
                source: "Fallback",
                score: 35,
                symbol: "lightbulb",
                state: "Ready",
                path: ""
            ))
        }

        let ranked = dedupe(items).sorted {
            let lhs = $0["score"] as? Int ?? 0
            let rhs = $1["score"] as? Int ?? 0
            if lhs == rhs {
                return ($0["title"] as? String ?? "") < ($1["title"] as? String ?? "")
            }
            return lhs > rhs
        }

        return [
            "generatedAt": generatedAt,
            "mode": "idea-pulse",
            "headline": ranked.first?["title"] as? String ?? "Capture an idea",
            "items": Array(ranked.prefix(10))
        ]
    }

    static func markdown() async -> String {
        let payload = await ideas()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        var lines: [String] = [
            "# Terminal Brain Idea Pulse",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "Use this as the queue of captured thoughts and resurfaced opportunities that deserve a cheap test before they become real work.",
            ""
        ]

        for (index, item) in items.prefix(10).enumerated() {
            lines.append("## \(index + 1). \(item["title"] as? String ?? "Idea")")
            lines.append("- Score: \(item["score"] as? Int ?? 0)")
            lines.append("- Project: \(item["project"] as? String ?? "General Brain")")
            lines.append("- Source: \(item["source"] as? String ?? "")")
            lines.append("- Next prompt: \(item["nextPrompt"] as? String ?? "What is the cheapest test?")")
            lines.append("- Why now: \(item["whyNow"] as? String ?? "")")
            if let detail = item["detail"] as? String, !detail.isEmpty {
                lines.append("- Detail: \(detail)")
            }
            if let path = item["path"] as? String, !path.isEmpty {
                lines.append("- Path: \(path)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func ask(id: String, question: String) async -> [String: Any] {
        let payload = await ideas()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        guard let item = selectedItem(id: id, items: items) ?? items.first else {
            return [
                "ok": false,
                "error": "No idea pulse items are available"
            ]
        }

        let title = item["title"] as? String ?? "Idea"
        let project = item["project"] as? String ?? "General Brain"
        let resolvedQuestion = question.ifEmpty(item["nextPrompt"] as? String ?? "What is the cheapest test for this idea?")
        let groundedQuestion = [
            resolvedQuestion,
            "",
            "Current Terminal Brain Idea Pulse item:",
            "Title: \(title)",
            "Project: \(project)",
            "Score: \(item["score"] as? Int ?? 0)",
            "Source: \(item["source"] as? String ?? "")",
            "Why now: \(item["whyNow"] as? String ?? "")",
            "Detail: \(item["detail"] as? String ?? "")",
            "Source path: \(item["path"] as? String ?? "")",
            "",
            "Answer with: cheap test, kill criteria, first action, and whether to commit this into project memory."
        ].joined(separator: "\n")

        let oracle = await OracleSnapshot.ask(question: groundedQuestion)
        var result = oracle
        result["idea"] = item
        result["question"] = resolvedQuestion
        result["groundedQuestion"] = groundedQuestion
        result["mode"] = "idea-\(oracle["mode"] as? String ?? "local")"
        result["commitSuggestion"] = [
            "title": "Idea Test - \(title)",
            "project": project,
            "tags": ["terminal-brain", "idea", "pressure-test", "oracle"]
        ]
        return result
    }

    private static func card(id: String, title: String, detail: String, whyNow: String, nextPrompt: String, project: String, source: String, score: Int, symbol: String, state: String, path: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "detail": detail,
            "whyNow": whyNow,
            "nextPrompt": nextPrompt,
            "project": project,
            "source": source,
            "score": min(max(score, 0), 100),
            "symbol": symbol,
            "state": state,
            "path": path
        ]
    }

    private static func dedupe(_ items: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var output: [[String: Any]] = []
        for item in items {
            let key = "\(item["title"] ?? "")-\(item["project"] ?? "")-\(item["source"] ?? "")".lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(item)
        }
        return output
    }

    private static func selectedItem(id: String, items: [[String: Any]]) -> [String: Any]? {
        guard !id.isEmpty else { return nil }
        return items.first {
            ($0["id"] as? String) == id ||
            ($0["title"] as? String) == id ||
            ($0["path"] as? String) == id
        }
    }
}

enum BlindspotSnapshot {
    static func blindspots() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let radarPayload = await RadarSnapshot.radar()
        let oraclePayload = await OracleSnapshot.items()
        let commitsPayload = OracleSnapshot.commits()
        let projectsPayload = ProjectSnapshot.projects()
        let setupPayload = await SetupSnapshot.setup()

        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let radar = (radarPayload["items"] as? [[String: Any]]) ?? []
        let oracle = (oraclePayload["items"] as? [[String: Any]]) ?? []
        let commits = (commitsPayload["items"] as? [[String: Any]]) ?? []
        let projects = (projectsPayload["items"] as? [[String: Any]]) ?? []
        let setup = (setupPayload["steps"] as? [[String: Any]]) ?? []

        var items: [[String: Any]] = []

        if let delegated = commits.first(where: { ($0["status"] as? String) == "delegated" }) {
            let title = delegated["title"] as? String ?? "Delegated Oracle read"
            items.append(card(
                id: "delegated-\(delegated["id"] as? String ?? title)",
                title: "Delegation without artifact",
                why: "You already decided this read should leave the inbox. If it does not become a Start Work pack or agent handoff, the decision decays into another loose note.",
                question: "What concrete artifact should this delegated read become?",
                nextAction: "Start Work",
                project: delegated["project"] as? String ?? "General Brain",
                source: "Oracle commit",
                sourceID: delegated["id"] as? String ?? "",
                score: 96,
                symbol: "paperplane.fill",
                path: delegated["path"] as? String ?? ""
            ))
        }

        if let review = commits.first(where: { ($0["status"] as? String) == "new" }) {
            let title = review["title"] as? String ?? "Unreviewed Oracle read"
            items.append(card(
                id: "review-\(review["id"] as? String ?? title)",
                title: "Decision debt in the Oracle Inbox",
                why: "A committed read is only useful after you accept, link, delegate, or dismiss it. A new read is an unresolved decision sitting in a note.",
                question: "Is this read accepted, linked to a project, delegated, or dismissed?",
                nextAction: "Review",
                project: review["project"] as? String ?? "General Brain",
                source: "Oracle commit",
                sourceID: review["id"] as? String ?? "",
                score: 92,
                symbol: "tray.and.arrow.down.fill",
                path: review["path"] as? String ?? ""
            ))
        }

        if let openLoop = oracle.first(where: { ($0["kind"] as? String) == "openLoop" }) {
            let title = openLoop["title"] as? String ?? "Open loop"
            items.append(card(
                id: "loop-\(openLoop["id"] as? String ?? title)",
                title: "Open loop resurfacing",
                why: openLoop["detail"] as? String ?? "This keeps appearing in local memory and may be unresolved work.",
                question: "What would make this loop closed enough to stop resurfacing?",
                nextAction: "Start Work",
                project: ProjectSnapshot.projectName(from: "\(title) \(openLoop["detail"] ?? "")"),
                source: openLoop["source"] as? String ?? "Oracle",
                sourceID: openLoop["id"] as? String ?? "",
                score: 86,
                symbol: openLoop["symbol"] as? String ?? "checklist",
                path: openLoop["path"] as? String ?? ""
            ))
        }

        if let idea = oracle.first(where: { ["idea", "opportunity", "bubbling"].contains($0["kind"] as? String ?? "") }) {
            let title = idea["title"] as? String ?? "Idea worth testing"
            items.append(card(
                id: "idea-\(idea["id"] as? String ?? title)",
                title: "Idea that needs pressure testing",
                why: idea["detail"] as? String ?? "This looks potentially valuable, but it has not been converted into a small test.",
                question: "What is the cheapest test that would prove whether this idea is worth keeping?",
                nextAction: "Ask Oracle",
                project: ProjectSnapshot.projectName(from: "\(title) \(idea["detail"] ?? "")"),
                source: idea["source"] as? String ?? "Oracle",
                sourceID: idea["id"] as? String ?? "",
                score: 78,
                symbol: idea["symbol"] as? String ?? "lightbulb.fill",
                path: idea["path"] as? String ?? ""
            ))
        }

        if let project = projects.first(where: { (($0["signalCount"] as? Int) ?? 0) >= 2 && (($0["delegatedCount"] as? Int) ?? 0) == 0 }) {
            let name = project["name"] as? String ?? "Project"
            items.append(card(
                id: "project-\(project["id"] as? String ?? name)",
                title: "Active project without an execution edge",
                why: project["recommendedAction"] as? String ?? "This project has memory attached, but no delegated execution card.",
                question: "What is the one artifact that would move \(name) forward today?",
                nextAction: "Open Project",
                project: name,
                source: "Project Memory",
                sourceID: project["id"] as? String ?? "",
                score: 72,
                symbol: project["symbol"] as? String ?? "folder.fill",
                path: ((project["contextPacks"] as? [[String: Any]])?.first?["path"] as? String) ?? ""
            ))
        }

        let focusID = focus["id"] as? String ?? ""
        if let secondSignal = radar.first(where: { ($0["id"] as? String ?? "") != focusID }) {
            let title = secondSignal["title"] as? String ?? "Second signal"
            items.append(card(
                id: "radar-\(secondSignal["id"] as? String ?? title)",
                title: "Second-order signal",
                why: "This did not win the focus slot, but its score is high enough that it may be the thing you are underweighting.",
                question: "Why is this not the first thing you are doing?",
                nextAction: secondSignal["action"] as? String ?? "Ask Oracle",
                project: secondSignal["project"] as? String ?? "General Brain",
                source: "Radar",
                sourceID: secondSignal["id"] as? String ?? "",
                score: max((secondSignal["score"] as? Int ?? 0) - 4, 50),
                symbol: secondSignal["symbol"] as? String ?? "scope",
                path: secondSignal["path"] as? String ?? ""
            ))
        }

        if let gap = setup.first(where: { ($0["state"] as? String) == "Attention" }) {
            let title = gap["title"] as? String ?? "Setup gap"
            items.append(card(
                id: "setup-\(gap["id"] as? String ?? title)",
                title: "System assumption to verify",
                why: gap["detail"] as? String ?? "A readiness gap can make every agent answer less trustworthy.",
                question: "Does this gap change which agent work is safe to delegate?",
                nextAction: gap["action"] as? String ?? "Open System",
                project: "System",
                source: "Setup",
                sourceID: gap["id"] as? String ?? "",
                score: 70,
                symbol: gap["symbol"] as? String ?? "exclamationmark.triangle.fill",
                path: ""
            ))
        }

        if items.isEmpty {
            items.append(card(
                id: "fallback",
                title: "No blindspot candidate is strong enough yet",
                why: "The current local scan did not find stale review debt, delegated work, project drift, or resurfacing open loops.",
                question: "What changed since the last sync that is not represented in durable memory?",
                nextAction: "Capture Idea",
                project: "General Brain",
                source: "Fallback",
                sourceID: "fallback",
                score: 40,
                symbol: "sparkle.magnifyingglass",
                path: ""
            ))
        }

        let ranked = dedupe(items).sorted { ($0["score"] as? Int ?? 0) > ($1["score"] as? Int ?? 0) }
        return [
            "generatedAt": generatedAt,
            "mode": "blindspot-brief",
            "headline": ranked.first?["title"] as? String ?? "Ask what is missing",
            "items": Array(ranked.prefix(6))
        ]
    }

    static func markdown() async -> String {
        let payload = await blindspots()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        var lines: [String] = [
            "# Terminal Brain Blindspot Brief",
            "",
            "Generated: \(payload["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "Use this as the counterweight to the normal focus lane: the things that may be ignored, stale, under-tested, or not yet turned into an artifact.",
            ""
        ]

        for (index, item) in items.enumerated() {
            lines.append("## \(index + 1). \(item["title"] as? String ?? "Blindspot")")
            lines.append("- Score: \(item["score"] as? Int ?? 0)")
            lines.append("- Project: \(item["project"] as? String ?? "General Brain")")
            lines.append("- Next action: \(item["nextAction"] as? String ?? "Ask Oracle")")
            lines.append("- Question: \(item["question"] as? String ?? "What am I not considering?")")
            lines.append("- Why: \(item["why"] as? String ?? "")")
            let source = item["source"] as? String ?? ""
            let sourceID = item["sourceID"] as? String ?? ""
            if !source.isEmpty || !sourceID.isEmpty {
                lines.append("- Source: \(source) \(sourceID)")
            }
            if let path = item["path"] as? String, !path.isEmpty {
                lines.append("- Path: \(path)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func ask(id: String, question: String) async -> [String: Any] {
        let payload = await blindspots()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        guard let item = selectedItem(id: id, items: items) ?? items.first else {
            return [
                "ok": false,
                "error": "No blindspot items are available"
            ]
        }

        let title = item["title"] as? String ?? "Blindspot"
        let project = item["project"] as? String ?? "General Brain"
        let resolvedQuestion = question.ifEmpty(item["question"] as? String ?? "What am I not considering?")
        let groundedQuestion = [
            resolvedQuestion,
            "",
            "Current Terminal Brain blindspot:",
            "Title: \(title)",
            "Project: \(project)",
            "Score: \(item["score"] as? Int ?? 0)",
            "Why: \(item["why"] as? String ?? "")",
            "Recommended next action: \(item["nextAction"] as? String ?? "Ask Oracle")",
            "Source: \(item["source"] as? String ?? "") \(item["sourceID"] as? String ?? "")"
        ].joined(separator: "\n")

        let oracle = await OracleSnapshot.ask(question: groundedQuestion)
        var result = oracle
        result["blindspot"] = item
        result["question"] = resolvedQuestion
        result["groundedQuestion"] = groundedQuestion
        result["mode"] = "blindspot-\(oracle["mode"] as? String ?? "local")"
        result["commitSuggestion"] = [
            "title": "Blindspot - \(title)",
            "project": project,
            "tags": ["terminal-brain", "blindspot", "oracle"]
        ]
        return result
    }

    static func applyAction(id: String, status: String, disposition: String) async -> [String: Any] {
        let payload = await blindspots()
        let items = (payload["items"] as? [[String: Any]]) ?? []
        guard let item = selectedItem(id: id, items: items) else {
            return [
                "ok": false,
                "error": "Blindspot item not found",
                "id": id
            ]
        }

        let source = item["source"] as? String ?? ""
        let sourceID = item["sourceID"] as? String ?? ""
        switch source {
        case "Oracle commit":
            let resolvedStatus = status.isEmpty ? "accepted" : status
            var result = OracleSnapshot.setReviewStatus(id: sourceID, status: resolvedStatus)
            result["blindspotID"] = item["id"] as? String ?? id
            result["source"] = source
            return result
        case "Radar":
            let resolvedDisposition = disposition.isEmpty ? "acted" : disposition
            var result = await RadarSnapshot.setDisposition(id: sourceID, disposition: resolvedDisposition)
            result["blindspotID"] = item["id"] as? String ?? id
            result["source"] = source
            return result
        default:
            return [
                "ok": false,
                "error": "Blindspot source is not directly resolvable",
                "source": source,
                "supportedSources": ["Oracle commit", "Radar"]
            ]
        }
    }

    private static func card(id: String, title: String, why: String, question: String, nextAction: String, project: String, source: String, sourceID: String, score: Int, symbol: String, path: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "why": why,
            "question": question,
            "nextAction": nextAction,
            "project": project,
            "source": source,
            "sourceID": sourceID,
            "score": min(max(score, 0), 100),
            "symbol": symbol,
            "path": path
        ]
    }

    private static func dedupe(_ items: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var output: [[String: Any]] = []
        for item in items {
            let key = "\(item["title"] ?? "")-\(item["project"] ?? "")-\(item["sourceID"] ?? "")".lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(item)
        }
        return output
    }

    private static func selectedItem(id: String, items: [[String: Any]]) -> [String: Any]? {
        guard !id.isEmpty else { return nil }
        return items.first {
            ($0["id"] as? String) == id ||
            ($0["sourceID"] as? String) == id ||
            ($0["title"] as? String) == id
        }
    }
}

enum BrainSnapshot {
    static func snapshot() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let briefPayload = await OperatorBriefSnapshot.brief()
        let deckPayload = await OperatorDeckSnapshot.deck()
        let focus = await FocusSnapshot.focus()
        let radarPayload = await RadarSnapshot.radar()
        let blindspotPayload = await BlindspotSnapshot.blindspots()
        let ideaPayload = await IdeaPulseSnapshot.ideas()
        let setupPayload = await SetupSnapshot.setup()
        let todayPayload = await TodaySnapshot.today()
        let commitsPayload = OracleSnapshot.commits()

        let focusItem = (focus["item"] as? [String: Any]) ?? [:]
        let radarItems = (radarPayload["items"] as? [[String: Any]]) ?? []
        let setupSteps = (setupPayload["steps"] as? [[String: Any]]) ?? []
        let todayCommands = (todayPayload["commands"] as? [[String: Any]]) ?? []
        let commits = (commitsPayload["items"] as? [[String: Any]]) ?? []

        return payload(
            generatedAt: generatedAt,
            focus: focus,
            radarItems: Array(radarItems.prefix(5)),
            blindspots: Array((blindspotPayload["items"] as? [[String: Any]] ?? []).prefix(5)),
            ideas: Array((ideaPayload["items"] as? [[String: Any]] ?? []).prefix(5)),
            setupSteps: attentionSteps(from: setupSteps),
            todayCommands: Array(todayCommands.prefix(5)),
            operatorBrief: (briefPayload["items"] as? [[String: Any]]) ?? [],
            operatorDeck: (deckPayload["items"] as? [[String: Any]]) ?? [],
            memoryTrail: Array(commits.prefix(5)),
            suggestedActions: suggestedActions(focusItem: focusItem, setupSteps: setupSteps, commits: commits)
        )
    }

    static func markdown() async -> String {
        renderMarkdown(snapshot: await snapshot())
    }

    private static func payload(generatedAt: String, focus: [String: Any], radarItems: [[String: Any]], blindspots: [[String: Any]], ideas: [[String: Any]], setupSteps: [[String: Any]], todayCommands: [[String: Any]], operatorBrief: [[String: Any]], operatorDeck: [[String: Any]], memoryTrail: [[String: Any]], suggestedActions: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        result["generatedAt"] = generatedAt
        result["mode"] = "operator-snapshot"
        result["focus"] = focus
        result["radar"] = radarItems
        result["blindspots"] = blindspots
        result["ideas"] = ideas
        result["setupAttention"] = setupSteps
        result["today"] = todayCommands
        result["operatorBrief"] = operatorBrief
        result["operatorDeck"] = operatorDeck
        result["memoryTrail"] = memoryTrail
        result["suggestedActions"] = suggestedActions
        return result
    }

    private static func attentionSteps(from steps: [[String: Any]]) -> [[String: Any]] {
        Array(steps.filter { ($0["state"] as? String) == "Attention" }.prefix(5))
    }

    private static func suggestedActions(focusItem: [String: Any], setupSteps: [[String: Any]], commits: [[String: Any]]) -> [String] {
        var actions: [String] = []
        let focusTitle = focusItem["title"] as? String ?? "current focus"
        let focusAction = focusItem["action"] as? String ?? "Act"
        actions.append("\(focusAction): \(focusTitle)")
        actions.append("Ask the Focus Oracle what is missing.")
        if setupSteps.contains(where: { ($0["state"] as? String) == "Attention" }) {
            actions.append("Clear the top setup attention item.")
        }
        if commits.contains(where: { ($0["status"] as? String) == "new" }) {
            actions.append("Review the newest committed memory.")
        }
        actions.append("Capture any new thought before changing context.")
        return actions
    }

    private static func renderMarkdown(snapshot: [String: Any]) -> String {
        let focus = snapshot["focus"] as? [String: Any] ?? [:]
        let focusItem = focus["item"] as? [String: Any] ?? [:]
        let operatorBrief = snapshot["operatorBrief"] as? [[String: Any]] ?? []
        let operatorDeck = snapshot["operatorDeck"] as? [[String: Any]] ?? []
        let radar = snapshot["radar"] as? [[String: Any]] ?? []
        let blindspots = snapshot["blindspots"] as? [[String: Any]] ?? []
        let ideas = snapshot["ideas"] as? [[String: Any]] ?? []
        let trail = snapshot["memoryTrail"] as? [[String: Any]] ?? []
        let actions = snapshot["suggestedActions"] as? [String] ?? []

        var lines: [String] = [
            "# Terminal Brain Snapshot",
            "",
            "Generated: \(snapshot["generatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Focus",
            "- Title: \(focusItem["title"] as? String ?? "Unknown")",
            "- Project: \(focusItem["project"] as? String ?? "General Brain")",
            "- Action: \(focusItem["action"] as? String ?? "Act")",
            "- Score: \(focusItem["score"] as? Int ?? 0)",
            "- Reason: \(focusItem["reason"] as? String ?? "")",
            ""
        ]

        lines.append("## Suggested Actions")
        lines.append(contentsOf: actions.prefix(5).map { "- \($0)" })
        if actions.isEmpty { lines.append("- Ask the Focus Oracle what changed.") }
        lines.append("")

        lines.append("## Operator Brief")
        lines.append(contentsOf: operatorBrief.prefix(4).map { item in
            let label = item["label"] as? String ?? "Signal"
            let title = item["title"] as? String ?? "Untitled"
            let action = item["action"] as? String ?? "Act"
            return "- \(label): \(title) -> \(action)"
        })
        if operatorBrief.isEmpty { lines.append("- No operator brief items.") }
        lines.append("")

        lines.append("## Operator Deck")
        lines.append(contentsOf: operatorDeck.prefix(4).map { item in
            let kicker = item["kicker"] as? String ?? "Card"
            let title = item["title"] as? String ?? "Untitled"
            let action = item["action"] as? String ?? "Act"
            return "- \(kicker): \(title) -> \(action)"
        })
        if operatorDeck.isEmpty { lines.append("- No operator deck cards.") }
        lines.append("")

        lines.append("## Radar")
        lines.append(contentsOf: radar.prefix(5).map { item in
            let score = item["score"] as? Int ?? 0
            let title = item["title"] as? String ?? "Radar signal"
            let detail = item["detail"] as? String ?? ""
            return "- [\(score)] \(title): \(detail)"
        })
        if radar.isEmpty { lines.append("- No radar signals.") }
        lines.append("")

        lines.append("## Blindspot Brief")
        lines.append(contentsOf: blindspots.prefix(5).map { item in
            let score = item["score"] as? Int ?? 0
            let title = item["title"] as? String ?? "Blindspot"
            let question = item["question"] as? String ?? "What am I not considering?"
            return "- [\(score)] \(title): \(question)"
        })
        if blindspots.isEmpty { lines.append("- No blindspot candidates.") }
        lines.append("")

        lines.append("## Idea Pulse")
        lines.append(contentsOf: ideas.prefix(5).map { item in
            let score = item["score"] as? Int ?? 0
            let title = item["title"] as? String ?? "Idea"
            let nextPrompt = item["nextPrompt"] as? String ?? "What is the cheapest test?"
            return "- [\(score)] \(title): \(nextPrompt)"
        })
        if ideas.isEmpty { lines.append("- No idea pulse items.") }
        lines.append("")

        lines.append("## Memory Trail")
        lines.append(contentsOf: trail.prefix(5).map { item in
            let title = item["title"] as? String ?? "Memory"
            let status = item["status"] as? String ?? "new"
            let project = item["project"] as? String ?? "General Brain"
            return "- \(title) (\(project), \(status))"
        })
        if trail.isEmpty { lines.append("- No committed memory yet.") }

        return lines.joined(separator: "\n")
    }
}

enum AgentPromptSnapshot {
    static func markdown() async -> String {
        let generated = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let valuePayload = await ValueBriefSnapshot.brief()
        let digestPayload = await OracleDigestSnapshot.digest()
        let ideaPayload = await IdeaPulseSnapshot.ideas()
        let blindspotPayload = await BlindspotSnapshot.blindspots()
        let pack = ControlSnapshot.latestContextPack()

        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let drivers = (valuePayload["drivers"] as? [[String: Any]]) ?? []
        let digestSections = (digestPayload["sections"] as? [[String: Any]]) ?? []
        let ideas = (ideaPayload["items"] as? [[String: Any]]) ?? []
        let blindspots = (blindspotPayload["items"] as? [[String: Any]]) ?? []
        let title = focus["title"] as? String ?? "Move the current Terminal Brain focus forward"
        let project = focus["project"] as? String ?? "General Brain"
        let action = focus["action"] as? String ?? "Act"
        let query = focus["query"] as? String ?? title

        var lines: [String] = [
            "# Terminal Brain Agent Prompt",
            "",
            "Generated: \(generated)",
            "",
            "## Task",
            "Move this forward now: \(title)",
            "",
            "- Project: \(project)",
            "- Action: \(action)",
            "- Working query: \(query.ifEmpty(title))",
            "",
            "## Why This Matters",
            (digestPayload["thesis"] as? String) ?? (valuePayload["thesis"] as? String) ?? "Use the current Value Brief as the reason for prioritizing this task.",
            ""
        ]

        lines.append("## Oracle Digest")
        for section in digestSections.prefix(5) {
            lines.append("- \(section["label"] as? String ?? "Signal"): \(section["title"] as? String ?? "Untitled") -> \(section["action"] as? String ?? "Act")")
            if let question = section["question"] as? String, !question.isEmpty {
                lines.append("  Question: \(question.prefixString(maxLength: 220))")
            }
        }
        if digestSections.isEmpty {
            lines.append("- No Oracle Digest lanes are available. Use Focus, Value Brief, and Project Memory.")
        }
        lines.append("")

        lines.append("## Value Drivers")
        for driver in drivers.prefix(4) {
            lines.append("- \(driver["label"] as? String ?? "Value"): \(driver["title"] as? String ?? "Untitled") -> \(driver["action"] as? String ?? "Act")")
            if let detail = driver["detail"] as? String, !detail.isEmpty {
                lines.append("  Detail: \(detail.prefixString(maxLength: 240))")
            }
        }
        if drivers.isEmpty {
            lines.append("- No value drivers are available. Ask Terminal Brain Oracle what changed.")
        }
        lines.append("")

        lines.append("## Acceptance Criteria")
        lines.append("- Produce one concrete artifact, patch, decision, or written recommendation tied to \(project).")
        lines.append("- State what changed, why it matters, and the next action.")
        lines.append("- Commit useful findings back with `terminal_brain_commit_outcome` or through the Obsidian-backed Oracle Inbox.")
        lines.append("- If implementation is unsafe or under-specified, return the smallest clarifying question and a proposed next test.")
        lines.append("")

        lines.append("## Signals To Consider")
        if let idea = ideas.first {
            lines.append("- Idea to pressure-test: \(idea["title"] as? String ?? "Idea")")
            lines.append("  Prompt: \(idea["nextPrompt"] as? String ?? "What is the cheapest test?")")
        }
        if let blindspot = blindspots.first {
            lines.append("- Blindspot to check: \(blindspot["title"] as? String ?? "Blindspot")")
            lines.append("  Question: \(blindspot["question"] as? String ?? "What am I not considering?")")
        }
        if ideas.isEmpty && blindspots.isEmpty {
            lines.append("- No Idea Pulse or Blindspot signal is available; use Focus and Project Memory.")
        }
        lines.append("")

        lines.append("## Context")
        if pack["ok"] as? Bool == true {
            lines.append("- Latest context pack: \(pack["path"] as? String ?? "")")
        } else {
            lines.append("- No latest context pack is available. Build one if the task needs local source grounding.")
        }
        lines.append("- Terminal Brain API: http://127.0.0.1:8765")
        lines.append("")

        lines.append("## Guardrails")
        lines.append("- Do not launch, relaunch, quit, or foreground Terminal Brain unless John explicitly asks in the current turn.")
        lines.append("- Prefer non-launching static verification first: `make verify`.")
        lines.append("- Preserve unrelated working-tree changes.")
        lines.append("- End with files changed, verification run, and any remaining risk.")

        return lines.joined(separator: "\n")
    }
}

enum StartHereSnapshot {
    static func markdown() async -> String {
        let generated = ISO8601DateFormatter().string(from: Date())
        let focusPayload = await FocusSnapshot.focus()
        let digestPayload = await OracleDigestSnapshot.digest()
        let pack = ControlSnapshot.latestContextPack()
        let focus = (focusPayload["item"] as? [String: Any]) ?? [:]
        let sections = (digestPayload["sections"] as? [[String: Any]]) ?? []

        let title = focus["title"] as? String ?? "Move the current Terminal Brain focus forward"
        let project = focus["project"] as? String ?? "General Brain"
        let action = focus["action"] as? String ?? "Act"
        let query = (focus["query"] as? String ?? title).ifEmpty(title)
        let packPath = pack["path"] as? String ?? ""

        var lines: [String] = [
            "# Terminal Brain Start Here",
            "",
            "Generated: \(generated)",
            "",
            "## One-Block Path",
            "1. Read the Oracle Brief for the direct read, missing signal, cheap test, and handoff.",
            "2. Copy the Agent Prompt when handing work to Codex or Claude.",
            "3. Build or use a context pack for the current project.",
            "4. Commit the outcome before switching context.",
            "",
            "## Current Move",
            "- Project: \(project)",
            "- Focus: \(title)",
            "- Action: \(action)",
            "- Working query: \(query)",
            ""
        ]

        lines.append("## Oracle Brief")
        for section in sections.prefix(5) {
            lines.append("- \(section["label"] as? String ?? "Signal"): \(section["title"] as? String ?? "Untitled") -> \(section["action"] as? String ?? "Act")")
            if let question = section["question"] as? String, !question.isEmpty {
                lines.append("  Question: \(question.prefixString(maxLength: 220))")
            }
        }
        if sections.isEmpty {
            lines.append("- No digest lanes are available. Start with Focus and commit a useful outcome.")
        }
        lines.append("")

        lines.append("## Context")
        if pack["ok"] as? Bool == true, !packPath.isEmpty {
            lines.append("- Latest context pack: \(packPath)")
        } else {
            lines.append("- No latest context pack is available. Build one with the working query before deep implementation.")
        }
        lines.append("")

        lines.append("## Non-Launching Commands")
        lines.append("- `make snapshot-digest`")
        lines.append("- `make agent-prompt`")
        lines.append("- `make latest-pack`")
        lines.append("- `make outcome TITLE=\"...\" OUTCOME=\"...\" PROJECT=\"\(project)\" NEXT=\"...\"`")
        lines.append("")

        lines.append("## Done Means")
        lines.append("- One artifact, patch, decision, or written recommendation exists.")
        lines.append("- The result says what changed, why it matters, and the next action.")
        lines.append("- Useful findings are committed with `terminal_brain_commit_outcome`, `make outcome`, the app Start Here box, or the Commit Outcome shortcut.")
        lines.append("- Terminal Brain was not launched, relaunched, quit, or foregrounded unless John explicitly asked.")

        return lines.joined(separator: "\n")
    }
}

enum BrainHandoffSnapshot {
    static func markdown() async -> String {
        let generated = ISO8601DateFormatter().string(from: Date())
        let startHere = await StartHereSnapshot.markdown()
        let oracle = await OracleSnapshot.markdown()
        let digest = await OracleDigestSnapshot.markdown()
        let value = await ValueBriefSnapshot.markdown()
        let brief = await OperatorBriefSnapshot.markdown()
        let blindspots = await BlindspotSnapshot.markdown()
        let ideas = await IdeaPulseSnapshot.markdown()
        let decisions = await TodaySnapshot.markdown()
        let deck = await OperatorDeckSnapshot.markdown()
        let projects = ProjectSnapshot.markdown()
        let pack = ControlSnapshot.latestContextPackMarkdown()
        return [
            "# Terminal Brain Handoff",
            "",
            "Generated: \(generated)",
            "",
            "## How To Use This",
            "- Use Start Here when you need the shortest path from signal to action to outcome.",
            "- Start with the Oracle Brief when you want the direct read: next moves, missing signal, cheap test, and agent handoff.",
            "- Use the Oracle Digest when you want the lane breakdown: what to notice, decide, test, create, and avoid.",
            "- Start with the Operator Brief for plain-language value, then use the Operator Deck for concrete actions.",
            "- Treat the first action card as the default next move unless new evidence contradicts it.",
            "- Read the Blindspot Brief before broad planning; it lists the thing most likely to be ignored or left unresolved.",
            "- Read Idea Pulse to pressure-test captured thoughts and resurfaced opportunities before they become noisy projects.",
            "- Use the Decision Lane as the ranked execution queue before asking broad follow-up questions.",
            "- Use Project Memory to keep agent work attached to durable work surfaces.",
            "- Use the latest context pack as the working memory bundle for implementation, review, or planning.",
            "- Prefer concrete actions: build a pack, ask a focused question, commit useful findings, or mark queue items acted/dismissed.",
            "- Do not relaunch or foreground Terminal Brain unless the operator explicitly asks.",
            "",
            "## Contents",
            "- Start Here: one-block path from current signal to committed outcome.",
            "- Oracle Brief: direct read, missing signal, cheap test, and agent handoff.",
            "- Oracle Digest: narrative read on what deserves attention and closure.",
            "- Value Brief: compact read on why the current move is worth attention.",
            "- Operator Brief: plain-language value read.",
            "- Blindspot Brief: counter-signal for ignored, stale, or under-tested work.",
            "- Idea Pulse: captured ideas and resurfaced opportunities ranked by cheap-test value.",
            "- Decision Lane: ranked execution queue.",
            "- Operator Deck: four action cards.",
            "- Project Memory: active work surfaces and source paths.",
            "- Latest Context Pack: freshest working-memory bundle.",
            "",
            startHere,
            "",
            "---",
            "",
            oracle,
            "",
            "---",
            "",
            digest,
            "",
            "---",
            "",
            value,
            "",
            "---",
            "",
            brief,
            "",
            "---",
            "",
            blindspots,
            "",
            "---",
            "",
            ideas,
            "",
            "---",
            "",
            decisions,
            "",
            "---",
            "",
            deck,
            "",
            "---",
            "",
            projects,
            "",
            "---",
            "",
            "# Latest Context Pack",
            "",
            pack
        ].joined(separator: "\n")
    }
}

enum FocusSnapshot {
    static func focus() async -> [String: Any] {
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let radarPayload = await RadarSnapshot.radar()
        let radar = (radarPayload["items"] as? [[String: Any]]) ?? []
        if let item = radar.first {
            return focusPayload(
                generatedAt: generatedAt,
                mode: "radar",
                item: radarFocusItem(from: item),
                candidates: Array(radar.prefix(4))
            )
        }

        let today = await TodaySnapshot.today()
        let commands = (today["commands"] as? [[String: Any]]) ?? []
        let first = commands.first ?? fallbackCommand()
        return focusPayload(
            generatedAt: generatedAt,
            mode: "today",
            item: commandFocusItem(from: first),
            candidates: commands
        )
    }

    static func ask(question: String) async -> [String: Any] {
        let focusPayload = await focus()
        let item = (focusPayload["item"] as? [String: Any]) ?? [:]
        let resolvedQuestion = question.ifEmpty(defaultQuestion(for: item))
        let groundedQuestion = focusQuestion(question: resolvedQuestion, item: item)
        let oracle = await OracleSnapshot.ask(question: groundedQuestion)

        var payload = oracle
        payload["focus"] = focusPayload
        payload["question"] = resolvedQuestion
        payload["groundedQuestion"] = groundedQuestion
        payload["mode"] = "focus-\(oracle["mode"] as? String ?? "local")"
        payload["commitSuggestion"] = [
            "title": "Focus - \(item["title"] as? String ?? "Oracle Read")",
            "project": item["project"] as? String ?? "General Brain",
            "tags": ["terminal-brain", "focus", "oracle"]
        ]
        return payload
    }

    private static func focusPayload(generatedAt: String, mode: String, item: [String: Any], candidates: [[String: Any]]) -> [String: Any] {
        var payload: [String: Any] = [:]
        payload["generatedAt"] = generatedAt
        payload["mode"] = mode
        payload["item"] = item
        payload["candidates"] = candidates
        return payload
    }

    private static func radarFocusItem(from item: [String: Any]) -> [String: Any] {
        let evidence = (item["evidence"] as? [String]) ?? []
        let reason = evidence.joined(separator: " • ").ifEmpty(item["reason"] as? String ?? "")
        return focusItem(
            id: item["id"] as? String ?? "",
            title: item["title"] as? String ?? "",
            detail: item["detail"] as? String ?? "",
            reason: reason,
            action: item["action"] as? String ?? "Ask Oracle",
            project: item["project"] as? String ?? "General Brain",
            score: item["score"] as? Int ?? 0,
            symbol: item["symbol"] as? String ?? "target",
            state: item["state"] as? String ?? "Ready",
            query: item["query"] as? String ?? "",
            path: item["path"] as? String ?? ""
        )
    }

    private static func commandFocusItem(from item: [String: Any]) -> [String: Any] {
        focusItem(
            id: item["id"] as? String ?? "",
            title: item["title"] as? String ?? "",
            detail: item["detail"] as? String ?? "",
            reason: "Top item from the Daily Command Center.",
            action: item["action"] as? String ?? "Ask Oracle",
            project: item["project"] as? String ?? "General Brain",
            score: 0,
            symbol: item["symbol"] as? String ?? "target",
            state: "Ready",
            query: item["query"] as? String ?? "",
            path: ""
        )
    }

    private static func fallbackCommand() -> [String: Any] {
        var item: [String: Any] = [:]
        item["id"] = "ask-oracle"
        item["title"] = "Ask what changed"
        item["detail"] = "No active signal is available yet."
        item["action"] = "Ask Oracle"
        item["project"] = "General Brain"
        item["symbol"] = "sparkle.magnifyingglass"
        item["query"] = "What am I not considering right now?"
        return item
    }

    private static func defaultQuestion(for item: [String: Any]) -> String {
        "What should I do next about \(item["title"] as? String ?? "this focus item")?"
    }

    private static func focusQuestion(question: String, item: [String: Any]) -> String {
        [
            question,
            "",
            "Current Terminal Brain focus:",
            "Title: \(item["title"] as? String ?? "")",
            "Project: \(item["project"] as? String ?? "")",
            "Detail: \(item["detail"] as? String ?? "")",
            "Reason: \(item["reason"] as? String ?? "")",
            "Score: \(item["score"] as? Int ?? 0)",
            "Recommended action: \(item["action"] as? String ?? "")"
        ].joined(separator: "\n")
    }

    private static func focusItem(id: String, title: String, detail: String, reason: String, action: String, project: String, score: Int, symbol: String, state: String, query: String, path: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "detail": detail,
            "reason": reason,
            "action": action,
            "project": project,
            "score": score,
            "symbol": symbol,
            "state": state,
            "query": query,
            "path": path
        ]
    }
}

enum RadarSnapshot {
    static func radar() async -> [String: Any] {
        let setup = await SetupSnapshot.setup()
        let projects = (ProjectSnapshot.projects()["items"] as? [[String: Any]]) ?? []
        let commits = (OracleSnapshot.commits()["items"] as? [[String: Any]]) ?? []
        let oraclePayload = await OracleSnapshot.items()
        let oracle = (oraclePayload["items"] as? [[String: Any]]) ?? []
        var items: [[String: Any]] = []

        for step in (setup["steps"] as? [[String: Any]] ?? []).filter({ ($0["state"] as? String) == "Attention" }).prefix(2) {
            items.append(item(
                id: "setup-\(step["id"] ?? "")",
                title: "Readiness gap: \(step["title"] as? String ?? "Setup")",
                detail: step["detail"] as? String ?? "",
                reason: "This weakens agent reliability or source coverage.",
                action: step["action"] as? String ?? "Open Setup",
                project: "System",
                urgency: "Safety",
                symbol: step["symbol"] as? String ?? "exclamationmark.triangle",
                state: "Attention",
                query: step["title"] as? String ?? "Setup",
                path: ""
            ))
        }

        for commit in commits.filter({ ($0["status"] as? String) == "delegated" }).prefix(3) {
            items.append(item(
                id: "delegated-\(commit["id"] ?? "")",
                title: "Delegated read needs execution",
                detail: commit["title"] as? String ?? "Delegated Oracle read",
                reason: "You already marked this as delegated. It should become a context pack or agent handoff.",
                action: "Start Work",
                project: commit["project"] as? String ?? "",
                urgency: "Now",
                symbol: "paperplane.fill",
                state: "Running",
                query: [commit["project"] as? String ?? "", commit["title"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " - "),
                path: commit["path"] as? String ?? ""
            ))
        }

        for commit in commits.filter({ ($0["status"] as? String) == "new" }).prefix(4) {
            items.append(item(
                id: "review-\(commit["id"] ?? "")",
                title: "Unclassified Oracle read",
                detail: commit["preview"] as? String ?? "",
                reason: "A useful answer is only durable when it is accepted, linked, delegated, or dismissed.",
                action: "Open Review",
                project: commit["project"] as? String ?? "",
                urgency: "Triage",
                symbol: "tray.fill",
                state: "Attention",
                query: commit["title"] as? String ?? "",
                path: commit["path"] as? String ?? ""
            ))
        }

        for project in projects.prefix(5) {
            let delegated = project["delegatedCount"] as? Int ?? 0
            let recommended = project["recommendedAction"] as? String ?? ""
            items.append(item(
                id: "project-\(project["id"] ?? "")",
                title: delegated > 0 ? "Project needs execution" : "Project wants a decision",
                detail: recommended,
                reason: project["summary"] as? String ?? "",
                action: "Open Project",
                project: project["name"] as? String ?? "",
                urgency: delegated > 0 ? "Now" : "Next",
                symbol: project["symbol"] as? String ?? "folder.fill",
                state: delegated > 0 ? "Running" : "Ready",
                query: project["name"] as? String ?? "",
                path: ((project["contextPacks"] as? [[String: Any]])?.first?["path"] as? String) ?? ""
            ))
        }

        for signal in oracle.filter({ ["idea", "opportunity", "openLoop"].contains($0["kind"] as? String ?? "") }).prefix(5) {
            let kind = signal["kind"] as? String ?? "signal"
            items.append(item(
                id: "oracle-\(signal["id"] ?? "")",
                title: kind == "openLoop" ? "Open loop resurfaced" : "Idea worth testing",
                detail: signal["title"] as? String ?? "",
                reason: signal["detail"] as? String ?? "",
                action: kind == "openLoop" ? "Start Work" : "Ask Oracle",
                project: ProjectSnapshot.projectName(from: "\(signal["title"] ?? "") \(signal["detail"] ?? "") \(signal["source"] ?? "")"),
                urgency: kind == "openLoop" ? "Next" : "Explore",
                symbol: signal["symbol"] as? String ?? "scope",
                state: kind == "openLoop" ? "Attention" : "Ready",
                query: signal["title"] as? String ?? "",
                path: signal["path"] as? String ?? ""
            ))
        }

        let deduped = rank(applyDisposition(to: dedupe(items)))
        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "items": Array(deduped.prefix(12)),
            "attentionCount": deduped.filter { ($0["state"] as? String) == "Attention" }.count,
            "nowCount": deduped.filter { ($0["urgency"] as? String) == "Now" }.count
        ]
    }

    static func setDisposition(id: String, disposition: String) async -> [String: Any] {
        let allowed = ["fresh", "watching", "acted", "snoozed", "dismissed"]
        guard allowed.contains(disposition) else {
            return ["ok": false, "error": "Invalid disposition", "allowed": allowed]
        }
        var records = dispositionRecords()
        if disposition == "fresh" {
            records.removeValue(forKey: id)
        } else {
            var record = [
                "disposition": disposition,
                "updatedAt": ISO8601DateFormatter().string(from: Date())
            ]
            if disposition == "snoozed", let until = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
                record["snoozedUntil"] = ISO8601DateFormatter().string(from: until)
            }
            records[id] = record
        }
        saveDispositionRecords(records)
        var payload = await radar()
        payload["ok"] = true
        payload["id"] = id
        payload["disposition"] = disposition
        return payload
    }

    private static func item(id: String, title: String, detail: String, reason: String, action: String, project: String, urgency: String, symbol: String, state: String, query: String, path: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "detail": detail,
            "reason": reason,
            "action": action,
            "project": project,
            "urgency": urgency,
            "symbol": symbol,
            "state": state,
            "disposition": "fresh",
            "score": 0,
            "evidence": [],
            "query": query,
            "path": path
        ]
    }

    private static func dedupe(_ items: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var output: [[String: Any]] = []
        for item in items {
            let key = "\(item["title"] ?? "")-\(item["project"] ?? "")-\(item["query"] ?? "")".lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(item)
        }
        return output
    }

    private static func rank(_ items: [[String: Any]]) -> [[String: Any]] {
        items.map { item in
            var next = item
            let scored = score(item)
            next["score"] = scored.score
            next["evidence"] = scored.evidence
            return next
        }
        .sorted {
            let left = $0["score"] as? Int ?? 0
            let right = $1["score"] as? Int ?? 0
            if left == right {
                return ($0["title"] as? String ?? "") < ($1["title"] as? String ?? "")
            }
            return left > right
        }
    }

    private static func score(_ item: [String: Any]) -> (score: Int, evidence: [String]) {
        var score = 0
        var evidence: [String] = []
        let urgency = item["urgency"] as? String ?? ""
        let state = item["state"] as? String ?? ""
        let disposition = item["disposition"] as? String ?? "fresh"
        let project = item["project"] as? String ?? ""
        let title = item["title"] as? String ?? ""
        switch urgency {
        case "Now":
            score += 50
            evidence.append("Immediate execution")
        case "Safety":
            score += 45
            evidence.append("Reliability or permission risk")
        case "Triage":
            score += 38
            evidence.append("Needs classification")
        case "Review":
            score += 34
            evidence.append("Stale or unresolved")
        case "Next":
            score += 28
            evidence.append("Project movement")
        case "Explore":
            score += 18
            evidence.append("Idea or opportunity")
        case "Context":
            score += 14
            evidence.append("Fresh working material")
        default:
            score += 10
        }
        if state == "Running" {
            score += 16
            evidence.append("Already delegated")
        } else if state == "Attention" {
            score += 12
            evidence.append("Attention state")
        }
        if disposition == "watching" {
            score += 10
            evidence.append("You marked it watching")
        }
        if !["General Brain", "System", ""].contains(project) {
            score += 6
            evidence.append("Attached to \(project)")
        }
        if !(item["path"] as? String ?? "").isEmpty {
            score += 4
            evidence.append("Has source artifact")
        }
        if title.localizedCaseInsensitiveContains("Delegated") {
            score += 12
        }
        if title.localizedCaseInsensitiveContains("Stale") {
            score += 8
        }
        return (min(score, 100), Array(evidence.prefix(5)))
    }

    private static func applyDisposition(to items: [[String: Any]]) -> [[String: Any]] {
        let records = dispositionRecords()
        let now = Date()
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let record = records[id],
                  let disposition = record["disposition"] else {
                return item
            }
            if disposition == "dismissed" || disposition == "acted" {
                return nil
            }
            if disposition == "snoozed",
               let rawUntil = record["snoozedUntil"],
               let until = ISO8601DateFormatter().date(from: rawUntil),
               until > now {
                return nil
            }
            var next = item
            next["disposition"] = disposition == "snoozed" ? "fresh" : disposition
            return next
        }
    }

    private static func dispositionRecords() -> [String: [String: String]] {
        UserDefaults.standard.dictionary(forKey: "terminalBrainRadarDispositionRecords") as? [String: [String: String]] ?? [:]
    }

    private static func saveDispositionRecords(_ records: [String: [String: String]]) {
        UserDefaults.standard.set(records, forKey: "terminalBrainRadarDispositionRecords")
    }
}

enum SetupSnapshot {
    static func setup() async -> [String: Any] {
        let status = await ControlSnapshot.status()
        let indexes = status["indexes"] as? [String: Any] ?? [:]
        let mission = status["mission"] as? [String: Any] ?? [:]
        let mcp = status["mcp"] as? [String: Any] ?? [:]
        let sync = status["sync"] as? [String: Any] ?? [:]
        let promptSafe = status["promptSafe"] as? Bool ?? false
        let codexConfig = CommandRunner.readText(Paths.codexConfig)
        let workspaceConfig = CommandRunner.readText(Paths.workspaceMCP)
        let codexReady = codexConfig.contains("[mcp_servers.local-brain]")
            && !codexConfig.contains("[mcp_servers.apple-notes]")
            && !codexConfig.contains("[mcp_servers.drafts-obsidian]")
        let workspaceReady = workspaceConfig.contains("local-brain")
            && !workspaceConfig.contains("apple-notes")
            && !workspaceConfig.contains("drafts-obsidian")

        let steps = [
            step(
                id: "app",
                title: "Terminal Brain App",
                detail: "Local control API is responding on 127.0.0.1:8765.",
                ready: true,
                action: "Keep app running",
                symbol: "macwindow"
            ),
            step(
                id: "workspace",
                title: "Workspace",
                detail: fileExists(Paths.workspace, directory: true) ? Paths.workspace : "Set the workspace path in Terminal Brain Settings.",
                ready: fileExists(Paths.workspace, directory: true),
                action: fileExists(Paths.workspace, directory: true) ? "Open Workspace" : "Open Settings",
                symbol: "folder"
            ),
            step(
                id: "brain-cli",
                title: "Start Work CLI",
                detail: fileExists(Paths.brainCLI) ? Paths.brainCLI : "Set the brain CLI path before Start Work can build packs.",
                ready: fileExists(Paths.brainCLI),
                action: fileExists(Paths.brainCLI) ? "Start Work" : "Open Settings",
                symbol: "terminal"
            ),
            step(
                id: "sync-script",
                title: "Sync Script",
                detail: fileExists(Paths.syncScript) ? Paths.syncScript : "Set the Edge Brain sync wrapper path.",
                ready: fileExists(Paths.syncScript),
                action: fileExists(Paths.syncScript) ? "Run Sync" : "Open Settings",
                symbol: "arrow.triangle.2.circlepath"
            ),
            step(
                id: "obsidian-index",
                title: "Obsidian Index",
                detail: "\(indexes["obsidianNotes"] ?? 0) notes and \(indexes["entities"] ?? 0) entities in derived memory.",
                ready: ((indexes["obsidianNotes"] as? Int) ?? 0) > 0,
                action: "Run Sync",
                symbol: "doc.text.magnifyingglass"
            ),
            step(
                id: "mission",
                title: "Mission Control",
                detail: (mission["reachable"] as? Bool ?? false) ? "\(mission["points"] ?? 0) Mission points reachable." : "Mission Control is not reachable at \(Paths.missionURL.absoluteString).",
                ready: mission["reachable"] as? Bool ?? false,
                action: "Open Mission",
                symbol: "display"
            ),
            step(
                id: "codex-mcp",
                title: "Codex MCP Config",
                detail: codexReady ? "Codex points to local-brain without auto-starting Apple Notes or Drafts." : "Register local-brain and remove prompt-prone auto-start bridges.",
                ready: codexReady,
                action: "Open Settings",
                symbol: "antenna.radiowaves.left.and.right"
            ),
            step(
                id: "workspace-mcp",
                title: "Workspace MCP Config",
                detail: workspaceReady ? "Workspace MCP points to local-brain only." : "Update workspace MCP config to route agents through Terminal Brain.",
                ready: workspaceReady,
                action: "Open Workspace",
                symbol: "folder.badge.gearshape"
            ),
            step(
                id: "prompt-safety",
                title: "Prompt Safety",
                detail: promptSafe ? "Apple Notes, Drafts, and hourly sync bridges are quiet." : "A prompt-prone bridge or launch agent is active.",
                ready: promptSafe,
                action: "Open Sources",
                symbol: "lock.shield.fill"
            ),
            step(
                id: "oracle-inbox",
                title: "Oracle Inbox",
                detail: fileExists(Paths.oracleInbox, directory: true) ? Paths.oracleInbox : "Commit an Oracle read to create the Obsidian writeback inbox.",
                ready: fileExists(Paths.oracleInbox, directory: true),
                action: fileExists(Paths.oracleInbox, directory: true) ? "Open Review" : "Ask Oracle",
                symbol: "tray.and.arrow.down.fill"
            )
        ]

        let readyCount = steps.filter { ($0["state"] as? String) == "Ready" }.count
        let attentionCount = steps.filter { ($0["state"] as? String) == "Attention" }.count

        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "readyCount": readyCount,
            "attentionCount": attentionCount,
            "mcpLocalBrainRunning": mcp["localBrainRunning"] as? Bool ?? false,
            "syncRecords": sync["records"] as? Int ?? 0,
            "steps": steps
        ]
    }

    private static func step(id: String, title: String, detail: String, ready: Bool, action: String, symbol: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "detail": detail,
            "state": ready ? "Ready" : "Attention",
            "action": action,
            "symbol": symbol
        ]
    }

    private static func fileExists(_ path: String, directory: Bool? = nil) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        if let directory {
            return isDirectory.boolValue == directory
        }
        return true
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
    let headers: [String: String]

    var jsonBody: [String: Any]? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var contentLength = 0
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 {
                let key = pair[0].lowercased()
                guard headers[key] == nil else { return nil }
                headers[key] = pair[1]
                if key == "content-length" {
                    guard let length = Int(pair[1]), (0...16_384).contains(length) else { return nil }
                    contentLength = length
                }
            }
        }

        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        let path = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? parts[1]
        return HTTPRequest(method: parts[0], path: path, body: body, headers: headers)
    }
}

struct HTTPResponse {
    let data: Data

    static func json(_ status: Int, _ body: [String: Any]) -> HTTPResponse {
        let payload = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : "Not Found"
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Content-Length: \(payload.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(payload)
        return HTTPResponse(data: data)
    }

    static func text(_ status: Int, _ body: String) -> HTTPResponse {
        let payload = Data(body.utf8)
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : "Not Found"
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: text/markdown; charset=utf-8\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Content-Length: \(payload.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(payload)
        return HTTPResponse(data: data)
    }
}

enum ControlSnapshot {
    static func status() async -> [String: Any] {
        async let localBrain = pgrep("brain-kernel/server.mjs")
        async let appleNotesMCP = pgrep("apple-notes-mcp/server.mjs")
        async let draftsMCP = pgrep("drafts-obsidian-mcp/server.mjs")
        async let launchd = launchAgentStatus()
        async let mission = missionBrain()

        let stats = CommandRunner.readJSON(Paths.statsJSON)
        let agent = CommandRunner.readJSON(Paths.agentHistoryStatsJSON)
        let sync = CommandRunner.readJSON(Paths.edgeSyncStateJSON)
        let syncRecords = sync["records"] as? [String: Any]
        let localBrainText = await localBrain
        let appleNotesText = await appleNotesMCP
        let draftsText = await draftsMCP
        let launchdText = await launchd
        let missionValue = await mission

        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "app": [
                "name": "Terminal Brain",
                "bundleID": "com.franklin.terminal-brain",
                "controlAPI": "http://127.0.0.1:8765"
            ],
            "mcp": [
                "localBrainRunning": !localBrainText.isEmpty,
                "appleNotesBridgeRunning": !appleNotesText.isEmpty,
                "draftsBridgeRunning": !draftsText.isEmpty
            ],
            "sync": [
                "launchAgentLoaded": !launchdText.contains("Could not find service"),
                "records": sync["exported"] as? Int ?? sync["recordCount"] as? Int ?? syncRecords?.count ?? 0,
                "updatedAt": sync["updatedAt"] as? String ?? "unknown"
            ],
            "indexes": [
                "obsidianNotes": stats["notes"] as? Int ?? 0,
                "entities": stats["entities"] as? Int ?? 0,
                "agentRecords": agent["records"] as? Int ?? 0,
                "agentSessions": agent["sessions"] as? Int ?? 0
            ],
            "mission": missionValue ?? ["reachable": false],
            "promptSafe": appleNotesText.isEmpty && draftsText.isEmpty && launchdText.contains("Could not find service")
        ]
    }

    static func sources() async -> [String: Any] {
        let status = await status()
        let indexes = status["indexes"] as? [String: Any] ?? [:]
        let sync = status["sync"] as? [String: Any] ?? [:]
        let mission = status["mission"] as? [String: Any] ?? [:]
        return [
            "sources": [
                [
                    "id": "obsidian",
                    "name": "Obsidian Vault",
                    "mode": "indexed",
                    "records": indexes["obsidianNotes"] as? Int ?? 0,
                    "sensitive": false
                ],
                [
                    "id": "agent-history",
                    "name": "Codex / Claude Histories",
                    "mode": "derived-memory",
                    "records": indexes["agentRecords"] as? Int ?? 0,
                    "sensitive": true
                ],
                [
                    "id": "drafts",
                    "name": "Drafts",
                    "mode": "manual",
                    "records": sync["records"] as? Int ?? 0,
                    "sensitive": true
                ],
                [
                    "id": "apple-notes",
                    "name": "Apple Notes",
                    "mode": "explicit-only",
                    "records": 0,
                    "sensitive": true
                ],
                [
                    "id": "mission-control",
                    "name": "Mission Control",
                    "mode": (mission["reachable"] as? Bool ?? false) ? "reachable" : "offline",
                    "records": mission["points"] as? Int ?? 0,
                    "sensitive": false
                ]
            ]
        ]
    }

    static func briefing() async -> [String: Any] {
        let status = await status()
        let indexes = status["indexes"] as? [String: Any] ?? [:]
        let sync = status["sync"] as? [String: Any] ?? [:]
        let mission = status["mission"] as? [String: Any] ?? [:]
        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "items": [
                [
                    "title": "Brain Coverage",
                    "detail": "\(indexes["obsidianNotes"] ?? 0) Obsidian notes, \(indexes["entities"] ?? 0) entities, \(indexes["agentRecords"] ?? 0) derived agent-memory records."
                ],
                [
                    "title": "Edge Sync",
                    "detail": "\(sync["records"] ?? 0) records tracked for remote sync. Updated \(sync["updatedAt"] ?? "unknown")."
                ],
                [
                    "title": "Mission Control",
                    "detail": (mission["reachable"] as? Bool ?? false) ? "Remote brain reachable with \(mission["points"] ?? 0) points." : "Remote brain not reachable."
                ],
                [
                    "title": "Prompt Safety",
                    "detail": (status["promptSafe"] as? Bool ?? false) ? "Apple Notes/Drafts bridges and hourly sync are not auto-running." : "One or more prompt-prone bridges is active."
                ]
            ]
        ]
    }

    static func permissions() -> [String: Any] {
        [
            "appleNotes": [
                "startupAccess": false,
                "manualCheckOnly": true,
                "owner": "Terminal Brain.app",
                "bundleID": "com.franklin.terminal-brain"
            ],
            "drafts": [
                "startupAccess": false,
                "manualBridgeOnly": true
            ],
            "obsidian": [
                "vaultPath": Paths.workspace,
                "readDerivedIndex": true
            ]
        ]
    }

    static func latestContextPack() -> [String: Any] {
        let path = newestContextPackPath()
        guard !path.isEmpty else {
            return [
                "ok": false,
                "path": "",
                "title": "",
                "detail": "No context pack found."
            ]
        }

        let url = URL(fileURLWithPath: path)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        return [
            "ok": true,
            "path": path,
            "title": url.deletingPathExtension().lastPathComponent,
            "modifiedAt": ISO8601DateFormatter().string(from: modified)
        ]
    }

    static func latestContextPackMarkdown() -> String {
        let path = newestContextPackPath()
        guard !path.isEmpty,
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              !text.isEmpty else {
            return "# Terminal Brain Context Pack\n\nNo context pack found."
        }
        return text
    }

    static func newestContextPackPath() -> String {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: Paths.contextPacks),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> (Date, URL)? in
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return nil
                }
                return (modified, url)
            }
            .sorted { $0.0 > $1.0 }
            .first?.1.path ?? ""
    }

    private static func pgrep(_ pattern: String) async -> String {
        let result = await CommandRunner.run("/usr/bin/pgrep", ["-fl", pattern])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func launchAgentStatus() async -> String {
        let result = await CommandRunner.run("/bin/launchctl", ["print", "gui/\(getuid())/com.franklin.edge-brain-sync"])
        return [result.stdout, result.stderr].joined(separator: "\n")
    }

    private static func missionBrain() async -> [String: Any]? {
        guard var components = URLComponents(url: Paths.missionURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/api/brain"
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let brain = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return [
            "reachable": true,
            "points": brain["total_points"] as? Int ?? brain["points"] as? Int ?? 0
        ]
    }
}

private extension String {
    func prefixString(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
