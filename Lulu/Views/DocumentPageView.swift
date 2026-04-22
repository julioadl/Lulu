import SwiftUI

struct DocumentPageView: View {
    let page: DocumentPage
    @EnvironmentObject var docVM: DocumentViewModel
    @EnvironmentObject var ttsVM: TTSViewModel
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = page.image {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(10)
                }
                .overlay {
                    ForEach(page.sentences, id: \.id) { sentence in
                        GeometryReader { geo in
                            let size = geo.size
                            let scaledRect = CGRect(
                                x: sentence.boundingBox.minX * size.width,
                                y: sentence.boundingBox.minY * size.height,
                                width: sentence.boundingBox.width * size.width,
                                height: sentence.boundingBox.height * size.height
                            )
                            
                            RoundedRectangle(cornerRadius: 5)
                                .fill(backgroundColor(for: sentence))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(borderColor(for: sentence), lineWidth: 2)
                                )
                                .frame(width: scaledRect.width, height: scaledRect.height)
                                .offset(x: scaledRect.minX, y: scaledRect.minY)
                                .onTapGesture {
                                    docVM.toggleSentenceSelection(sentence)
                                }
                        }
                    }
                }
            } else {
                Text("No image available")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func backgroundColor(for sentence: Sentence) -> Color {
        if ttsVM.currentSentence?.id == sentence.id {
            return Color.yellow.opacity(0.5)
        }
        if docVM.isSentenceSelected(sentence) {
            return Color.blue.opacity(0.25)
        }
        return Color.clear
    }

    private func borderColor(for sentence: Sentence) -> Color {
        if ttsVM.currentSentence?.id == sentence.id {
            return Color.yellow.opacity(0.6)
        }
        if docVM.isSentenceSelected(sentence) {
            return Color.blue.opacity(0.6)
        }
        return Color.clear
    }
}
