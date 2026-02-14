import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.messages.isEmpty && viewModel.currentConversation == nil {
                    emptyState
                } else {
                    messageList
                }

                inputBar
            }
            .background(Color.appCardSecondary)
            .navigationTitle(viewModel.currentConversation?.title ?? "Preguntar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundStyle(Color.appAccent)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Image(systemName: "plus.bubble")
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                ConversationHistoryView(viewModel: viewModel, isPresented: $showHistory)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient.accentSoftGradient)
                    .frame(width: 100, height: 100)

                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.appAccent)
            }

            VStack(spacing: 8) {
                Text("Pregunta lo que quieras")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Buscaré en tus documentos\ny te responderé con precisión")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                suggestionCard("¿Mi lavadora sigue en garantía?", icon: "washer")
                suggestionCard("¿Cuánto pagué de luz el mes pasado?", icon: "bolt")
                suggestionCard("¿Qué cubre mi seguro de hogar?", icon: "house.lodge")
            }

            // Recent conversations quick access
            if !viewModel.conversations.isEmpty {
                recentConversations
            }

            Spacer()
        }
        .padding(AppStyle.paddingLarge)
    }

    private var recentConversations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Conversaciones recientes")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button("Ver todas") {
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
            Text("Buscando en tus documentos...")
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
            TextField("Escribe tu pregunta...", text: $viewModel.queryText, axis: .vertical)
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
                    .frame(width: 36, height: 36)
                    .background(
                        viewModel.queryText.isEmpty
                        ? AnyShapeStyle(Color.gray.opacity(0.3))
                        : AnyShapeStyle(LinearGradient.accentGradient)
                    )
                    .clipShape(Circle())
            }
            .disabled(viewModel.queryText.isEmpty || viewModel.isSearching)
        }
        .padding(.horizontal, AppStyle.padding)
        .padding(.vertical, 10)
        .background(Color.appCard)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

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
                } else {
                    Text(Self.markdownContent(message.content))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.appCard)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                }

                if !message.isUser { Spacer(minLength: 48) }
            }

            // Citations
            if !message.citations.isEmpty {
                citationsView
            }
        }
    }

    /// Parse markdown for bot messages with fallback to plain text
    private static func markdownContent(_ content: String) -> AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
    }

    private var citationsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fuentes")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(message.citations) { citation in
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
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appAccentLight)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusSmall))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Conversation History View

struct ConversationHistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var showDeleteAllAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.conversations.isEmpty {
                    emptyHistoryState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { isPresented = false }
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
            .alert("Borrar todo el historial", isPresented: $showDeleteAllAlert) {
                Button("Cancelar", role: .cancel) { }
                Button("Borrar todo", role: .destructive) {
                    Task {
                        await viewModel.deleteAllConversations()
                    }
                }
            } message: {
                Text("Se eliminarán todas las conversaciones. Esta acción no se puede deshacer.")
            }
        }
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            Text("Sin conversaciones")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Tus conversaciones aparecerán aquí")
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
                                Label("Borrar", systemImage: "trash")
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
        let order = ["Hoy", "Ayer", "Esta semana", "Este mes", "Anteriores"]

        for conv in viewModel.conversations {
            let key: String
            if calendar.isDateInToday(conv.updatedAt) {
                key = "Hoy"
            } else if calendar.isDateInYesterday(conv.updatedAt) {
                key = "Ayer"
            } else if calendar.isDate(conv.updatedAt, equalTo: Date(), toGranularity: .weekOfYear) {
                key = "Esta semana"
            } else if calendar.isDate(conv.updatedAt, equalTo: Date(), toGranularity: .month) {
                key = "Este mes"
            } else {
                key = "Anteriores"
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

// MARK: - Date Extension

extension Date {
    var relativeFormatted: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: self)
        } else if calendar.isDateInYesterday(self) {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            formatter.locale = Locale(identifier: "es_ES")
            return formatter.string(from: self)
        }
    }
}
