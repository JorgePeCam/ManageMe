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
