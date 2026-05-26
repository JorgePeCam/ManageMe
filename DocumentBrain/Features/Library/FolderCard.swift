import SwiftUI

struct FolderCard: View {
    let folder: Folder
    let documentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon area
            ZStack {
                LinearGradient.accentSoftGradient

                Image(systemName: "folder.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.appAccent)
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
                Text(folder.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text("\(documentCount) doc\(documentCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
    }
}
