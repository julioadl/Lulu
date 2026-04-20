import SwiftUI

struct WordResultsView: View {
    let results: [SpeechRecognitionViewModel.WordResult]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Your pronunciation:")
                .font(.headline)
            
            // Layout words into rows and display as VStack of HStacks
            let rows = buildRows(results)
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex]) { result in
                        Text(result.word)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(result.correct ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                            .cornerRadius(8)
                    }
                }
            }
            
            // Show score
            Text("\(results.filter { $0.correct }.count) / \(results.count) words correct")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func buildRows(_ results: [SpeechRecognitionViewModel.WordResult]) -> [[SpeechRecognitionViewModel.WordResult]] {
        var rows: [[SpeechRecognitionViewModel.WordResult]] = []
        var currentRow: [SpeechRecognitionViewModel.WordResult] = []
        
        for result in results {
            let estimatedWidth = (result.word.count + 2) * 10 // Simplified estimation
            if currentRow.reduce(0, { $0 + $1.word.count }) + estimatedWidth > 300 {
                rows.append(currentRow)
                currentRow = []
            }
            currentRow.append(result)
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
}
