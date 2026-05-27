import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private var lang: AppLanguage { AppLanguage.current }

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                icon: "brain.head.profile",
                title: lang.onboardingTitle1,
                subtitle: lang.onboardingSubtitle1,
                accentColor: .indigo
            ),
            OnboardingPage(
                icon: "doc.text.magnifyingglass",
                title: lang.onboardingTitle2,
                subtitle: lang.onboardingSubtitle2,
                accentColor: .purple
            ),
            OnboardingPage(
                icon: "square.and.arrow.up",
                title: lang.onboardingTitle3,
                subtitle: lang.onboardingSubtitle3,
                accentColor: .blue
            ),
            OnboardingPage(
                icon: "lock.shield",
                title: lang.onboardingTitle4,
                subtitle: lang.onboardingSubtitle4,
                accentColor: .green
            ),
        ]
    }

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
            .background(Color.appCardSecondary)

            bottomSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appCardSecondary)
        .ignoresSafeArea(edges: .bottom)
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
                    .accessibilityHidden(true)
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

            if currentPage == pages.count - 1 {
                Button {
                    withAnimation { hasCompletedOnboarding = true }
                } label: {
                    Text(lang.onboardingStart)
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
                    Button(lang.onboardingSkip) {
                        withAnimation { hasCompletedOnboarding = true }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation { currentPage += 1 }
                    } label: {
                        HStack(spacing: 6) {
                            Text(lang.onboardingNext)
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
