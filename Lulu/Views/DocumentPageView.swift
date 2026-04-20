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
                                .fill(Color.yellow.opacity(ttsVM.currentSentence?.id == sentence.id ? 0.5 : 0))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.yellow.opacity(ttsVM.currentSentence?.id == sentence.id ? 0.3 : 0), lineWidth: 2)
                                )
                                .frame(width: scaledRect.width, height: scaledRect.height)
                                .offset(x: scaledRect.minX, y: scaledRect.minY)
                                .onTapGesture {
                                    docVM.selectedSentence = sentence
                                    ttsVM.speak(sentence: sentence)
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
}
