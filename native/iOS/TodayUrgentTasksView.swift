import SwiftUI
import LedgerCore

struct TodayUrgentTasksView: View {
    @EnvironmentObject private var store: LedgerStore
    let now: Date
    @State private var editing: Capture?

    var body: some View {
        let groups = store.ledger.urgentCaptureGroups(at: now)
        let count = Set(groups.flatMap { $0.captures.map(\.id) }).count
        VStack(alignment: .leading, spacing: 16) {
            Text("Urgent tasks (\(count))").font(.headline).accessibilityIdentifier("today.urgent-title")
            if groups.isEmpty {
                Text("No urgent tasks").foregroundStyle(.secondary).accessibilityIdentifier("today.urgent-empty")
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("today.urgent-category.\(group.id)")
                    ForEach(group.captures) { capture in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                do { try store.setCaptureDone(capture, done: true) } catch { store.report(error) }
                            } label: {
                                Image(systemName: "circle").font(.title3).frame(width: 36, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Complete \(capture.text)")
                                .accessibilityIdentifier("today.urgent-complete.\(group.id).\(capture.id)")
                            Button { editing = capture } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(capture.text).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                    Text(timing(capture)).font(.caption).foregroundStyle(.orange)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("today.urgent-task.\(group.id).\(capture.id)")
                        }
                        Divider()
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .sheet(item: $editing) { TaskPlanningView(capture: $0) }
    }

    private func timing(_ capture: Capture) -> String {
        guard let urgency = store.ledger.urgency(for: capture) else { return "" }
        if let due = urgency.timing.dueAt { return "Due " + due.formatted(date: .abbreviated, time: .omitted) }
        return urgency.isSuggested ? "Suggested ASAP" : "ASAP"
    }
}
