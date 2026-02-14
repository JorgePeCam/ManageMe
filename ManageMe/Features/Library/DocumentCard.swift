import SwiftUI

struct DocumentCard: View {
    let document: Document
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else if let thumbURL = document.absoluteThumbnailURL,
                          let image = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Gradient background with icon
                    LinearGradient.cardGradient

                    Image(systemName: document.fileTypeEnum.systemImage)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.appAccent.opacity(0.7))
                }
            }
            .frame(height: 110)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppStyle.cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: AppStyle.cornerRadius
                )
            )

            // Content area
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack {
                    Text(document.fileTypeEnum.displayName)
                        .pillBadge()

                    Spacer()

                    statusIndicator
                }
            }
            .padding(.horizontal, AppStyle.paddingSmall + 2)
            .padding(.vertical, AppStyle.paddingSmall)
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
        .shadow(
            color: .black.opacity(AppStyle.shadowOpacity),
            radius: AppStyle.shadowRadius,
            y: AppStyle.shadowY
        )
        .task {
            // Generate thumbnail if we don't have one
            if document.absoluteThumbnailURL == nil,
               document.fileTypeEnum == .pdf || document.fileTypeEnum == .image {
                thumbnail = await ThumbnailService.shared.thumbnail(for: document)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch document.processingStatusEnum {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.appSuccess)
                .font(.caption)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.appDanger)
                .font(.caption)
        case .pending, .extracting, .chunking, .embedding:
            ProgressView()
                .scaleEffect(0.7)
                .tint(Color.appAccent)
        }
    }
}
