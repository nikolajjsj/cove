import CoveUI
import SwiftUI

/// A section displaying studio names as flow-layout chips.
struct StudiosSection: View {
    let studios: [String]

    var body: some View {
        if !studios.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Studios")
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(studios, id: \.self) { studio in
                        Text(studio)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.tertiarySystemFill))
                            )
                    }
                }
            }
        }
    }
}
