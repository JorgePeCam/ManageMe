import SwiftUI
import QuickLook

struct DocumentDetailView: View {
    let documentId: String
    @StateObject private var viewModel = DocumentDetailViewModel()

    var body: some View {
        ScrollView {
            if let document = viewModel.document {
                VStack(spacing: AppStyle.padding) {
                    headerCard(document)
                    statusCard(document)

                    if document.absoluteFileURL != nil {
                        previewButton
                    }

                    if !document.content.isEmpty {
                        extractedTextCard(document)
                    }
                }
                .padding(AppStyle.padding)
            } else {
                ProgressView()
                    .tint(.accent)
                    .padding(.top, 100)
            }
        }
        .background(Color.cardBackgroundSecondary)
        .navigationTitle(viewModel.document?.title ?? "Documento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let doc = viewModel.document, doc.processingStatusEnum == .error {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.reprocess()
                    } label: {
                        Label("Reintentar", systemImage: "arrow.clockwise")
                            .foregroundStyle(.accent)
                    }
                }
            }
        }
        .quickLookPreview($viewModel.previewURL)
        .task {
            await viewModel.load(documentId: documentId)
        }
    }

    // MARK: - Header Card

    private func headerCard(_ document: Document) -> some View {
        HStack(spacing: 16) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                    .fill(LinearGradient.accentSoftGradient)
                    .frame(width: 64, height: 64)

                Image(systemName: document.fileTypeEnum.systemImage)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)

                Text(document.fileTypeEnum.displayName)
                    .pillBadge()

                HStack(spacing: 12) {
                    if let size = document.fileSizeBytes {
                        Label(
                            ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                            systemImage: "doc"
                        )
                    }

                    Label(
                        document.createdAt.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "calendar"
                    )
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .cardStyle()
    }

    // MARK: - Status Card

    private func statusCard(_ document: Document) -> some View {
        HStack(spacing: 12) {
            statusIcon(document)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle(document))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let error = document.errorMessage, document.processingStatusEnum == .error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if document.processingStatusEnum != .ready && document.processingStatusEnum != .error {
                ProgressView()
                    .tint(.accent)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func statusIcon(_ document: Document) -> some View {
        let (icon, color): (String, Color) = switch document.processingStatusEnum {
        case .ready: ("checkmark.circle.fill", .success)
        case .error: ("exclamationmark.triangle.fill", .danger)
        case .pending: ("clock.fill", .warning)
        case .extracting: ("doc.text.magnifyingglass", .accent)
        case .chunking: ("scissors", .accent)
        case .embedding: ("brain", .accent)
        }

        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 32)
    }

    private func statusTitle(_ document: Document) -> String {
        switch document.processingStatusEnum {
        case .ready: return "Procesado correctamente"
        case .error: return "Error al procesar"
        case .pending: return "Pendiente"
        case .extracting: return "Extrayendo texto..."
        case .chunking: return "Fragmentando..."
        case .embedding: return "Generando embeddings..."
        }
    }

    // MARK: - Preview Button

    private var previewButton: some View {
        Button {
            viewModel.openPreview()
        } label: {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.accent)
                Text("Ver archivo original")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                    .stroke(Color.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Extracted Text

    private func extractedTextCard(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.accent)
                Text("Texto extraido")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            Text(document.content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(50)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
