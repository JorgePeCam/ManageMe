import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private var lang: AppLanguage { AppLanguage.current }

    private let totalPages = 5 // 4 info + 1 API key

    private var infoPagesData: [OnboardingPage] {
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
                ForEach(Array(infoPagesData.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }

                APIKeySetupPage(onComplete: {
                    withAnimation { hasCompletedOnboarding = true }
                })
                .tag(4)
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
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.appAccent : Color.appAccent.opacity(0.2))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            // Action button — hidden on last page (API page handles its own CTAs)
            if currentPage < totalPages - 1 {
                HStack {
                    Button(lang.onboardingSkip) {
                        withAnimation { currentPage = totalPages - 1 }
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
            } else {
                // Spacer placeholder so layout height stays consistent
                Color.clear.frame(height: 44)
            }
        }
        .padding(.bottom, 40)
        .background(Color.appCardSecondary)
    }
}

// MARK: - API Key Setup Page

private struct APIKeySetupPage: View {
    let onComplete: () -> Void

    @State private var apiKey = ""
    @State private var verificationState: VerificationState = .idle
    @FocusState private var fieldFocused: Bool

    private var lang: AppLanguage { AppLanguage.current }

    enum VerificationState: Equatable {
        case idle, verifying, valid, invalid(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 16)

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 140, height: 140)

                    Circle()
                        .fill(Color.orange.opacity(0.06))
                        .frame(width: 180, height: 180)

                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.orange)
                }

                // Title + subtitle
                VStack(spacing: 12) {
                    Text(lang.onboardingAPITitle)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(lang.onboardingAPISubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }

                // Key input + get-key link
                VStack(spacing: 12) {
                    SecureField(lang.onboardingAPIPlaceholder, text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($fieldFocused)
                        .padding(14)
                        .background(Color.appCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                                .stroke(borderColor, lineWidth: 1.5)
                        )
                        .padding(.horizontal, AppStyle.paddingLarge)
                        .onChange(of: apiKey) { _, _ in
                            if case .valid = verificationState { } else {
                                verificationState = .idle
                            }
                        }

                    Link(lang.onboardingAPIGetKey, destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.footnote)
                        .foregroundStyle(Color.appAccent)
                }

                // Verification status
                verificationStatusView

                // CTAs
                VStack(spacing: 12) {
                    if case .valid = verificationState {
                        Button {
                            onComplete()
                        } label: {
                            Text(lang.onboardingAPIStart)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(LinearGradient.accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusPill))
                        }
                        .padding(.horizontal, AppStyle.paddingLarge)
                    } else {
                        Button {
                            fieldFocused = false
                            Task { await verifyKey() }
                        } label: {
                            HStack(spacing: 8) {
                                if case .verifying = verificationState {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                }
                                Text(verificationButtonLabel)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(apiKey.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.appAccent)
                            .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusPill))
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || verificationState == .verifying)
                        .padding(.horizontal, AppStyle.paddingLarge)
                    }

                    Button(lang.onboardingAPISkip) {
                        onComplete()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer().frame(height: 8)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appCardSecondary)
    }

    @ViewBuilder
    private var verificationStatusView: some View {
        switch verificationState {
        case .idle:
            EmptyView()
        case .verifying:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text(lang.onboardingAPIVerifying)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .valid:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
                Text(lang.onboardingAPIValid)
                    .font(.caption)
                    .foregroundStyle(Color.appSuccess)
            }
        case .invalid(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.appDanger)
                Text(msg.isEmpty ? lang.onboardingAPIInvalid : msg)
                    .font(.caption)
                    .foregroundStyle(Color.appDanger)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppStyle.paddingLarge)
        }
    }

    private var borderColor: Color {
        switch verificationState {
        case .idle:      return Color.secondary.opacity(0.2)
        case .verifying: return Color.appAccent.opacity(0.5)
        case .valid:     return Color.appSuccess
        case .invalid:   return Color.appDanger
        }
    }

    private var verificationButtonLabel: String {
        if case .verifying = verificationState { return lang.onboardingAPIVerifying }
        return lang.onboardingAPIVerify
    }

    private func verifyKey() async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        verificationState = .verifying

        let isValid = await GeminiQAProvider.verifyKey(trimmed)

        if isValid {
            try? APIKeyStore.saveKey(trimmed)
            verificationState = .valid
        } else {
            verificationState = .invalid("")
        }
    }
}

// MARK: - Page Model

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
}
