import SwiftUI

struct DocumentPage: Identifiable {
    let id = UUID()
    var index: Int
    var image: UIImage?
    var sentences: [Sentence]
}
