import SwiftUI
import QuickLook
import PDFKit

struct DocumentDetailView: View {
    let documentId: String
    @StateObject private var viewModel = DocumentDetailViewModel()

    var body: some View {
        ScrollView {
            if let document = viewModel.document {
                VStack(spacing: AppStyle.padding) {
                    headerCard(document)

                    // Inline preview for PDFs and images
                    if let fileURL = document.absoluteFileURL {
                        inlinePreview(url: fileURL, fileType: document.fileTypeEnum)
                    }

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
                    .tint(Color.appAccent)
                    .padding(.top, 100)
            }
        }
        .background(Color.appCardSecondary)
        .navigationTitle(viewModel.document?.title ?? "Documento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let doc = viewModel.document {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if doc.processingStatusEnum == .error {
                            Button {
                                viewModel.reprocess()
                            } label: {
                                Label("Reintentar procesado", systemImage: "arrow.clockwise")
                            }
                        }

                        if let url = doc.absoluteFileURL {
                            ShareLink(item: url) {
                                Label("Compartir", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
        }
        .quickLookPreview($viewModel.previewURL)
        .task {
            await viewModel.load(documentId: documentId)
        }
    }

    // MARK: - Inline Preview

    @ViewBuilder
    private func inlinePreview(url: URL, fileType: FileType) -> some View {
        switch fileType {
        case .pdf:
            PDFPreviewView(url: url)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                .shadow(color: .black.opacity(AppStyle.shadowOpacity), radius: AppStyle.shadowRadius, y: AppStyle.shadowY)
                .onTapGesture { viewModel.openPreview() }

        case .image:
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 350)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                    .shadow(color: .black.opacity(AppStyle.shadowOpacity), radius: AppStyle.shadowRadius, y: AppStyle.shadowY)
                    .onTapGesture { viewModel.openPreview() }
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Header Card

    private func headerCard(_ document: Document) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                    .fill(LinearGradient.accentSoftGradient)
                    .frame(width: 64, height: 64)

                Image(systemName: document.fileTypeEnum.systemImage)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.appAccent)
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
                    .tint(Color.appAccent)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func statusIcon(_ document: Document) -> some View {
        let (icon, color): (String, Color) = switch document.processingStatusEnum {
        case .ready: ("checkmark.circle.fill", .appSuccess)
        case .error: ("exclamationmark.triangle.fill", .appDanger)
        case .pending: ("clock.fill", .appWarning)
        case .extracting: ("doc.text.magnifyingglass", .appAccent)
        case .chunking: ("scissors", .appAccent)
        case .embedding: ("brain", .appAccent)
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
                    .foregroundStyle(Color.appAccent)
                Text("Ver archivo original")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                    .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Extracted Text

    private func extractedTextCard(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(Color.appAccent)
                Text("Texto extraído")
                    .fontWeight(.semibold)

                Spacer()

                Text("\(document.content.count) caracteres")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

// MARK: - PDF Preview (UIKit wrapper)

struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.document = PDFDocument(url: url)
        pdfView.isUserInteractionEnabled = false
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil {
            pdfView.document = PDFDocument(url: url)
        }
    }
}
