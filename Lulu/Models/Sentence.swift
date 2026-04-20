import SwiftUI

struct Sentence: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var boundingBox: CGRect
    let pageIndex: Int
    
    enum CodingKeys: CodingKey {
        case id
        case text
        case x, y, width, height
        case pageIndex
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.text = try container.decode(String.self, forKey: .text)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.boundingBox = CGRect(x: x, y: y, width: width, height: height)
        self.pageIndex = try container.decode(Int.self, forKey: .pageIndex)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        let rect = boundingBox
        try container.encode(rect.origin.x, forKey: .x)
        try container.encode(rect.origin.y, forKey: .y)
        try container.encode(rect.size.width, forKey: .width)
        try container.encode(rect.size.height, forKey: .height)
        try container.encode(pageIndex, forKey: .pageIndex)
    }
}
