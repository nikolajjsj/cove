import SwiftUI

/// A single scrolling line showing only the filters that are actually applied.
///
/// Takes no vertical space when nothing is filtered, which is the common case —
/// the previous chip bar always showed every filter and wrapped to two or three
/// rows before the user had narrowed anything.
struct ActiveFilterBar: View {
    var selection: MediaFilterSelection

    var body: some View {
        let active = selection.active

        if !active.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(active) { filter in
                        RemovableFilterChip(filter: filter)
                    }

                    if active.count > 1 {
                        Button("Clear", role: .destructive) {
                            withAnimation(.snappy) { selection.clear() }
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// One applied filter, tappable to remove.
private struct RemovableFilterChip: View {
    let filter: ActiveMediaFilter

    var body: some View {
        Button {
            withAnimation(.snappy) { filter.remove() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.systemImage)
                    .imageScale(.small)
                Text(filter.label)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(filter.label) filter")
    }
}
