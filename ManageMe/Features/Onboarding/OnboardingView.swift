import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "brain.head.profile",
            title: "Tu segundo cerebro",
            subtitle: "Guarda facturas, garantías, contratos y cualquier documento importante. ManageMe los organiza y los tiene siempre listos para ti.",
            accentColor: .indigo
        ),
        OnboardingPage(
            icon: "doc.text.magnifyingglass",
            title: "Pregunta lo que quieras",
            subtitle: "¿Cuánto pagué de luz? ¿Mi lavadora sigue en garantía? Pregunta en lenguaje natural y obtén respuestas al instante.",
            accentColor: .purple
        ),
        OnboardingPage(
            icon: "square.and.arrow.up",
            title: "Importa desde cualquier app",
            subtitle: "Comparte PDFs, fotos, documentos Word o Excel directamente desde cualquier aplicación usando el botón compartir.",
            accentColor: .blue
        ),
        OnboardingPage(
            icon: "lock.shield",
            title: "Privacidad total",
            subtitle: "Tus documentos se procesan en tu dispositivo con Apple Intelligence. Tus datos nunca salen de tu iPhone.",
            accentColor: .green
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            bottomSection
        }
        .background(Color.appCardSecondary)
    }

    // MARK: - Page View

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.accentColor.opacity(0.12))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(page.accentColor.opacity(0.06))
                    .frame(width: 180, height: 180)

                Image(systemName: page.icon)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(page.accentColor)
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .padding(AppStyle.paddingLarge)
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 20) {
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.appAccent : Color.appAccent.opacity(0.2))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            // Action button
            if currentPage == pages.count - 1 {
                Button {
                    withAnimation {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text("Empezar")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusPill))
                }
                .padding(.horizontal, AppStyle.paddingLarge)
            } else {
                HStack {
                    Button("Saltar") {
                        withAnimation {
                            hasCompletedOnboarding = true
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Siguiente")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Image(systemName: "arrow.right")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.appAccent)
                    }
                }
                .padding(.horizontal, AppStyle.paddingLarge)
            }
        }
        .padding(.bottom, 40)
        .background(Color.appCardSecondary)
    }
}

// MARK: - Page Model

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
}
