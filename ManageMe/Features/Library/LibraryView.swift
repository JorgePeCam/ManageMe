import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: AppStyle.cardSpacing),
        GridItem(.flexible(), spacing: AppStyle.cardSpacing)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.documents.isEmpty {
                    emptyState
                } else {
                    documentGrid
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $searchText, prompt: "Buscar documentos...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            viewModel.showImporter = true
                        } label: {
                            Label("Desde archivos", systemImage: "folder")
                        }

                        Button {
                            viewModel.showCamera = true
                        } label: {
                            Label("Hacer foto", systemImage: "camera")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.appAccent)
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            viewModel.filterType = nil
                        } label: {
                            Label("Todos", systemImage: viewModel.filterType == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(FileType.allCases, id: \.self) { type in
                            Button {
                                viewModel.filterType = type
                            } label: {
                                Label(type.displayName, systemImage: type.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.filterType != nil
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .fileImporter(
                isPresented: $viewModel.showImporter,
                allowedContentTypes: viewModel.allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleFileImport(result: result)
            }
            .sheet(isPresented: $viewModel.showCamera) {
                ImagePicker(sourceType: .camera) { image in
                    viewModel.handleCameraCapture(image: image)
                }
            }
            .task {
                await viewModel.loadDocuments()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient.accentSoftGradient)
                    .frame(width: 120, height: 120)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.appAccent)
            }

            VStack(spacing: 8) {
                Text("Tu segundo cerebro")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Importa documentos y pregunta lo que\nnecesites saber sobre ellos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    viewModel.showImporter = true
                } label: {
                    Label("Importar archivos", systemImage: "folder.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button {
                    viewModel.showCamera = true
                } label: {
                    Label("Escanear documento", systemImage: "camera.fill")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(AppStyle.paddingLarge)
    }

    // MARK: - Document Grid

    private var documentGrid: some View {
        ScrollView {
            // Document count header
            if !filteredDocuments.isEmpty {
                HStack {
                    Text("\(filteredDocuments.count) documento\(filteredDocuments.count == 1 ? "" : "s")")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, AppStyle.padding)
                .padding(.top, 4)
            }

            LazyVGrid(columns: columns, spacing: AppStyle.cardSpacing) {
                ForEach(filteredDocuments) { document in
                    NavigationLink(value: document.id) {
                        DocumentCard(document: document)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteDocument(id: document.id)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, AppStyle.padding)
            .padding(.bottom, AppStyle.padding)
        }
        .navigationDestination(for: String.self) { documentId in
            DocumentDetailView(documentId: documentId)
        }
    }

    private var filteredDocuments: [Document] {
        let docs = viewModel.filteredDocuments
        if searchText.isEmpty { return docs }
        return docs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}
