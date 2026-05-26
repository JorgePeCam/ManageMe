import Combine
import SwiftUI

/// Full-screen blocking overlay shown while embeddings are being regenerated.
struct ReindexingOverlay: View {
    @State private var dotCount = 1
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var lang: AppLanguage { AppLanguage.current }
    private var dots: String { String(repeating: ".", count: dotCount) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.appAccent)
                    .symbolEffect(.pulse)

                VStack(spacing: 8) {
                    Text(lang == .spanish ? "Actualizando documentos\(dots)" : "Updating documents\(dots)")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .animation(nil, value: dots)

                    Text(lang == .spanish
                         ? "El modelo de IA ha sido actualizado.\nReindexando tus documentos…"
                         : "The AI model has been updated.\nReindexing your documents…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ProgressView(value: AppState.shared.reindexProgress)
                        .tint(Color.appAccent)
                        .frame(width: 220)

                    if AppState.shared.reindexTotal > 0 {
                        Text(AppState.shared.reindexStatusText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                }
            }
            .padding(40)
        }
        .onReceive(timer) { _ in
            dotCount = dotCount % 3 + 1
        }
    }
}
