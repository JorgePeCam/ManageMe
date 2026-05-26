import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        NavigationStack {
            List {
                // Language
                Section {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            viewModel.changeLanguage(to: language)
                        } label: {
                            HStack(spacing: 12) {
                                Text(language.flag)
                                    .font(.title3)
                                Text(language.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if language == viewModel.selectedLanguage {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.appAccent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text(lang.languageSectionTitle)
                }

                // AI Section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundStyle(Color.appAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.activeProviderName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(viewModel.aiStatusText)
                                .font(.caption)
                                .foregroundStyle(viewModel.isOnDeviceAIActive ? Color.appSuccess : .secondary)
                        }

                        Spacer()

                        Image(systemName: viewModel.isAIAvailable ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(viewModel.isOnDeviceAIActive ? Color.appSuccess : .secondary)
                    }
                } header: {
                    Text(lang.aiSectionTitle)
                } footer: {
                    Text(viewModel.aiFooterText)
                }

                // Gemini API Key
                geminiAPISection

                // iCloud Sync
                if #available(iOS 17.0, *) {
                    iCloudSyncSection
                }

                // Storage
                Section(lang.storageSectionTitle) {
                    HStack {
                        Label(lang.documentsLabel, systemImage: "doc.on.doc")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(viewModel.documentCount)")
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Label(lang.storageUsedLabel, systemImage: "internaldrive")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(viewModel.storageUsed)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Label("Embeddings", systemImage: "brain")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(viewModel.embeddingModelStatus)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }
                }

                // Actions
                Section(lang.actionsSectionTitle) {
                    Button {
                        viewModel.reindexAll()
                    } label: {
                        Label(lang.reindexLabel, systemImage: "arrow.clockwise")
                            .foregroundStyle(Color.appAccent)
                    }

                    Button(role: .destructive) {
                        viewModel.showDeleteConfirmation = true
                    } label: {
                        Label(lang.deleteAllLabel, systemImage: "trash")
                    }
                }

                // About
                Section {
                    HStack {
                        Label(lang.versionLabel, systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(lang.aboutSectionTitle)
                } footer: {
                    Text(lang.tagline)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            .navigationTitle(lang.settingsTitle)
            .tint(Color.appAccent)
            .alert(lang.deleteAllTitle, isPresented: $viewModel.showDeleteConfirmation) {
                Button(lang.cancelButton, role: .cancel) {}
                Button(lang.deleteButton, role: .destructive) {
                    viewModel.deleteAllData()
                }
            } message: {
                Text(lang.deleteAllMessage)
            }
            .task {
                await viewModel.loadStats()
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.userErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.userErrorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.userErrorMessage = nil
                }
            } message: {
                Text(viewModel.userErrorMessage ?? "")
            }
            .sheet(isPresented: $viewModel.showAPIKeySheet) {
                APIKeySheet(viewModel: viewModel)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Gemini API Section

    private var geminiAPISection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill")
                    .font(.title3)
                    .foregroundStyle(viewModel.isGeminiKeyConfigured ? Color.appAccent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.settingsGeminiTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(viewModel.isGeminiKeyConfigured ? lang.settingsGeminiConfigured : lang.settingsGeminiNotConfigured)
                        .font(.caption)
                        .foregroundStyle(viewModel.isGeminiKeyConfigured ? Color.appSuccess : .secondary)
                }

                Spacer()

                Image(systemName: viewModel.isGeminiKeyConfigured ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(viewModel.isGeminiKeyConfigured ? Color.appSuccess : .secondary)
            }

            Button {
                viewModel.pendingAPIKey = ""
                viewModel.apiKeyVerificationState = .idle
                viewModel.showAPIKeySheet = true
            } label: {
                Label(
                    viewModel.isGeminiKeyConfigured ? lang.settingsGeminiChange : lang.settingsGeminiAddKey,
                    systemImage: viewModel.isGeminiKeyConfigured ? "pencil" : "plus"
                )
                .foregroundStyle(Color.appAccent)
            }

            if viewModel.isGeminiKeyConfigured {
                Button(role: .destructive) {
                    viewModel.removeAPIKey()
                } label: {
                    Label(lang.settingsGeminiRemove, systemImage: "trash")
                }
            }
        } footer: {
            Text(lang.settingsGeminiFooter)
        }
    }

    // MARK: - iCloud Sync Section

    @available(iOS 17.0, *)
    private var iCloudSyncSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "icloud")
                    .font(.title3)
                    .foregroundStyle(SyncCoordinator.shared.iCloudAvailable ? Color.appAccent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.iCloudTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if SyncCoordinator.shared.isSyncing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(lang.iCloudSyncing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if SyncCoordinator.shared.lastSyncDate != nil {
                        Text(lang.iCloudActive)
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                    } else if SyncCoordinator.shared.iCloudAvailable {
                        Text(lang.iCloudActive)
                            .font(.caption)
                            .foregroundStyle(Color.appSuccess)
                    } else {
                        Text(lang.iCloudUnavailable)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: SyncCoordinator.shared.iCloudAvailable ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(SyncCoordinator.shared.iCloudAvailable ? Color.appSuccess : .secondary)
            }

            if let error = SyncCoordinator.shared.syncError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(lang.iCloudFooter)
        }
    }
}

// MARK: - API Key Sheet

private struct APIKeySheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @FocusState private var focused: Bool

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(lang.settingsGeminiTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Link(lang.onboardingAPIGetKey, destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.footnote)
                        .foregroundStyle(Color.appAccent)
                }
                .padding(.top, 8)

                SecureField(lang.onboardingAPIPlaceholder, text: $viewModel.pendingAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .padding(14)
                    .background(Color.appCard)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                            .stroke(sheetBorderColor, lineWidth: 1.5)
                    )
                    .padding(.horizontal)
                    .onChange(of: viewModel.pendingAPIKey) { _, _ in
                        viewModel.apiKeyVerificationState = .idle
                    }

                verificationStatusRow

                Button {
                    focused = false
                    viewModel.verifyAndSaveAPIKey()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.apiKeyVerificationState == .verifying {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        }
                        Text(viewModel.apiKeyVerificationState == .verifying
                             ? lang.onboardingAPIVerifying
                             : lang.onboardingAPIVerify)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.pendingAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.secondary
                                : Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadiusPill))
                }
                .disabled(viewModel.pendingAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
                          || viewModel.apiKeyVerificationState == .verifying)
                .padding(.horizontal)

                Text(lang.settingsGeminiFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.cancelButton) {
                        viewModel.showAPIKeySheet = false
                    }
                }
            }
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var verificationStatusRow: some View {
        switch viewModel.apiKeyVerificationState {
        case .idle:
            EmptyView()
        case .verifying:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text(lang.onboardingAPIVerifying).font(.caption).foregroundStyle(.secondary)
            }
        case .valid:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appSuccess)
                Text(lang.onboardingAPIValid).font(.caption).foregroundStyle(Color.appSuccess)
            }
        case .invalid:
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appDanger)
                Text(lang.onboardingAPIInvalid).font(.caption).foregroundStyle(Color.appDanger)
            }
        }
    }

    private var sheetBorderColor: Color {
        switch viewModel.apiKeyVerificationState {
        case .idle:      return Color.secondary.opacity(0.2)
        case .verifying: return Color.appAccent.opacity(0.5)
        case .valid:     return Color.appSuccess
        case .invalid:   return Color.appDanger
        }
    }
}
