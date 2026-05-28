import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var showHistory = false

    private var lang: AppLanguage { AppLanguage.current }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.messages.isEmpty && viewModel.currentConversation == nil {
                    ScrollView {
                        emptyState
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { isInputFocused = false }
                } else {
                    messageList
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .background(Color.appCardSecondary)
            .navigationTitle(viewModel.currentConversation?.title ?? lang.chatEmptyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundStyle(Color.appAccent)
                    }
                    .accessibilityLabel(lang.chatHistory)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Image(systemName: "plus.bubble")
                            .foregroundStyle(Color.appAccent)
                    }
                    .accessibilityLabel(AppLanguage.current.accessibilityNewConversation)
                }
            }
            .sheet(isPresented: $showHistory) {
                ConversationHistoryView(viewModel: viewModel, isPresented: $showHistory)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(LinearGradient.accentSoftGradient)
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)
            }
            .padding(.top, 32)

            VStack(spacing: 6) {
                Text(lang.chatEmptyTitle)
                    .font(.title3)
                    .fontWeight(.bold)

                Text(lang.chatEmptySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                suggestionCard(lang.chatSuggestion1, icon: "washer")
                suggestionCard(lang.chatSuggestion2, icon: "bolt")
                suggestionCard(lang.chatSuggestion3, icon: "house.lodge")
            }

            // Recent conversations quick access
            if !viewModel.conversations.isEmpty {
                recentConversations
            }
        }
        .padding(AppStyle.paddingLarge)
    }

    private var recentConversations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang.chatRecentConversations)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button(lang.chatSeeAll) {
                    showHistory = true
                }
                .font(.caption)
                .foregroundStyle(Color.appAccent)
            }

            ForEach(viewModel.conversations.prefix(3)) { conv in
                Button {
                    Task { await viewModel.loadConversation(conv) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.caption)
                            .foregroundStyle(Color.appAccent)

                        Text(conv.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(conv.updatedAt.relativeFormatted)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.appCard)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusSmall))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func suggestionCard(_ text: String, icon: String) -> some View {
        Button {
            viewModel.queryText = text
            viewModel.sendQuery()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 28)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusSmall))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isSearching {
                        searchingIndicator
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var searchingIndicator: some View {
        HStack(spacing: 10) {
            TypingIndicator()
            Text(lang.chatSearching)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppStyle.padding)
        .padding(.vertical, 8)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(lang.chatPlaceholder, text: $viewModel.queryText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appCardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusPill))
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyle.cornerRadiusPill)
                        .stroke(Color.appAccent.opacity(isInputFocused ? 0.4 : 0.15), lineWidth: 1)
                )

            Button {
                viewModel.sendQuery()
                isInputFocused = false
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        viewModel.queryText.isEmpty
                        ? AnyShapeStyle(Color.gray.opacity(0.3))
                        : AnyShapeStyle(LinearGradient.accentGradient)
                    )
                    .clipShape(Circle())
            }
            .disabled(viewModel.queryText.isEmpty || viewModel.isSearching)
            .accessibilityLabel(AppLanguage.current.accessibilitySend)
        }
        .padding(.horizontal, AppStyle.padding)
        .padding(.vertical, 10)
        .background(Color.appCard)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var selectedCitation: Citation?

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.isUser { Spacer(minLength: 48) }

                if message.isUser {
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(LinearGradient.accentGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else if message.content.isEmpty {
                    TypingIndicator()
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Color.appCard)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                } else {
                    MarkdownRenderer(text: message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.appCard)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                        .textSelection(.enabled)
                }

                if !message.isUser { Spacer(minLength: 48) }
            }

            if !message.citations.isEmpty {
                citationsView
            }

            if let debug = message.debugInfo, AppState.shared.isDebugMode {
                RAGDebugPanel(debug: debug)
            }
        }
        .sheet(item: $selectedCitation) { citation in
            CitationDetailView(citation: citation)
        }
    }

    private var citationsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.current.chatSources)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(message.citations) { citation in
                Button {
                    selectedCitation = citation
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.appAccent)

                        Text(citation.documentTitle)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(Int(citation.score * 100))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.appAccent)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appAccentLight)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusSmall))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Citation Detail

struct CitationDetailView: View {
    let citation: Citation
    @Environment(\.dismiss) private var dismiss
    private var lang: AppLanguage { AppLanguage.current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(Color.appAccent)
                        Text(citation.documentTitle)
                            .font(.headline)
                            .lineLimit(2)
                        Spacer()
                        Text("\(Int(citation.score * 100))% \(lang.chatRelevance)")
                            .font(.caption)
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.appAccentLight)
                            .clipShape(Capsule())
                    }

                    Divider()

                    Text(citation.chunkContent)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color.appCardSecondary)
            .navigationTitle(lang.chatSourceFragment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.cancelButton) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Markdown Renderer

struct MarkdownRenderer: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Block {
        case paragraph(String)
        case heading(level: Int, text: String)
        case bullet(text: String)
        case numbered(n: Int, text: String)
        case codeBlock(code: String)
        case rule
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { result.append(.paragraph(joined)) }
            paragraphLines = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    result.append(.codeBlock(code: codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode { codeLines.append(line); continue }

            let t = line.trimmingCharacters(in: .whitespaces)

            if t.isEmpty { flushParagraph(); continue }

            if t.hasPrefix("### ") {
                flushParagraph(); result.append(.heading(level: 3, text: String(t.dropFirst(4)))); continue
            }
            if t.hasPrefix("## ") {
                flushParagraph(); result.append(.heading(level: 2, text: String(t.dropFirst(3)))); continue
            }
            if t.hasPrefix("# ") {
                flushParagraph(); result.append(.heading(level: 1, text: String(t.dropFirst(2)))); continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
                flushParagraph(); result.append(.bullet(text: String(t.dropFirst(2)))); continue
            }
            if t == "---" || t == "***" || t == "___" {
                flushParagraph(); result.append(.rule); continue
            }
            if let (n, rest) = numberedItem(t) {
                flushParagraph(); result.append(.numbered(n: n, text: rest)); continue
            }

            paragraphLines.append(t)
        }
        flushParagraph()
        return result
    }

    @ViewBuilder
    private func blockView(for block: Block) -> some View {
        switch block {
        case .paragraph(let t):
            Text(inline(t))
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let t):
            Text(inline(t))
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, level < 3 ? 4 : 2)

        case .bullet(let t):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundStyle(Color.appAccent)
                    .padding(.top, 1)
                Text(inline(t))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let n, let t):
            HStack(alignment: .top, spacing: 6) {
                Text("\(n).")
                    .foregroundStyle(Color.appAccent)
                    .monospacedDigit()
                    .padding(.top, 1)
                Text(inline(t))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .codeBlock(let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let processed = shortenLinkDisplayTexts(linkify(text))
        return (try? AttributedString(
            markdown: processed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// Wraps bare URLs in `[domain](url)` so AttributedString renders them as tappable links.
    /// Skips URLs already inside existing markdown `[text](url)` links.
    private func linkify(_ text: String) -> String {
        // Find ranges already covered by markdown link syntax — don't double-wrap them
        var protectedRanges = [Range<String.Index>]()
        if let regex = try? NSRegularExpression(pattern: #"\[[^\[\]]*\]\(https?://[^)]+\)"#) {
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range, in: text) { protectedRanges.append(r) }
            }
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return text
        }

        let urlMatches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text

        // Reverse so replacements don't shift earlier positions
        for match in urlMatches.reversed() {
            guard let originalRange = Range(match.range, in: text),
                  let resultRange   = Range(match.range, in: result) else { continue }
            if protectedRanges.contains(where: { $0.overlaps(originalRange) }) { continue }
            let urlString   = match.url?.absoluteString ?? String(result[resultRange])
            let displayText = match.url?.host ?? String(result[resultRange])
            result.replaceSubrange(resultRange, with: "[\(displayText)](\(urlString))")
        }
        return result
    }

    /// Replaces `[https://full-url](url)` with `[domain](url)` for readability
    /// when the LLM already produced markdown links with the raw URL as display text.
    private func shortenLinkDisplayTexts(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[(https?://[^\]]+)\]\((https?://[^)]+)\)"#
        ) else { return text }

        var result = text
        while let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            guard let fullRange = Range(match.range, in: result),
                  let hrefRange = Range(match.range(at: 2), in: result),
                  let url = URL(string: String(result[hrefRange])) else { break }
            let domain = url.host ?? String(result[hrefRange])
            let href   = String(result[hrefRange])
            result.replaceSubrange(fullRange, with: "[\(domain)](\(href))")
        }
        return result
    }

    private func numberedItem(_ line: String) -> (Int, String)? {
        guard let dotRange = line.range(of: ". ") else { return nil }
        let prefix = String(line[line.startIndex..<dotRange.lowerBound])
        guard let n = Int(prefix), n > 0 else { return nil }
        return (n, String(line[dotRange.upperBound...]))
    }
}

// MARK: - Conversation History View

struct ConversationHistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var showDeleteAllAlert = false

    private var lang: AppLanguage { AppLanguage.current }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.conversations.isEmpty {
                    emptyHistoryState
                } else {
                    conversationList
                }
            }
            .navigationTitle(lang.chatHistory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.chatClose) { isPresented = false }
                }
                if !viewModel.conversations.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            showDeleteAllAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.appDanger)
                        }
                    }
                }
            }
            .alert(lang.chatDeleteAllHistory, isPresented: $showDeleteAllAlert) {
                Button(lang.cancelButton, role: .cancel) { }
                Button(lang.deleteButton, role: .destructive) {
                    Task {
                        await viewModel.deleteAllConversations()
                    }
                }
            } message: {
                Text(lang.chatDeleteAllHistoryMessage)
            }
        }
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            Text(lang.chatNoConversations)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(lang.chatConversationsAppearHere)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversationList: some View {
        List {
            ForEach(groupedConversations, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.conversations) { conv in
                        Button {
                            Task {
                                await viewModel.loadConversation(conv)
                                isPresented = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.appAccent)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conv.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    Text(conv.updatedAt.relativeFormatted)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteConversation(conv) }
                            } label: {
                                Label(lang.chatDeleteAction, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var groupedConversations: [ConversationGroup] {
        let calendar = Calendar.current
        var groups: [String: [Conversation]] = [:]
        let order = [lang.dateToday, lang.dateYesterday, lang.dateThisWeek, lang.dateThisMonth, lang.dateOlder]

        for conv in viewModel.conversations {
            let key: String
            if calendar.isDateInToday(conv.updatedAt) {
                key = lang.dateToday
            } else if calendar.isDateInYesterday(conv.updatedAt) {
                key = lang.dateYesterday
            } else if calendar.isDate(conv.updatedAt, equalTo: Date(), toGranularity: .weekOfYear) {
                key = lang.dateThisWeek
            } else if calendar.isDate(conv.updatedAt, equalTo: Date(), toGranularity: .month) {
                key = lang.dateThisMonth
            } else {
                key = lang.dateOlder
            }
            groups[key, default: []].append(conv)
        }

        return order.compactMap { key in
            guard let convs = groups[key], !convs.isEmpty else { return nil }
            return ConversationGroup(key: key, conversations: convs)
        }
    }
}

private struct ConversationGroup: Hashable {
    let key: String
    let conversations: [Conversation]

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }

    static func == (lhs: ConversationGroup, rhs: ConversationGroup) -> Bool {
        lhs.key == rhs.key
    }
}

// MARK: - RAG Debug Panel

struct RAGDebugPanel: View {
    let debug: RAGDebugInfo
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ant.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("RAG Debug")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("\(debug.results.count) chunks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Query info
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Query", systemImage: "magnifyingglass")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(debug.originalQuery)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        if debug.expandedQuery != debug.originalQuery {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(debug.expandedQuery)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Provider
                    HStack(spacing: 4) {
                        Label("Provider", systemImage: "brain")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(debug.provider)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }

                    Divider()

                    // Chunks
                    Label("Chunks recuperados", systemImage: "list.number")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(debug.results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                // Score bar
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15)).frame(width: 60, height: 5)
                                    Capsule().fill(scoreColor(result.score)).frame(width: CGFloat(result.score) * 60, height: 5)
                                }
                                Text(String(format: "%.0f%%", result.score * 100))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(scoreColor(result.score))
                                    .frame(width: 30, alignment: .trailing)
                                Text(result.documentTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let idx = result.chunkIndex {
                                    Text("#\(idx)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text(result.preview)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case 0.6...: return .green
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// Date.relativeFormatted is defined in Extensions.swift
