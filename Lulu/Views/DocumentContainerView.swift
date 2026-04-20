import SwiftUI

struct DocumentContainerView: View {
    @EnvironmentObject var docVM: DocumentViewModel
    @EnvironmentObject var ttsVM: TTSViewModel
    @State private var showScanner = false
    @State private var showFilePicker = false
    
    var body: some View {
        VStack {
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
                TabView {
                    ForEach(docVM.pages) { page in
                        DocumentPageView(page: page)
                            .tag(page.index)
                    }
                }
                .tabViewStyle(.page)
            }
        }
        .navigationTitle("Lulu")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showScanner = true }) {
                        Label("Scan Document", systemImage: "camera")
                    }
                    Button(action: { showFilePicker = true }) {
                        Label("Import PDF", systemImage: "square.and.arrow.down")
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
        .alert(isPresented: Binding<Bool>(
                    get: { docVM.errorMessage != nil },
                    set: { _ in docVM.errorMessage = nil }
                )) {
            Alert(title: Text("Error"), message: Text(docVM.errorMessage ?? ""))
        }
    }
}
