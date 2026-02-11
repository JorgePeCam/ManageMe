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

                Divider()

                inputBar
            }
            .navigationTitle("Preguntar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.clearMessages()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Pregunta sobre tus documentos")
                .font(.title3)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 8) {
                suggestionChip("¿Mi lavadora sigue en garantia?")
                suggestionChip("¿Cuanto pague de luz el mes pasado?")
                suggestionChip("¿Que cubre mi seguro de hogar?")
            }

            Spacer()
        }
        .padding()
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            viewModel.queryText = text
            viewModel.sendQuery()
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text(text)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Buscando en tus documentos...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Escribe tu pregunta...", text: $viewModel.queryText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)

            Button {
                viewModel.sendQuery()
                isInputFocused = false
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.queryText.isEmpty ? .gray : .blue)
            }
            .disabled(viewModel.queryText.isEmpty || viewModel.isSearching)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.isUser { Spacer() }

                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if !message.isUser { Spacer() }
            }

            // Citations
            if !message.citations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fuentes:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(message.citations) { citation in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                            Text(citation.documentTitle)
                                .font(.caption)
                            Text("\(Int(citation.score * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
