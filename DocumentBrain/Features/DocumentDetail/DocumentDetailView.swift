import EventKit
import SwiftUI
import QuickLook
import PDFKit

struct DocumentDetailView: View {
    let documentId: String
    @StateObject private var viewModel = DocumentDetailViewModel()

    private var lang: AppLanguage { AppLanguage.current }

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

                    if let metadata = document.structuredDataDecoded {
                        structuredDataCard(metadata, document: document)
                    } else if document.isReady && !document.content.isEmpty {
                        extractMetadataButton
                    }

                    if !document.barcodesDecoded.isEmpty {
                        barcodesCard(document.barcodesDecoded)
                    }

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
        .navigationTitle(viewModel.document?.title ?? lang.detailDocument)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let doc = viewModel.document {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if doc.processingStatusEnum == .error {
                            Button {
                                viewModel.reprocess()
                            } label: {
                                Label(lang.detailRetryProcessing, systemImage: "arrow.clockwise")
                            }
                        }

                        if let url = doc.absoluteFileURL {
                            ShareLink(item: url) {
                                Label(lang.detailShare, systemImage: "square.and.arrow.up")
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
        .sheet(isPresented: $viewModel.showCalendarSheet) {
            if let event = viewModel.calendarEvent {
                CalendarEventSheet(
                    event: event,
                    store: EventKitService.shared.store,
                    isPresented: $viewModel.showCalendarSheet
                )
                .ignoresSafeArea()
            }
        }
        .alert("Sin acceso al Calendario", isPresented: $viewModel.calendarAccessDenied) {
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Permite el acceso al Calendario en Ajustes para añadir eventos desde tus documentos.")
        }
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
        case .ready: return lang.detailStatusReady
        case .error: return lang.detailStatusError
        case .pending: return lang.detailStatusPending
        case .extracting: return lang.detailStatusExtracting
        case .chunking: return lang.detailStatusChunking
        case .embedding: return lang.detailStatusEmbedding
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
                Text(lang.detailViewOriginal)
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

    // MARK: - Structured Data Card

    private func structuredDataCard(_ metadata: StructuredDocumentData, document: Document) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: metadata.documentType?.systemImage ?? "sparkles")
                    .font(.title3)
                    .foregroundStyle(Color.appAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.documentType?.displayName ?? "Datos extraídos")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let category = metadata.category {
                        Text("\(category.emoji) \(category.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    viewModel.extractMetadata()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(viewModel.isExtractingMetadata)
            }

            Divider()

            // Flight / travel rows
            if let origin = metadata.origin, let destination = metadata.destination {
                routeRow(origin: origin, destination: destination)
            } else if let origin = metadata.origin {
                metadataRow(icon: "mappin", label: "Origen", value: origin)
            } else if let destination = metadata.destination {
                metadataRow(icon: "mappin.and.ellipse", label: "Destino", value: destination)
            }

            if let flightNumber = metadata.flightNumber {
                metadataRow(icon: "airplane", label: "Vuelo", value: flightNumber)
            }

            if let dep = metadata.departureTime, let arr = metadata.arrivalTime {
                metadataRow(icon: "clock", label: "Horario", value: "\(dep) → \(arr)")
            } else if let dep = metadata.departureTime {
                let label = metadata.documentType == .event ? "Hora" : "Salida"
                metadataRow(icon: "clock", label: label, value: dep)
            }

            if let seat = metadata.seat {
                metadataRow(icon: "carseat.right.fill", label: "Asiento", value: seat)
            }

            // Event title
            if let title = metadata.eventTitle {
                metadataRow(icon: "music.note", label: "Evento", value: title)
            }

            // Common rows
            if let vendor = metadata.vendor {
                metadataRow(icon: "building.2", label: vendorLabel(for: metadata), value: vendor)
            }
            if let date = metadata.formattedDate {
                metadataRow(icon: "calendar", label: "Fecha", value: date)
            }
            if let amount = metadata.formattedAmount {
                metadataRow(icon: "eurosign.circle", label: "Importe", value: amount, highlight: true)
            }

            // Calendar button — only when there is a parseable date
            if metadata.date != nil {
                Divider()
                Button {
                    viewModel.addToCalendar(metadata: metadata, documentTitle: document.title)
                } label: {
                    Label("Añadir al Calendario", systemImage: "calendar.badge.plus")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func vendorLabel(for metadata: StructuredDocumentData) -> String {
        switch metadata.documentType {
        case .flight: return "Aerolínea"
        case .event:  return "Recinto"
        default:      return "Emisor"
        }
    }

    private func routeRow(origin: String, destination: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane")
                .font(.caption)
                .foregroundStyle(Color.appAccent)
                .frame(width: 18)

            Text(origin)
                .font(.subheadline)
                .fontWeight(.medium)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(destination)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()
        }
    }

    private func metadataRow(icon: String, label: String, value: String, highlight: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.appAccent)
                .frame(width: 18)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(highlight ? .subheadline.bold() : .subheadline)
                .foregroundStyle(highlight ? Color.appAccent : .primary)

            Spacer()
        }
    }

    private var extractMetadataButton: some View {
        VStack(spacing: 6) {
            Button {
                viewModel.extractMetadata()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isExtractingMetadata {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.appAccent)
                        Text("Analizando documento…")
                    } else {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.appAccent)
                        Text("Extraer datos estructurados")
                            .fontWeight(.medium)
                    }
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
            .disabled(viewModel.isExtractingMetadata)

            if viewModel.metadataNotFound {
                Text("No se encontraron datos estructurados en este documento")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Barcodes Card

    @State private var selectedBarcode: String? = nil

    private func barcodesCard(_ payloads: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title3)
                    .foregroundStyle(Color.appAccent)
                Text(payloads.count == 1 ? "Código digital" : "\(payloads.count) Códigos digitales")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Divider()

            ForEach(Array(payloads.enumerated()), id: \.offset) { _, payload in
                barcodeRow(payload)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .sheet(item: $selectedBarcode) { payload in
            BarcodeDisplayView(payload: payload)
        }
    }

    private func barcodeRow(_ payload: String) -> some View {
        let kind = BarcodeKind(payload: payload)

        return HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(Color.appAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(kind.subtitle(for: payload))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .url(let url) = kind {
                Link(destination: url) {
                    Label("Abrir", systemImage: "safari")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                }
            } else {
                Button {
                    selectedBarcode = payload
                } label: {
                    Label("Ver código", systemImage: "qrcode")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Extracted Text

    private func extractedTextCard(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(Color.appAccent)
                Text(lang.detailExtractedText)
                    .fontWeight(.semibold)

                Spacer()

                Text(lang.detailCharCount(document.content.count))
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
