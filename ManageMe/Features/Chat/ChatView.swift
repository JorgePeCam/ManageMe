import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                inputBar
            }
            .background(Color.appCardSecondary)
            .navigationTitle("Preguntar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.clearMessages()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(.appAccent)
                        }
                    }
                }
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
                    .foregroundStyle(.appAccent)
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

            Spacer()
        }
        .padding(AppStyle.paddingLarge)
    }

    private func suggestionCard(_ text: String, icon: String) -> some View {
        Button {
            viewModel.queryText = text
            viewModel.sendQuery()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.appAccent)
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
            .background(.appCard)
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
        .background(.appCard)
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
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.appCard)
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
                        .foregroundStyle(.appAccent)

                    Text(citation.documentTitle)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(citation.score * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.appAccent)
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
