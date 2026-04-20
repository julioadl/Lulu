import SwiftUI
import AVFoundation
import PDFKit

@MainActor
class DocumentViewModel: ObservableObject {
    @Published var pages: [DocumentPage] = []
    @Published var isProcessing = false
    @Published var errorMessage: String? = nil
    @Published var selectedSentence: Sentence? = nil
    
    func loadFromScan(_ images: [UIImage]) async {
        isProcessing = true
        pages.removeAll()
        do {
            for (index, image) in images.enumerated() {
                let sentences = try await OCRService.shared.extractSentences(from: image, pageIndex: index)
                pages.append(DocumentPage(index: index, image: image, sentences: sentences))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    func loadFromPDF(_ url: URL) async {
        isProcessing = true
        pages.removeAll()
        guard let pdfDocument = PDFDocument(url: url) else {
            errorMessage = "Failed to load PDF document."
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}
