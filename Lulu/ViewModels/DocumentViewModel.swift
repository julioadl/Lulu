import SwiftUI
import AVFoundation
import PDFKit

struct SavedDocumentSummary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    let pageCount: Int
    let thumbnailURL: URL
    let folderURL: URL
}

struct SavedDocumentManifest: Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let pages: [SavedPageManifest]
}

struct SavedPageManifest: Codable {
    let index: Int
    let imageFileName: String
    let sentences: [Sentence]
}

@MainActor
class DocumentViewModel: ObservableObject {
    @Published var pages: [DocumentPage] = []
    @Published var isProcessing = false
    @Published var errorMessage: String? = nil
    @Published var selectedSentence: Sentence? = nil
    @Published var selectedSentenceIDs: Set<UUID> = []
    @Published var savedDocuments: [SavedDocumentSummary] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let autosaveFolderName = "_autosave"
    private let autosaveDocumentID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    init() {
        refreshSavedDocuments()
    }

    var selectedSentences: [Sentence] {
        let all = pages.flatMap { $0.sentences }
        if selectedSentenceIDs.isEmpty {
            return all
        }
        return all.filter { selectedSentenceIDs.contains($0.id) }
    }
    
    func loadFromScan(_ images: [UIImage]) async {
        isProcessing = true
        pages.removeAll()
        selectedSentenceIDs.removeAll()
        do {
            for (index, image) in images.enumerated() {
                let sentences = try await OCRService.shared.extractSentences(from: image, pageIndex: index)
                pages.append(DocumentPage(index: index, image: image, sentences: sentences))
            }
            if !pages.isEmpty {
                try upsertAutosavedDocument()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    func loadFromPDF(_ url: URL) async {
        isProcessing = true
        pages.removeAll()
        selectedSentenceIDs.removeAll()
        errorMessage = nil

        // URLs returned by fileImporter (especially from iCloud Drive) may require security-scoped access.
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let pdfDocument: PDFDocument?
        if let doc = PDFDocument(url: url) {
            pdfDocument = doc
        } else if let data = try? Data(contentsOf: url), let doc = PDFDocument(data: data) {
            // Fallback path for providers that fail URL-based open but allow data streaming.
            pdfDocument = doc
        } else {
            pdfDocument = nil
        }

        guard let pdfDocument else {
            errorMessage = "Failed to load PDF document. If this file is in iCloud, make sure it is fully downloaded first."
            isProcessing = false
            return
        }
        do {
            for index in 0..<pdfDocument.pageCount {
                guard let pdfPage = pdfDocument.page(at: index) else { continue }
                let thumbnailImage = pdfPage.thumbnail(of: CGSize(width: 800, height: 1100), for: .mediaBox)
                let sentences = try await OCRService.shared.extractSentences(from: thumbnailImage, pageIndex: index)
                pages.append(DocumentPage(index: index, image: thumbnailImage, sentences: sentences))
            }
            if !pages.isEmpty {
                try upsertAutosavedDocument()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    func saveCurrentDocument(title: String) {
        let sanitizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            errorMessage = "Please enter a valid document name."
            return
        }
        guard !pages.isEmpty else {
            errorMessage = "There is no document loaded to save."
            return
        }

        do {
            let libraryURL = try ensureLibraryDirectory()
            let documentID = UUID()
            let documentFolderURL = libraryURL.appendingPathComponent(documentID.uuidString, isDirectory: true)
            try fileManager.createDirectory(at: documentFolderURL, withIntermediateDirectories: true)

            var pageManifests: [SavedPageManifest] = []
            for page in pages.sorted(by: { $0.index < $1.index }) {
                guard let image = page.image else { continue }
                let imageFileName = "page_\(page.index).jpg"
                let imageURL = documentFolderURL.appendingPathComponent(imageFileName)
                guard let imageData = image.jpegData(compressionQuality: 0.9) else { continue }
                try imageData.write(to: imageURL, options: .atomic)
                pageManifests.append(
                    SavedPageManifest(index: page.index, imageFileName: imageFileName, sentences: page.sentences)
                )
            }

            let manifest = SavedDocumentManifest(
                id: documentID,
                title: sanitizedTitle,
                createdAt: Date(),
                pages: pageManifests
            )
            let manifestURL = documentFolderURL.appendingPathComponent("manifest.json")
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)

            refreshSavedDocuments()
        } catch {
            errorMessage = "Could not save document: \(error.localizedDescription)"
        }
    }

    func loadSavedDocument(_ summary: SavedDocumentSummary) {
        do {
            let manifestURL = summary.folderURL.appendingPathComponent("manifest.json")
            let data = try Data(contentsOf: manifestURL)
            let manifest = try decoder.decode(SavedDocumentManifest.self, from: data)

            let loadedPages: [DocumentPage] = manifest.pages.compactMap { page in
                let imageURL = summary.folderURL.appendingPathComponent(page.imageFileName)
                guard let imageData = try? Data(contentsOf: imageURL),
                      let image = UIImage(data: imageData) else {
                    return nil
                }
                return DocumentPage(index: page.index, image: image, sentences: page.sentences)
            }

            pages = loadedPages.sorted(by: { $0.index < $1.index })
            selectedSentenceIDs.removeAll()
            selectedSentence = nil
            errorMessage = nil
        } catch {
            errorMessage = "Could not load saved document: \(error.localizedDescription)"
        }
    }

    func deleteSavedDocument(_ summary: SavedDocumentSummary) {
        do {
            try fileManager.removeItem(at: summary.folderURL)
            refreshSavedDocuments()
        } catch {
            errorMessage = "Could not delete document: \(error.localizedDescription)"
        }
    }

    func refreshSavedDocuments() {
        do {
            let libraryURL = try ensureLibraryDirectory()
            let folderURLs = try fileManager.contentsOfDirectory(
                at: libraryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let summaries: [SavedDocumentSummary] = folderURLs.compactMap { folderURL in
                let manifestURL = folderURL.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? decoder.decode(SavedDocumentManifest.self, from: data),
                      let firstPage = manifest.pages.sorted(by: { $0.index < $1.index }).first else {
                    return nil
                }
                let thumbnailURL = folderURL.appendingPathComponent(firstPage.imageFileName)
                return SavedDocumentSummary(
                    id: manifest.id,
                    title: manifest.title,
                    createdAt: manifest.createdAt,
                    pageCount: manifest.pages.count,
                    thumbnailURL: thumbnailURL,
                    folderURL: folderURL
                )
            }

            savedDocuments = summaries.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            errorMessage = "Could not load saved documents: \(error.localizedDescription)"
            savedDocuments = []
        }
    }

    func isSentenceSelected(_ sentence: Sentence) -> Bool {
        selectedSentenceIDs.contains(sentence.id)
    }

    func toggleSentenceSelection(_ sentence: Sentence) {
        if selectedSentenceIDs.contains(sentence.id) {
            selectedSentenceIDs.remove(sentence.id)
        } else {
            selectedSentenceIDs.insert(sentence.id)
        }
    }

    private func ensureLibraryDirectory() throws -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let libraryURL = appSupportURL.appendingPathComponent("SavedDocuments", isDirectory: true)
        try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        return libraryURL
    }

    private func upsertAutosavedDocument() throws {
        let libraryURL = try ensureLibraryDirectory()
        let documentFolderURL = libraryURL.appendingPathComponent(autosaveFolderName, isDirectory: true)

        if fileManager.fileExists(atPath: documentFolderURL.path) {
            try fileManager.removeItem(at: documentFolderURL)
        }
        try fileManager.createDirectory(at: documentFolderURL, withIntermediateDirectories: true)

        var pageManifests: [SavedPageManifest] = []
        for page in pages.sorted(by: { $0.index < $1.index }) {
            guard let image = page.image else { continue }
            let imageFileName = "page_\(page.index).jpg"
            let imageURL = documentFolderURL.appendingPathComponent(imageFileName)
            guard let imageData = image.jpegData(compressionQuality: 0.9) else { continue }
            try imageData.write(to: imageURL, options: .atomic)
            pageManifests.append(
                SavedPageManifest(index: page.index, imageFileName: imageFileName, sentences: page.sentences)
            )
        }

        let manifest = SavedDocumentManifest(
            id: autosaveDocumentID,
            title: "Last Session (Auto)",
            createdAt: Date(),
            pages: pageManifests
        )
        let manifestURL = documentFolderURL.appendingPathComponent("manifest.json")
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        refreshSavedDocuments()
    }
}
