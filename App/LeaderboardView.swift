import SwiftUI
import GrappleCore

/// The race leaderboard sheet: totals for one course (with a hole-by-hole scorecard) or for every course.
struct LeaderboardView: View {
    struct CourseInfo: Identifiable {
        let id: Int
        let name: String
        /// Hole file names, in order.
        let holes: [String]
    }

    let courses: [CourseInfo]
    /// Which course to show first; nil shows all courses.
    @State var selection: Int?
    @State private var board = LeaderboardStore.load()
    @State private var confirmNewRound = false
    @Environment(\.dismiss) private var dismiss

    private var selectedHoles: [String]? {
        selection.flatMap { index in courses.first { $0.id == index }?.holes }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $selection) {
                        Text("All courses").tag(Int?.none)
                        ForEach(courses) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                }

                Section {
                    let rows = board.standings(for: selectedHoles)
                    ForEach(Array(rows.enumerated()), id: \.element.name) { index, row in
                        HStack {
                            Text("\(index + 1)").monospacedDigit().frame(width: 24, alignment: .leading)
                            Text(row.isPlayer ? "You" : row.name).fontWeight(row.isPlayer ? .bold : .regular)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(row.toParText).font(.headline).monospacedDigit()
                                    .foregroundStyle(row.toPar <= 0 ? Color.green : Color.red)
                                Text("\(row.strokes) swings · \(row.holeWins) won\(row.pickUps > 0 ? " · \(row.pickUps) picked up" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(header)
                } footer: {
                    Text("Fewest total swings leads, then fewest holes given up, then fastest total time. Replaying a hole replaces its score. Finishing a course's first hole starts a new round of it.")
                }

                if let selection, let course = courses.first(where: { $0.id == selection }) {
                    Section("Scorecard") { scorecard(course) }
                }

                Section {
                    Button(selection == nil ? "Clear all scores" : "New round of this course", role: .destructive) {
                        confirmNewRound = true
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear these scores?", isPresented: $confirmNewRound, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    if let holes = selectedHoles { board.clear(holes: holes) } else { board.clearAll() }
                    LeaderboardStore.save(board)
                }
            }
        }
    }

    private var header: String {
        let played = board.played(selectedHoles).count
        guard let holes = selectedHoles else { return "All courses · \(played) holes played" }
        return "\(played) of \(holes.count) holes played"
    }

    /// Swings per hole for everyone, with par on top.
    private func scorecard(_ course: CourseInfo) -> some View {
        let rows = board.standings(for: course.holes)
        return ScrollView(.horizontal) {
            Grid(alignment: .center, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Hole").bold().gridColumnAlignment(.leading)
                    ForEach(course.holes.indices, id: \.self) { Text("\($0 + 1)").bold() }
                    Text("Tot").bold()
                }
                GridRow {
                    Text("Par").foregroundStyle(.secondary)
                    ForEach(course.holes, id: \.self) { hole in
                        Text(board.results[hole].map { "\($0.par)" } ?? "–").foregroundStyle(.secondary)
                    }
                    Text("\(board.played(course.holes).reduce(0) { $0 + $1.par })").foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.name) { row in
                    GridRow {
                        Text(row.isPlayer ? "You" : (row.name.components(separatedBy: " ").last ?? row.name))
                            .fontWeight(row.isPlayer ? .bold : .regular)
                        ForEach(course.holes, id: \.self) { hole in
                            if let result = board.results[hole], let entry = result.entries.first(where: { $0.name == row.name }) {
                                Text(entry.time == nil ? "\(entry.strokes)*" : "\(entry.strokes)")
                                    .foregroundStyle(entry.strokes < result.par ? Color.green
                                                     : entry.strokes > result.par ? Color.red : Color.primary)
                                    .fontWeight(result.winner == row.name ? .heavy : .regular)
                            } else {
                                Text("–").foregroundStyle(.secondary)
                            }
                        }
                        Text("\(row.strokes)").bold()
                    }
                }
            }
            .monospacedDigit()
            .font(.callout)
            .padding(.vertical, 4)
        }
    }
}
