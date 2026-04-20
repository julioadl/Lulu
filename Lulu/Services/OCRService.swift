import UIKit
import Vision

actor OCRService {
    static let shared = OCRService()
    
    func extractSentences(from image: UIImage, pageIndex: Int) async throws -> [Sentence] {
        return try await withCheckedThrowingContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(throwing: NSError(domain: "Invalid Image", code: -1, userInfo: nil))
                return
            }
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNRecognizeTextRequest { (request, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(with: .success([]))
                    return
                }
                
                let sentences = observations.enumerated().map { (_, observation) -> Sentence in
                    let topCandidate = observation.topCandidates(1).first?.string ?? ""
                    let boundingBox = CGRect(
                        x: observation.boundingBox.origin.x,
                        y: 1 - observation.boundingBox.maxY,
                        width: observation.boundingBox.width,
                        height: observation.boundingBox.height
                    )
                    return Sentence(id: UUID(), text: topCandidate, boundingBox: boundingBox, pageIndex: pageIndex)
                }
                
                let groupedSentences = groupSentencesByProximity(sentences)
                continuation.resume(with: .success(groupedSentences))
            }
            
            request.recognitionLanguages = ["fr-FR"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func groupSentencesByProximity(_ sentences: [Sentence]) -> [Sentence] {
        var groupedSentences: [Sentence] = []
        
        for sentence in sentences {
            if let lastGrouped = groupedSentences.last, abs(lastGrouped.boundingBox.midY - sentence.boundingBox.midY) < 0.015 {
                // Merge sentences
                let mergedText = "\(lastGrouped.text) \(sentence.text)"
                let mergedBoundingBox = CGRect(
                    x: min(lastGrouped.boundingBox.minX, sentence.boundingBox.minX),
                    y: min(lastGrouped.boundingBox.minY, sentence.boundingBox.minY),
                    width: max(lastGrouped.boundingBox.maxX, sentence.boundingBox.maxX) - min(lastGrouped.boundingBox.minX, sentence.boundingBox.minX),
                    height: max(lastGrouped.boundingBox.maxY, sentence.boundingBox.maxY) - min(lastGrouped.boundingBox.minY, sentence.boundingBox.minY)
                )
                let mergedSentence = Sentence(id: lastGrouped.id, text: mergedText, boundingBox: mergedBoundingBox, pageIndex: lastGrouped.pageIndex)
                groupedSentences[groupedSentences.count - 1] = mergedSentence
            } else {
                groupedSentences.append(sentence)
            }
        }
        
        return groupedSentences.sorted { (s1, s2) -> Bool in
            if abs(s1.boundingBox.midY - s2.boundingBox.midY) < 0.001 {
                return s1.boundingBox.minX < s2.boundingBox.minX
            }
            return s1.boundingBox.midY < s2.boundingBox.midY
        }
    }
}

