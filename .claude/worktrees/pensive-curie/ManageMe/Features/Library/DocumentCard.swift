import SwiftUI

struct DocumentCard: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail / Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 100)

                if let thumbURL = document.absoluteThumbnailURL,
                   let image = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: document.fileTypeEnum.systemImage)
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
            }

            // Title
            Text(document.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Metadata row
            HStack {
                Text(document.fileTypeEnum.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                Spacer()

                statusIndicator
            }
        }
        .padding(10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch document.processingStatusEnum {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .pending, .extracting, .chunking, .embedding:
            ProgressView()
                .scaleEffect(0.7)
        }
    }
}
