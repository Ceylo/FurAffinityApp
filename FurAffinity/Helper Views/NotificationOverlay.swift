//
//  NotificationOverlay.swift
//  FurAffinity
//
//  Created by Ceylo on 07/01/2022.
//

import SwiftUI

extension AnyTransition {
    static var fallAndFade: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}


struct NotificationOverlay: View {
    @Binding var itemCount: Int?
    var dismissAfter: TimeInterval = 3.0
    
    private func text(count: Int) -> String {
        switch count {
        case 0: return "No new submission"
        case 1: return "1 new submission"
        default: return "\(count) new submissions"
        }
    }
    
    @ViewBuilder
    func badge(_ count: Int) -> some View {
        if #available(iOS 26, *) {
            Text(text(count: count))
                .font(.callout)
                .foregroundColor(Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect()
        } else {
            Text(text(count: count))
                .font(.callout)
                .foregroundColor(Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.33) , radius: 5, x: 0, y: 0)
        }
    }
    
    var body: some View {
        if let itemCount = itemCount {
            badge(itemCount)
                .task {
                    do {
                        let nano = UInt64(dismissAfter * 1e9)
                        try await Task.sleep(nanoseconds: nano)
                        withAnimation {
                            self.itemCount = nil
                        }
                    } catch is CancellationError {
                        self.itemCount = nil
                    } catch {}
                }
                .transition(.fallAndFade)
        }
    }
}

private struct Checkerboard: Shape {
    let rows: Int
    let columns: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // figure out how big each row/column needs to be
        let rowSize = rect.height / Double(rows)
        let columnSize = rect.width / Double(columns)

        // loop over all rows and columns, making alternating squares colored
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                if (row + column).isMultiple(of: 2) {
                    // this square should be colored; add a rectangle here
                    let startX = columnSize * Double(column)
                    let startY = rowSize * Double(row)

                    let rect = CGRect(x: startX, y: startY, width: columnSize, height: rowSize)
                    path.addRect(rect)
                }
            }
        }

        return path
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    NotificationOverlay(itemCount: .constant(12))
        .padding()
        .background(Checkerboard(rows: 5, columns: 16).fill(.cyan))
}
