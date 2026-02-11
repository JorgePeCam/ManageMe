import SwiftUI
import QuickLook

struct DocumentDetailView: View {
    let documentId: String
    @StateObject private var viewModel = DocumentDetailViewModel()

    var body: some View {
        ScrollView {
            if let document = viewModel.document {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    header(document)

                    Divider()

                    // Status
                    statusSection(document)

                    // Preview button
                    if document.absoluteFileURL != nil {
                        previewButton
                    }

                    // Extracted text
                    if !document.content.isEmpty {
                        extractedTextSection(document)
                    }
                }
                .padding()
            } else {
                ProgressView()
                    .padding(.top, 100)
            }
        }
        .navigationTitle(viewModel.document?.title ?? "Documento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let doc = viewModel.document, doc.processingStatusEnum == .error {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reintentar") {
                        viewModel.reprocess()
                    }
                }
            }
        }
        .quickLookPreview($viewModel.previewURL)
        .task {
            await viewModel.load(documentId: documentId)
        }
    }

    private func header(_ document: Document) -> some View {
        HStack(spacing: 16) {
            Image(systemName: document.fileTypeEnum.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .frame(width: 60, height: 60)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)

                Text(document.fileTypeEnum.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let size = document.fileSizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(document.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private func statusSection(_ document: Document) -> some View {
        HStack {
            switch document.processingStatusEnum {
            case .ready:
                Label("Procesado", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                VStack(alignment: .leading) {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    if let error = document.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .pending:
                Label("Pendiente", systemImage: "clock")
                    .foregroundStyle(.orange)
            case .extracting:
                Label("Extrayendo texto...", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
            case .chunking:
                Label("Fragmentando...", systemImage: "scissors")
                    .foregroundStyle(.blue)
            case .embedding:
                Label("Generando embeddings...", systemImage: "brain")
                    .foregroundStyle(.blue)
            }
        }
        .font(.subheadline)
    }

    private var previewButton: some View {
        Button {
            viewModel.openPreview()
        } label: {
            Label("Ver archivo original", systemImage: "eye")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func extractedTextSection(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Texto extraido")
                .font(.headline)

            Text(document.content)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
