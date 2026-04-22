import SwiftUI

struct DocumentContainerView: View {
    @EnvironmentObject var docVM: DocumentViewModel
    @EnvironmentObject var ttsVM: TTSViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showScanner = false
    @State private var showFilePicker = false
    @State private var showSavePrompt = false
    @State private var saveTitle = ""
    @State private var pendingDeleteDocument: SavedDocumentSummary?
    
    var body: some View {
        GeometryReader { geometry in
            let useSidebarLayout = (horizontalSizeClass == .regular) || geometry.size.width >= 820
            if useSidebarLayout {
                HStack(spacing: 0) {
                    librarySidebar
                        .frame(width: 240)
                    Divider()
                    mainContent
                }
            } else {
                VStack {
                    savedLibrarySection
                    mainContent
                }
            }
        }
        .navigationTitle("Lulu")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !docVM.pages.isEmpty {
                    Button(action: {
                        saveTitle = defaultSaveTitle()
                        showSavePrompt = true
                    }) {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showScanner = true }) {
                        Label("Scan Document", systemImage: "camera")
                    }
                    Button(action: { showFilePicker = true }) {
                        Label("Import PDF", systemImage: "square.and.arrow.down")
                    }
                    if !docVM.pages.isEmpty {
                        Button(action: {
                            saveTitle = defaultSaveTitle()
                            showSavePrompt = true
                        }) {
                            Label("Save Current", systemImage: "square.and.arrow.down.on.square")
                        }
                    }
                    if !docVM.selectedSentenceIDs.isEmpty {
                        Button(role: .destructive, action: { docVM.selectedSentenceIDs.removeAll() }) {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title)
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            DocumentScannerView { images in
                Task { await docVM.loadFromScan(images) }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                Task { await docVM.loadFromPDF(url) }
            }
        }
        .onAppear {
            docVM.refreshSavedDocuments()
        }
        .alert("Save Document", isPresented: $showSavePrompt) {
            TextField("Document name", text: $saveTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                docVM.saveCurrentDocument(title: saveTitle)
            }
        } message: {
            Text("Save this scanned/imported document to your library for later use.")
        }
        .alert("Delete Saved Document?", isPresented: Binding(
            get: { pendingDeleteDocument != nil },
            set: { if !$0 { pendingDeleteDocument = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let summary = pendingDeleteDocument {
                    docVM.deleteSavedDocument(summary)
                }
                pendingDeleteDocument = nil
            }
        } message: {
            Text("This will remove the saved document from your local library.")
        }
        .alert(isPresented: Binding<Bool>(
                    get: { docVM.errorMessage != nil },
                    set: { _ in docVM.errorMessage = nil }
                )) {
            Alert(title: Text("Error"), message: Text(docVM.errorMessage ?? ""))
        }
    }

    private var mainContent: some View {
        Group {
            if docVM.pages.isEmpty && !docVM.isProcessing {
                Spacer()
                Image(systemName: "book")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                Text("Tap + to add a document")
                    .font(.headline)
                Text("Scan a worksheet or import a PDF")
                    .foregroundColor(.secondary)
                Spacer()
            } else if docVM.isProcessing {
                ProgressView("Analysing…")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap text blocks to choose what Lulu reads in Listen mode.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    TabView {
                        ForEach(docVM.pages) { page in
                            DocumentPageView(page: page)
                                .tag(page.index)
                        }
                    }
                    .tabViewStyle(.page)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            if docVM.savedDocuments.isEmpty {
                Text("No saved documents yet.\nScan/import to create Last Session (Auto).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(docVM.savedDocuments) { summary in
                            libraryCard(for: summary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemBackground).opacity(0.5))
    }

    private var savedLibrarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .font(.headline)
                .padding(.horizontal)
            if docVM.savedDocuments.isEmpty {
                Text("No saved documents yet. Scan/import a document and tap the save icon.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(docVM.savedDocuments) { summary in
                            libraryCard(for: summary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 8)
    }

    private func libraryCard(for summary: SavedDocumentSummary) -> some View {
        Button(action: {
            docVM.loadSavedDocument(summary)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                if let uiImage = UIImage(contentsOfFile: summary.thumbnailURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 90)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 120, height: 90)
                }
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text("\(summary.pageCount) pages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 140, alignment: .leading)
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Load") {
                docVM.loadSavedDocument(summary)
            }
            Button("Delete", role: .destructive) {
                pendingDeleteDocument = summary
            }
        }
    }

    private func defaultSaveTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Document \(formatter.string(from: Date()))"
    }
}
