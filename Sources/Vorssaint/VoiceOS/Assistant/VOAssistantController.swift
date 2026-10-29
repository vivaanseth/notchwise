// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Agent/AgentController.swift) into Vorssaint + VoiceOS.

import AppKit

enum VOAssistantPhase: Equatable {
    case collapsed, idle, listening, transcribing, thinking, answered
}

enum VOActionState: Equatable {
    case needsConfirm, running, done(String), failed(String), cancelled
}

struct VOAssistantActionItem: Identifiable, Equatable {
    var id: UUID { action.id }
    var action: VOAssistantAction
    var state: VOActionState
    var editing = false
    var files: [URL] = []
}

struct VOAssistantTurn: Identifiable, Equatable {
    let id = UUID()
    var query: String
    var provider: VOProviderID
    var say = ""
    var detail: String?
    var actions: [VOAssistantActionItem] = []
    var error: String?
    var thinking = true
    var usedScreen = false
    var via = ""          // which brain answered, and why if it wasn't the local one
}

/// Agent Mode: hold ⌘ (or type into the notch), say what you want, and VoiceOS answers out loud
/// and prepares actions — anything that sends or changes something waits for confirmation.
@MainActor
final class VOAssistantController: ObservableObject {
    static let shared = VOAssistantController()

    @Published var expanded = false
    @Published var phase: VOAssistantPhase = .collapsed
    @Published var input = ""
    @Published var live = ""
    @Published var level: Float = 0
    @Published var turns: [VOAssistantTurn] = []
    @Published var hint: String?
    @Published var focusToken = 0
    @Published var hovering = false {
        didSet { hovering ? cancelAutoCollapse() : scheduleAutoCollapse() }
    }

    private let settings = VOSettings.shared
    private var session: VOSpeechSession?
    private var screenshot: Task<URL?, Never>?
    private var context: VOFrontContext?
    /// Text selected in the app in front when the island opened, which the
    /// hub offers quick asks about.
    var frontSelection: String? { context?.selectedText }
    private var listenStarted = Date()
    private var collapseWork: DispatchWorkItem?
    private var lastActivity = Date.distantPast
    private var running: Task<Void, Never>?
    /// The island closed the page itself, so closing must not ask it again.
    private var closingFromIsland = false

    // MARK: - Open / close

    func open(focus: Bool) {
        if Date().timeIntervalSince(lastActivity) > 300, !hasPendingWork { turns.removeAll() }
        if context == nil || !expanded { context = VOAccessibility.frontContext() }
        expanded = true
        if phase == .collapsed { phase = turns.isEmpty ? .idle : .answered }
        cancelAutoCollapse()
        VOIsland.present(focus: focus)
        if focus {
            focusToken += 1
        }
    }

    func toggle() { expanded ? close() : open(focus: true) }

    /// The island showed the assistant's page by itself: the idle island
    /// clicked, its shortcut, a section picked, or a strip.
    func islandDidOpen(focus: Bool) {
        if !expanded {
            if Date().timeIntervalSince(lastActivity) > 300, !hasPendingWork { turns.removeAll() }
            if context == nil { context = VOAccessibility.frontContext() }
            expanded = true
            if phase == .collapsed { phase = turns.isEmpty ? .idle : .answered }
            if focus { focusToken += 1 }
            scheduleAutoCollapse()
        }
    }

    /// The island closed, or moved to another page.
    func islandDidClose() {
        guard expanded else { return }
        closingFromIsland = true
        close()
        closingFromIsland = false
    }

    /// Listening, transcribing, thinking or waiting on a confirmation: the
    /// island keeps the page open through clicks away, as VoiceOS's notch did.
    var holdsIsland: Bool { phase == .listening || phase == .transcribing || hasPendingWork }

    /// What the closed island shows while the assistant works.
    var islandActivity: VOIslandActivity? {
        if phase == .listening { return .listening }
        if phase == .transcribing || turns.contains(where: \.thinking) { return .thinking }
        if turns.contains(where: { $0.actions.contains { $0.state == .needsConfirm } }) { return .confirming }
        if VOAssistantVoice.shared.speaking { return .speaking }
        return nil
    }

    func close() {
        session?.cancel()
        session = nil
        VOAssistantVoice.shared.stop()
        cancelAutoCollapse()
        expanded = false
        phase = .collapsed
        hint = nil
        live = ""
        level = 0
        // Closed by the island itself, it keeps its keyboard for the page it
        // moved to, or has already given it back as it closed.
        if !closingFromIsland {
            VOIsland.releaseKeyFocus(reactivate: context?.pid)
            VOIsland.dismiss()
        }
        context = nil
    }

    var hasPendingWork: Bool {
        turns.contains { t in t.thinking || t.actions.contains { $0.state == .needsConfirm || $0.state == .running } }
    }

    // MARK: - Voice

    func startListening() {
        if VORuntime.microphoneIsMuted {
            open(focus: false)
            hint = VORuntime.microphoneMutedHint
            return
        }
        let perms = VOPermissions.shared
        perms.refresh()
        guard perms.microphone else {
            open(focus: false)
            hint = "Allow microphone access to talk to VoiceOS."
            perms.requestMicrophone()
            return
        }
        if settings.speechEngine == .apple && !perms.speech {
            open(focus: false)
            hint = "Allow speech recognition to talk to VoiceOS."
            perms.requestSpeech()
            return
        }
        VOAssistantVoice.shared.stop()
        // Kokoro loads while the question is asked, ready for the answer.
        VOAssistantVoice.shared.warmUp()
        VODictationController.shared.cancel()
        if !expanded { context = VOAccessibility.frontContext() }
        if Date().timeIntervalSince(lastActivity) > 300, !hasPendingWork { turns.removeAll() }
        expanded = true
        phase = .listening
        VOIsland.present(focus: false)
        hint = nil
        live = ""
        cancelAutoCollapse()
        screenshot = wantsScreenshot ? Task { await VOScreenGrab.captureAroundCursor() } : nil

        let s = VOSpeechSession(engine: settings.speechEngine)
        s.onPartial = { [weak self] t in self?.live = t }
        s.onLevel = { [weak self] l in self?.level = l }
        do {
            try s.start()
            session = s
            listenStarted = Date()
            VOSounds.start()
        } catch {
            phase = turns.isEmpty ? .idle : .answered
            hint = error.localizedDescription
        }
    }

    func stopListening() {
        guard phase == .listening, let s = session else { return }
        session = nil
        VOSounds.stop()
        phase = .transcribing
        level = 0
        Task {
            let (text, _) = await s.stop()
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                phase = turns.isEmpty ? .idle : .answered
                hint = "Didn't catch that — hold \(settings.agentTrigger.label) and speak."
                scheduleAutoCollapse(after: 4)
            } else {
                submit(t)
            }
        }
    }

    func cancelListening() {
        session?.cancel()
        session = nil
        level = 0
        if turns.isEmpty { close() } else { phase = .answered; scheduleAutoCollapse() }
    }

    private var wantsScreenshot: Bool { settings.isEnabled(.pointAndAsk) && VOScreenGrab.hasPermission }

    // MARK: - Asking

    func submit(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        input = ""
        live = ""
        hint = nil
        lastActivity = Date()
        if context == nil { context = VOAccessibility.frontContext() }
        if screenshot == nil && wantsScreenshot { screenshot = Task { await VOScreenGrab.captureAroundCursor() } }
        let provider = settings.agentProvider
        let turn = VOAssistantTurn(query: query, provider: provider)
        let history = Array(turns.suffix(6))
        turns.append(turn)
        if turns.count > 20 { turns.removeFirst(turns.count - 20) }
        phase = .thinking
        cancelAutoCollapse()

        let ctx = context ?? VOAccessibility.frontContext()
        let shotTask = screenshot
        screenshot = nil
        let spoken = Date().timeIntervalSince(listenStarted)
        running = Task { await run(turnID: turn.id, query: query, provider: provider, ctx: ctx, history: history, shot: shotTask, spoken: spoken) }
    }

    /// Screenshots add ~5–10s per request, so only send one when the request points at something on screen.
    static func refersToScreen(_ q: String) -> Bool {
        let pattern = #"(?i)\b(this|that|these|those|here|screen|page|window|tab|site|website|email|message|thread|document|doc|article|chart|graph|table|image|picture|photo|video|code|error|bug|him|her|his|hers|their|them|it's|selected|highlighted|above|below|pointing|looking|see|summari[sz]e|explain|translate|reply|respond|read|linkedin|who is|what is this|what's this)\b"#
        return q.range(of: pattern, options: .regularExpression) != nil
    }

    /// Stricter than `refersToScreen`: only phrasing that clearly points at something visible. Used to decide
    /// whether a local request must go to a cloud model that can see images.
    static func pointsAtScreen(_ q: String) -> Bool {
        let pattern = #"(?i)(\bon (my|the) screen\b|\bwhat am i looking at\b|\b(look|see) (at )?this\b|\bwhat('s| is) (this|that)\b|\bthis (page|email|e-mail|message|thread|doc|document|article|chart|graph|table|image|picture|photo|video|code|error|bug|site|website|tab|window|text|paragraph|sentence|person|guy|profile|product|item|slide|spreadsheet)\b|\b(summari[sz]e|explain|translate|read|proofread|rewrite) (this|that|it|the page|the email)\b|\breply to (this|him|her|them)\b|\bwho is (this|he|she)\b|\b(his|her|their) (linkedin|email|number|profile|website)\b|\bfind (his|her)\b)"#
        return q.range(of: pattern, options: .regularExpression) != nil
    }

    /// Developer self-test: never execute actions, only show them.
    var dryRun = false

    private func run(turnID: UUID, query: String, provider: VOProviderID, ctx: VOFrontContext, history: [VOAssistantTurn],
                     shot: Task<URL?, Never>?, spoken: Double) async {
        // Route: the local model handles almost everything; the cloud AI only gets what genuinely needs it.
        var route = provider
        var routeModel: String? = nil
        var reason: String? = nil
        let lookup = VOBrainRouter.lookup(query)
        let wantsScreen = lookup == nil && (provider.isLocal ? Self.pointsAtScreen(query) : Self.refersToScreen(query)) && shot != nil
        if provider.isLocal, lookup == nil, let r = VOBrainRouter.reasonToEscalate(query: query, hasImage: wantsScreen, selection: ctx.selectedText) {
            if let target = VOBrainRouter.escalationTarget() {
                route = target.provider
                routeModel = target.model
                reason = r
            } else if r != "needs to see your screen" {
                // Long writing/analysis is beyond the local model; say so right away instead of grinding for a minute.
                if let shot { Task.detached { if let url = await shot.value { try? FileManager.default.removeItem(at: url) } } }
                let say = "That needs a bigger model than the local one (\(r)). \(VOBrainRouter.escalationBlockedReason)"
                update(turnID) { $0.say = say; $0.thinking = false; $0.via = Self.label(.ollama, model: nil, reason: nil) }
                phase = .answered
                lastActivity = Date()
                VOAssistantVoice.shared.speak(say) { [weak self] in self?.scheduleAutoCollapse() }
                return
            }
        }
        var image: URL? = nil
        if let shot {
            if wantsScreen && !route.isLocal {
                image = await shot.value
            } else {
                // Local models can't see images; don't wait for a capture we won't send.
                Task.detached { if let url = await shot.value { try? FileManager.default.removeItem(at: url) } }
            }
        }
        update(turnID) {
            $0.usedScreen = image != nil
            $0.provider = route
            $0.via = Self.label(route, model: routeModel, reason: reason)
        }

        // The answer is spoken a sentence at a time as it is written.
        VOAssistantVoice.shared.beginStream()
        do {
            var parsed: Parsed
            if let found = lookup {
                // A lookup is a search, opened at once; no model is asked.
                if let image { try? FileManager.default.removeItem(at: image) }
                route = .ollama
                routeModel = nil
                reason = nil
                update(turnID) { $0.provider = .ollama; $0.via = "Search" }
                parsed = await Self.resolve(found)
            } else if route.isLocal {
                parsed = try await askLocal(turnID: turnID, query: query, ctx: ctx, history: history)
                if parsed.escalate {
                    if let target = VOBrainRouter.escalationTarget() {
                        route = target.provider
                        routeModel = target.model
                        reason = "the local model asked for help"
                        // Whatever the local model began to say gives way to the answer.
                        VOAssistantVoice.shared.beginStream()
                        update(turnID) {
                            $0.provider = route
                            $0.say = ""
                            $0.via = Self.label(route, model: routeModel, reason: reason)
                        }
                        parsed = try await askCloud(turnID: turnID, provider: route, model: routeModel, query: query,
                                                    ctx: ctx, history: history, image: nil)
                    } else {
                        parsed.say = "That one needs a bigger model than the local one. \(VOBrainRouter.escalationBlockedReason)"
                    }
                }
            } else {
                parsed = try await askCloud(turnID: turnID, provider: route, model: routeModel, query: query,
                                            ctx: ctx, history: history, image: image)
            }
            if let image { try? FileManager.default.removeItem(at: image) }

            let items: [VOAssistantActionItem] = parsed.actions.compactMap { a in
                guard VOActionKit.knownTypes.contains(a.type) else { return nil }
                let spec = VOActionKit.spec(a.type)
                if let cap = spec.capability, !settings.isEnabled(cap) { return nil }
                return VOAssistantActionItem(action: a, state: spec.confirm ? .needsConfirm : .running)
            }
            update(turnID) {
                $0.say = parsed.say
                $0.detail = parsed.detail
                $0.actions = items
                $0.thinking = false
            }
            // Something to confirm brings the page back, as VoiceOS's notch
            // stayed open for it.
            if !expanded, items.contains(where: { $0.state == .needsConfirm }) { open(focus: false) }
            parsed.remember.forEach { settings.addMemory($0) }
            phase = .answered
            lastActivity = Date()
            VOAssistantVoice.shared.finishStream(parsed.say) { [weak self] in self?.scheduleAutoCollapse() }
            for item in items where item.state == .running {
                if dryRun { updateAction(turnID, item.id) { $0.state = .done("(dry run — not executed)") }; continue }
                await perform(turnID: turnID, actionID: item.id, secondary: false)
            }
            VOHistoryStore.shared.add(VOHistoryItem(mode: .agent, appName: ctx.appName, bundleID: ctx.bundleID, transcript: query,
                                                output: [parsed.say, parsed.detail ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                                                provider: lookup != nil ? "Search"
                                                    : Self.label(route, model: routeModel, reason: reason), duration: min(spoken, 120),
                                                words: VOTextCleaner.wordCount(query), polished: true))
        } catch {
            if let image { try? FileManager.default.removeItem(at: image) }
            update(turnID) {
                $0.thinking = false
                $0.error = error.localizedDescription
            }
            phase = .answered
            VOSounds.error()
            VOHistoryStore.shared.add(VOHistoryItem(mode: .agent, appName: ctx.appName, bundleID: ctx.bundleID, transcript: query,
                                                output: "", provider: Self.label(route, model: routeModel, reason: reason),
                                                duration: min(spoken, 120), words: VOTextCleaner.wordCount(query), polished: false,
                                                error: error.localizedDescription))
        }
    }

    /// A person looked up on a site opens on their profile: the first one
    /// the search engine finds that carries every word of their name, with
    /// any others listed. Without one, the site's own search opens instead.
    private static func resolve(_ found: (say: String, action: VOAssistantAction,
                                          person: (site: VOWebLookup.Site, name: String)?)) async -> Parsed {
        guard let person = found.person else {
            return Parsed(say: found.say, detail: nil, actions: [found.action], remember: [])
        }
        let site = person.site
        let hits = VOWebLookup.profiles(await VOWebLookup.search("\(person.name) \(site.name)"), on: site, named: person.name)
        guard let best = hits.first else {
            return Parsed(say: "I couldn't pin down one profile, so here's \(site.name)'s search for \(person.name).",
                          detail: nil, actions: [found.action], remember: [])
        }
        func link(_ hit: VOWebLookup.Hit) -> String {
            "[\(hit.title.replacingOccurrences(of: "]", with: ")"))](\(hit.url.absoluteString))"
        }
        var detail = link(best)
        let others = hits.dropFirst().prefix(3)
        if !others.isEmpty {
            detail += "\n\nAlso named \(person.name):\n" + others.map { "- " + link($0) }.joined(separator: "\n")
                + "\n- [Everyone on \(site.name)](\(found.action["url"]))"
        }
        return Parsed(say: "Opening \(person.name)'s \(site.name).", detail: detail,
                      actions: [VOAssistantAction(type: "open_url", fields: ["url": best.url.absoluteString])], remember: [])
    }

    /// Small local model with a strict JSON schema, few-shot prompt and sanity checks.
    private func askLocal(turnID: UUID, query: String, ctx: VOFrontContext, history: [VOAssistantTurn]) async throws -> Parsed {
        let calc = VOBrainRouter.calculatorHint(query)
        let raw = try await VOProviderManager.shared.complete(
            .ollama, system: VOLocalPrompts.agentSystem(),
            prompt: VOLocalPrompts.agentUser(query: query, ctx: ctx, history: history, calculator: calc),
            jsonSchema: VOLocalPrompts.agentSchema(), maxTokens: 220, timeout: 90
        ) { [weak self] partial in
            guard let self, let say = Self.partialSay(partial), !say.isEmpty else { return }
            self.update(turnID) { $0.say = say }
            VOAssistantVoice.shared.stream(say)
        }
        var parsed = Self.parse(raw)
        parsed.actions = VOBrainRouter.fixDates(parsed.actions.filter { VOBrainRouter.plausible($0.type, query: query) }, query: query)
        if let calc, let result = calc.split(separator: "=").last?.trimmingCharacters(in: .whitespaces),
           !parsed.escalate, !parsed.say.contains(result) {
            let expr = calc.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) ?? ""
            parsed.say = [parsed.say, "\(expr) is \(result)."].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return parsed
    }

    private func askCloud(turnID: UUID, provider: VOProviderID, model: String?, query: String, ctx: VOFrontContext,
                          history: [VOAssistantTurn], image: URL?) async throws -> Parsed {
        let raw = try await VOProviderManager.shared.complete(
            provider, system: systemPrompt(ctx: ctx, hasImage: image != nil),
            prompt: userPrompt(query: query, ctx: ctx, history: history),
            images: image.map { [$0] } ?? [], model: model
        ) { [weak self] partial in
            guard let self, let say = Self.partialSay(partial), !say.isEmpty else { return }
            self.update(turnID) { $0.say = say }
            VOAssistantVoice.shared.stream(say)
        }
        var parsed = Self.parse(raw)
        parsed.escalate = false
        return parsed
    }

    /// "Local · qwen2.5:1.5b" or "Claude haiku · long writing".
    static func label(_ p: VOProviderID, model: String?, reason: String?) -> String {
        let m = model ?? VOProviderManager.shared.model(for: p)
        let name = p.isLocal ? "Local" : p.displayName
        let base = m.isEmpty ? name : "\(name) · \(m)"
        return reason.map { "\(base) — \($0)" } ?? base
    }

    // MARK: - Actions

    func confirm(turnID: UUID, actionID: UUID, secondary: Bool = false) {
        updateAction(turnID, actionID) { $0.state = .running; $0.editing = false }
        Task { await perform(turnID: turnID, actionID: actionID, secondary: secondary) }
    }

    func cancelAction(turnID: UUID, actionID: UUID) {
        updateAction(turnID, actionID) { $0.state = .cancelled; $0.editing = false }
        scheduleAutoCollapse()
    }

    func toggleEdit(turnID: UUID, actionID: UUID) {
        updateAction(turnID, actionID) { $0.editing.toggle() }
        if let item = action(turnID, actionID), item.editing {
            VOIsland.focusInput()
        }
    }

    func setField(turnID: UUID, actionID: UUID, key: String, value: String) {
        updateAction(turnID, actionID) { $0.action[key] = value }
    }

    private func perform(turnID: UUID, actionID: UUID, secondary: Bool) async {
        guard let item = action(turnID, actionID) else { return }
        do {
            let outcome = try await VOActionKit.execute(item.action, secondary: secondary)
            updateAction(turnID, actionID) { $0.state = .done(outcome.message); $0.files = outcome.files }
        } catch {
            updateAction(turnID, actionID) { $0.state = .failed(error.localizedDescription) }
        }
        lastActivity = Date()
        scheduleAutoCollapse()
    }

    private func action(_ turnID: UUID, _ actionID: UUID) -> VOAssistantActionItem? {
        turns.first { $0.id == turnID }?.actions.first { $0.id == actionID }
    }

    private func update(_ id: UUID, _ change: (inout VOAssistantTurn) -> Void) {
        guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[i])
    }

    private func updateAction(_ turnID: UUID, _ actionID: UUID, _ change: (inout VOAssistantActionItem) -> Void) {
        update(turnID) { t in
            if let j = t.actions.firstIndex(where: { $0.id == actionID }) { change(&t.actions[j]) }
        }
    }

    // MARK: - Auto-collapse

    func scheduleAutoCollapse(after seconds: Double = 12) {
        cancelAutoCollapse()
        guard expanded, phase == .answered || phase == .idle else { return }
        let w = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.expanded, !self.hovering, !self.hasPendingWork, !VOAssistantVoice.shared.speaking,
                      self.phase == .answered || self.phase == .idle,
                      !VOIsland.isTyping else { return }
                // The pointer on the island holds it open, as hovering VoiceOS's notch did.
                if VOIsland.pointerInside { self.scheduleAutoCollapse(after: 3); return }
                self.close()
            }
        }
        collapseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func cancelAutoCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    // MARK: - Prompting

    private func systemPrompt(ctx: VOFrontContext, hasImage: Bool) -> String {
        let now = Date().formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
        var actions: [String] = []
        func add(_ cap: VOAssistantCapability?, _ line: String) {
            if let cap, !settings.isEnabled(cap) { return }
            actions.append("  " + line)
        }
        add(.messages, #"{"type":"send_message","to":"contact name, phone or email","body":"message text"}  — send an iMessage"#)
        add(.email, #"{"type":"send_email","to":"contact name or email","subject":"…","body":"full email body"}  — send an email via Apple Mail"#)
        add(.calendar, #"{"type":"create_event","title":"…","start":"2026-10-26T15:00:00","duration_minutes":"30","location":"optional"}  — add a calendar event"#)
        add(.reminders, #"{"type":"create_reminder","title":"…","due":"2026-10-26T17:00:00"}  — set a reminder (due optional)"#)
        add(.notes, #"{"type":"create_note","title":"…","body":"…"}  — save a note in Apple Notes"#)
        add(.webSearch, #"{"type":"web_search","query":"…"}  — open a web search in the browser"#)
        add(.openApps, #"{"type":"open_url","url":"https://…"}  — open a website"#)
        add(.openApps, #"{"type":"open_app","name":"App Name"}  — open a Mac app"#)
        add(.findFiles, #"{"type":"find_files","query":"filename or keywords"}  — find files with Spotlight"#)
        add(.shortcuts, #"{"type":"run_shortcut","name":"Shortcut name","input":"optional"}  — run one of the user's Shortcuts"#)
        add(.claudeCode, #"{"type":"code_task","prompt":"coding task","folder":"~/path (optional)"}  — hand a coding task to Claude Code in Terminal"#)
        add(nil, #"{"type":"type_text","text":"…"}  — type text into the app the user is in (use when they ask you to write, draft or reply right here)"#)
        if ctx.selectedText != nil && settings.isEnabled(.editSelection) {
            add(nil, #"{"type":"replace_selection","text":"…"}  — replace the user's selected text (rewrite, translate, fix)"#)
        }
        add(nil, #"{"type":"copy_text","text":"…"}  — copy text to the clipboard"#)

        let memory = settings.memories.isEmpty ? "" : "\nWhat you know about the user:\n" + settings.memories.map { "- \($0)" }.joined(separator: "\n")
        let screen = hasImage ? """

        A screenshot of the user's screen is attached. A red circle marks where their cursor is pointing — \
        "this", "that", "here", "him", "her" usually mean whatever is under or right next to it.
        """ : ""
        let promptTip = settings.isEnabled(.createPrompt)
            ? "\nIf the user asks you to write a prompt for another AI tool, produce a clear, well-structured prompt (use type_text to put it where they are)." : ""

        return """
        You are VoiceOS, a voice assistant that lives in the notch at the top of the user's Mac. The user talks to you while working in other apps, and your reply is read aloud.
        It is now \(now) (time zone \(TimeZone.current.identifier)). The user's name is \(settings.displayName).\(memory)

        You have no tools and must not write tool or function-call syntax (no <function_calls>, no XML). \
        VoiceOS performs the actions you list in the JSON itself.
        Respond with ONLY one JSON object — no code fences, no text before or after it:
        {"say": string, "detail": string (optional), "actions": array (optional), "remember": array of strings (optional)}

        - "say": what you say out loud. One or two short, natural, conversational sentences. No markdown, lists or URLs. \
        When you take an action, say what you did or prepared ("Drafted a reply to Maya — take a look.").
        - "detail": optional markdown shown under the spoken line for answers that need more than two sentences (steps, lists, summaries, code). Omit for simple replies.
        - "actions": things to do on the Mac. Use only these:
        \(actions.joined(separator: "\n"))
          Use ISO 8601 local times for dates and times. Use people's names exactly as the user said them — VoiceOS looks them up in Contacts. \
        Write message and email bodies in the user's voice, ready to send. Anything that sends or changes something is shown to the user for confirmation first, so propose it confidently.
        - "remember": optional short durable facts the user just revealed about themselves or their preferences (e.g. "Manager is Tommy"). Usually omit.\(screen)\(promptTip)
        If you can't do something with these actions, say so briefly and help as best you can.
        """
    }

    private func userPrompt(query: String, ctx: VOFrontContext, history: [VOAssistantTurn]) -> String {
        var s = "<context>\nApp in front: \(ctx.appName)"
        if let w = ctx.windowTitle, !w.isEmpty { s += "\nWindow: \(w)" }
        if let sel = ctx.selectedText { s += "\nSelected text:\n\"\"\"\n\(sel.prefix(6000))\n\"\"\"" }
        s += "\n</context>\n"
        let past = history.filter { !$0.thinking }
        if !past.isEmpty {
            s += "<conversation>\n"
            for t in past {
                s += "User: \(t.query)\n"
                let reply = [t.say, t.detail ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
                s += "VoiceOS: \(t.error == nil ? reply : "(failed)")\n"
            }
            s += "</conversation>\n"
        }
        s += "User request: \(query)\n\nReply with the single JSON object only."
        return s
    }

    struct Parsed {
        var say: String
        var detail: String?
        var actions: [VOAssistantAction]
        var remember: [String]
        var escalate = false
    }

    /// Every balanced top-level {...} in the text (string-aware), in order.
    nonisolated static func jsonObjects(in text: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var depth = 0, inString = false, escaped = false
        var start: String.Index?
        for i in text.indices {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = depth > 0
            case "{":
                if depth == 0 { start = i }
                depth += 1
            case "}":
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let s = start, let data = String(text[s...i]).data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    out.append(obj)
                }
            default: break
            }
        }
        return out
    }

    static func parse(_ raw: String) -> Parsed {
        let t = VODictationController.stripWrapping(raw)
        let objects = jsonObjects(in: t)
        if let obj = objects.last(where: { $0["say"] != nil }) ?? objects.last(where: { $0["actions"] != nil }) {
            let detail = (obj["detail"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let actions = (obj["actions"] as? [[String: Any]] ?? []).compactMap(VOAssistantAction.init(json:))
            var say = (obj["say"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let escalate = obj["escalate"] as? Bool ?? false
            if say.isEmpty && detail == nil && !escalate { say = actions.isEmpty ? "Done." : "Here's what I've got." }
            return Parsed(say: say, detail: detail, actions: actions, remember: obj["remember"] as? [String] ?? [], escalate: escalate)
        }
        // Truncated or malformed JSON: salvage the spoken line rather than showing raw JSON.
        if t.hasPrefix("{") {
            let escalate = t.range(of: #""escalate"\s*:\s*true"#, options: .regularExpression) != nil
            let say = partialSay(t) ?? ""
            return Parsed(say: escalate ? "" : (say.isEmpty ? "Sorry, I couldn't put that together." : say),
                          detail: nil, actions: [], remember: [], escalate: escalate)
        }
        return Parsed(say: t, detail: nil, actions: [], remember: [])
    }

    /// Pulls the growing "say" string out of half-finished JSON so it can stream into the notch.
    static func partialSay(_ s: String) -> String? {
        guard let r = s.range(of: #""say"\s*:\s*""#, options: .regularExpression) else { return nil }
        var out = ""
        var escape = false
        for ch in s[r.upperBound...] {
            if escape {
                out.append(ch == "n" ? "\n" : ch)
                escape = false
            } else if ch == "\\" {
                escape = true
            } else if ch == "\"" {
                break
            } else {
                out.append(ch)
            }
        }
        return out
    }
}
