//
//  CommitGraphView.swift
//  GitX
//
//  Commit graph visualization showing branch lines and merge points
//

import SwiftUI

// MARK: - Graph Layout

/// Represents the computed graph layout for a commit
struct CommitGraphLayout {
    let position: Int          // Column position for the commit node
    let numColumns: Int        // Total number of columns
    let lines: [GraphLine]     // Lines to draw
}

/// A line segment in the graph
struct GraphLine {
    let upper: Bool        // true = draw from top to center, false = from center to bottom
    let from: Int          // Source column
    let to: Int            // Destination column
    let colorIndex: Int    // Color index for the line
}

// MARK: - Graph Computer

class CommitGraphComputer {
    /// Compute the graph layout for all commits
    static func computeLayout(for commits: [CommitInfo]) -> [String: CommitGraphLayout] {
        var layouts: [String: CommitGraphLayout] = [:]

        // Each lane tracks: (oid waiting for this lane, color index)
        var lanes: [(oid: String?, colorIndex: Int)] = []
        var nextColor = 0

        // Build OID to index lookup
        var oidToIndex: [String: Int] = [:]
        for (index, commit) in commits.enumerated() {
            oidToIndex[commit.oid] = index
        }

        for commit in commits {
            var lines: [GraphLine] = []
            var commitLane = -1

            // Find which lane this commit is on (the lane waiting for it)
            for (laneIndex, lane) in lanes.enumerated() {
                if lane.oid == commit.oid {
                    commitLane = laneIndex
                    break
                }
            }

            // If no lane waiting, assign to first free lane or create new
            if commitLane == -1 {
                if let freeLane = lanes.firstIndex(where: { $0.oid == nil }) {
                    commitLane = freeLane
                } else {
                    commitLane = lanes.count
                    lanes.append((oid: nil, colorIndex: nextColor))
                    nextColor += 1
                }
            }

            let commitColor = lanes[commitLane].colorIndex

            // Draw lines for each active lane
            for (laneIndex, lane) in lanes.enumerated() {
                guard let waitingOID = lane.oid else { continue }

                if waitingOID == commit.oid {
                    // This lane leads to this commit - draw upper line to node
                    lines.append(GraphLine(
                        upper: true,
                        from: laneIndex,
                        to: commitLane,
                        colorIndex: lane.colorIndex
                    ))
                } else {
                    // This lane passes through - draw full vertical line
                    lines.append(GraphLine(
                        upper: true,
                        from: laneIndex,
                        to: laneIndex,
                        colorIndex: lane.colorIndex
                    ))
                    lines.append(GraphLine(
                        upper: false,
                        from: laneIndex,
                        to: laneIndex,
                        colorIndex: lane.colorIndex
                    ))
                }
            }

            // Clear lanes that were waiting for this commit
            for laneIndex in 0..<lanes.count {
                if lanes[laneIndex].oid == commit.oid {
                    lanes[laneIndex].oid = nil
                }
            }

            // Handle parents
            let parents = commit.parents

            if !parents.isEmpty {
                // First parent continues on commit's lane
                lanes[commitLane].oid = parents[0]
                lines.append(GraphLine(
                    upper: false,
                    from: commitLane,
                    to: commitLane,
                    colorIndex: commitColor
                ))

                // Additional parents (merge) need their own lanes
                for parentIndex in 1..<parents.count {
                    let parentOID = parents[parentIndex]

                    // Check if parent already has a lane
                    var parentLane: Int? = nil
                    for (laneIndex, lane) in lanes.enumerated() {
                        if lane.oid == parentOID {
                            parentLane = laneIndex
                            break
                        }
                    }

                    if parentLane == nil {
                        // Find or create lane for this parent
                        if let freeLane = lanes.firstIndex(where: { $0.oid == nil }) {
                            parentLane = freeLane
                            lanes[freeLane] = (oid: parentOID, colorIndex: nextColor)
                        } else {
                            parentLane = lanes.count
                            lanes.append((oid: parentOID, colorIndex: nextColor))
                        }
                        nextColor += 1
                    }

                    // Draw line from commit to parent's lane
                    lines.append(GraphLine(
                        upper: false,
                        from: commitLane,
                        to: parentLane!,
                        colorIndex: lanes[parentLane!].colorIndex
                    ))
                }
            }

            // Compact lanes - remove trailing empty lanes
            while !lanes.isEmpty && lanes.last?.oid == nil {
                lanes.removeLast()
            }

            layouts[commit.oid] = CommitGraphLayout(
                position: commitLane,
                numColumns: max(lanes.count, commitLane + 1),
                lines: lines
            )
        }

        return layouts
    }
}

// MARK: - Graph Cell View

struct CommitGraphCell: View {
    let layout: CommitGraphLayout
    let isCurrentCommit: Bool

    let columnWidth: CGFloat = 10
    let rowHeight: CGFloat = 22

    // Colors matching original GitX (hue-based)
    static let laneColors: [Color] = {
        let count = 8
        var colors: [Color] = []
        for i in 0..<count {
            let hue = Double(i) / Double(count)
            colors.append(Color(hue: hue, saturation: 0.7, brightness: 0.8))
        }
        return colors
    }()

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let centerY = size.height / 2

                // Draw all lines
                for line in layout.lines {
                    let color = Self.laneColors[line.colorIndex % Self.laneColors.count]
                    let fromX = columnX(line.from)
                    let toX = columnX(line.to)

                    var path = Path()

                    if line.upper {
                        // Draw from top of cell to center
                        path.move(to: CGPoint(x: fromX, y: 0))
                        path.addLine(to: CGPoint(x: toX, y: centerY))
                    } else {
                        // Draw from center to bottom of cell
                        path.move(to: CGPoint(x: fromX, y: centerY))
                        path.addLine(to: CGPoint(x: toX, y: size.height))
                    }

                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .square))
                }

                // Draw commit node
                let nodeX = columnX(layout.position)
                let nodeRadius: CGFloat = 4

                let nodeRect = CGRect(
                    x: nodeX - nodeRadius,
                    y: centerY - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )

                // Black outline
                context.fill(Circle().path(in: nodeRect), with: .color(.black))

                // Inner fill (white, or orange for current commit)
                let innerRadius = nodeRadius - 1.2
                let innerRect = CGRect(
                    x: nodeX - innerRadius,
                    y: centerY - innerRadius,
                    width: innerRadius * 2,
                    height: innerRadius * 2
                )

                let fillColor: Color = isCurrentCommit
                    ? Color(red: 0xfc/255.0, green: 0xa6/255.0, blue: 0x4f/255.0)
                    : .white
                context.fill(Circle().path(in: innerRect), with: .color(fillColor))
            }
        }
        .frame(width: CGFloat(layout.numColumns) * columnWidth + 10)
    }

    private func columnX(_ column: Int) -> CGFloat {
        return CGFloat(column) * columnWidth + 5
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        // Simulated graph - straight line
        let layout1 = CommitGraphLayout(position: 0, numColumns: 1, lines: [
            GraphLine(upper: true, from: 0, to: 0, colorIndex: 0),
            GraphLine(upper: false, from: 0, to: 0, colorIndex: 0)
        ])

        // Branch out
        let layout2 = CommitGraphLayout(position: 0, numColumns: 2, lines: [
            GraphLine(upper: true, from: 0, to: 0, colorIndex: 0),
            GraphLine(upper: false, from: 0, to: 0, colorIndex: 0),
            GraphLine(upper: false, from: 0, to: 1, colorIndex: 1)
        ])

        // Parallel
        let layout3 = CommitGraphLayout(position: 0, numColumns: 2, lines: [
            GraphLine(upper: true, from: 0, to: 0, colorIndex: 0),
            GraphLine(upper: false, from: 0, to: 0, colorIndex: 0),
            GraphLine(upper: true, from: 1, to: 1, colorIndex: 1),
            GraphLine(upper: false, from: 1, to: 1, colorIndex: 1)
        ])

        // Merge
        let layout4 = CommitGraphLayout(position: 0, numColumns: 2, lines: [
            GraphLine(upper: true, from: 0, to: 0, colorIndex: 0),
            GraphLine(upper: true, from: 1, to: 0, colorIndex: 1),
            GraphLine(upper: false, from: 0, to: 0, colorIndex: 0)
        ])

        ForEach(Array([layout1, layout2, layout3, layout4].enumerated()), id: \.offset) { index, layout in
            HStack(spacing: 0) {
                CommitGraphCell(layout: layout, isCurrentCommit: index == 0)
                Text("Commit message \(index + 1)")
                    .padding(.leading, 8)
            }
        }
    }
    .padding()
    .background(Color(nsColor: .textBackgroundColor))
}
