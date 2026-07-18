//
//  ReorderSpikeView.swift
//  InterlinedList
//
//  SPIKE — throwaway. Proves horizontal drag-to-reorder of a thumbnail strip is
//  feasible on iOS 17 before committing it to a follow-up PR. Remove before merge.
//

import SwiftUI
import UniformTypeIdentifiers

private struct SpikeTile: Identifiable, Equatable {
    let id: Int
    let color: Color
}

struct ReorderSpikeView: View {
    @State private var tiles: [SpikeTile] = [
        .init(id: 0, color: .red), .init(id: 1, color: .orange), .init(id: 2, color: .yellow),
        .init(id: 3, color: .green), .init(id: 4, color: .blue), .init(id: 5, color: .purple)
    ]
    @State private var dragging: SpikeTile?

    var body: some View {
        VStack(alignment: .leading) {
            Text("order: " + tiles.map { String($0.id) }.joined(separator: ","))
                .font(.footnote.monospaced())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tiles) { tile in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tile.color)
                            .frame(width: 72, height: 72)
                            .overlay(Text("\(tile.id)").foregroundStyle(.white).bold())
                            .opacity(dragging == tile ? 0.35 : 1)
                            .onDrag {
                                dragging = tile
                                return NSItemProvider(object: String(tile.id) as NSString)
                            } preview: {
                                RoundedRectangle(cornerRadius: 8).fill(tile.color)
                                    .frame(width: 72, height: 72)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: ReorderDropDelegate(item: tile, tiles: $tiles, dragging: $dragging)
                            )
                    }
                }
                .padding()
            }
        }
    }
}

private struct ReorderDropDelegate: DropDelegate {
    let item: SpikeTile
    @Binding var tiles: [SpikeTile]
    @Binding var dragging: SpikeTile?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = tiles.firstIndex(of: dragging),
              let to = tiles.firstIndex(of: item) else { return }
        if tiles[to] != dragging {
            withAnimation {
                tiles.move(fromOffsets: IndexSet(integer: from),
                           toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

#Preview {
    ReorderSpikeView()
}
