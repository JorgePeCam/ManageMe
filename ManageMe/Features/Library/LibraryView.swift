import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Todos") { viewModel.filterType = nil }
                        ForEach(FileType.allCases, id: \.self) { type in
                            Button(type.displayName) { viewModel.filterType = type }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
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

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Sin documentos")
                .font(.title2)
                .bold()

            Text("Importa archivos para que la IA\npueda responder tus preguntas")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    viewModel.showImporter = true
                } label: {
                    Label("Archivos", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.showCamera = true
                } label: {
                    Label("Camara", systemImage: "camera")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.filteredDocuments) { document in
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
            .padding()
        }
        .navigationDestination(for: String.self) { documentId in
            DocumentDetailView(documentId: documentId)
        }
    }
}
