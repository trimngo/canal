import SwiftUI
import LedgerCore

/// All categories stay visible while the date columns scroll horizontally.
struct CategoryHeatmapView: View {
    @EnvironmentObject private var store: LedgerStore
    let report: HistoryReport
    let select: (HistoryCategoryRow) -> Void
    @AppStorage("history.heatmap.percent") private var percent = true
    @ScaledMetric private var rowHeight = 44
    @State private var selectedDay: Date?
    @State private var selectedCategoryID: String?

    private var calendar: Calendar { store.ledger.reportingCalendar() }

    var body: some View {
        let grid = HistoryHeatmap(report: report, ledger: store.ledger, calendar: calendar)
        GeometryReader { geometry in
            let labelWidth = min(140, geometry.size.width * 0.32)
            let columnWidth = max(32, (geometry.size.width - labelWidth - 8) / CGFloat(max(1, min(7, grid.days.count))))
            VStack(alignment: .leading, spacing: 10) {
                Picker("Heatmap units", selection: $percent) {
                    Text("Hours").tag(false)
                    Text("Percentages").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("report.heatmap.units")
                Text("All categories · Darker means more time")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("0")
                    LinearGradient(colors: [.teal.opacity(0.12), .teal], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 80, height: 8).clipShape(Capsule())
                    Text(percent ? "100%" : store.duration(grid.maximumMinutes))
                    Spacer(minLength: 0)
                    Text("— No data")
                }.font(.caption2).foregroundStyle(.secondary)
                if let day = selectedDay, let id = selectedCategoryID {
                    selectedValue(grid: grid, day: day, categoryID: id)
                }
                if grid.rows.isEmpty {
                    Text("Log an activity to start this view.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ScrollView {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Category").font(.caption.bold()).frame(height: rowHeight)
                                ForEach(grid.rows) { row in
                                    if row.hasChildren {
                                        Button { select(row) } label: { rowLabel(row).fontWeight(.semibold) }
                                            .buttonStyle(.plain).accessibilityAddTraits(.isHeader)
                                            .accessibilityIdentifier("report.heatmap.heading.\(row.id)")
                                    } else {
                                        Button { select(row) } label: { rowLabel(row) }
                                            .buttonStyle(.plain).accessibilityIdentifier("report.heatmap.category.\(row.id)")
                                    }
                                }
                            }.frame(width: labelWidth, alignment: .leading)
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 0) {
                                    ForEach(grid.days, id: \.self) { day in
                                        VStack(spacing: 4) {
                                            VStack(spacing: 2) {
                                                Text(month(day))
                                                Text("\(calendar.component(.day, from: day))").bold()
                                            }.font(.caption2).frame(height: rowHeight)
                                                .foregroundStyle(calendar.isDate(day, inSameDayAs: report.end) && calendar.isDateInToday(day) ? Color.accentColor : .secondary)
                                                .accessibilityLabel(store.dayLabel(day))
                                            ForEach(grid.rows) { row in
                                                if row.hasChildren {
                                                    Color.clear.frame(height: rowHeight).accessibilityHidden(true)
                                                } else {
                                                    cell(point: grid.point(on: day, categoryID: row.id), day: day, row: row, maximum: grid.maximumMinutes)
                                                }
                                            }
                                        }.frame(width: columnWidth)
                                    }
                                }.padding(.bottom, 6)
                            }.defaultScrollAnchor(.trailing).accessibilityIdentifier("report.heatmap.grid")
                        }
                        Text("Tap a square for details or a category for its logs. Today is incomplete. Scroll across for more dates.")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        if grid.days.count == 1 {
                            Text("Choose Past 7 days or a longer period to compare days.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        }
                    }.accessibilityIdentifier("report.heatmap.rows")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("report.view.heatmap")
            .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            .onChange(of: report.start) { _, _ in clearSelection() }
            .onChange(of: calendar.startOfDay(for: report.end)) { _, _ in clearSelection() }
            .onChange(of: calendar.timeZone.identifier) { _, _ in clearSelection() }
            .onChange(of: grid.rows.map(\.id)) { _, ids in
                if let selectedCategoryID, !ids.contains(selectedCategoryID) { clearSelection() }
            }
    }

    private func rowLabel(_ item: HistoryCategoryRow) -> some View {
        Text(item.row.name).font(.subheadline).foregroundStyle(.primary).lineLimit(2).minimumScaleFactor(0.8)
            .padding(.leading, CGFloat(item.depth) * 10)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight)
            .contentShape(Rectangle())
    }

    private func cell(point: DailyTotal?, day: Date, row: HistoryCategoryRow, maximum: Double) -> some View {
        let value = point.map { percent ? $0.percent : $0.minutes }
        let intensity = value.map { min(1, max(0, $0 / max(1, percent ? 100 : maximum))) } ?? 0
        let isSelected = selectedDay == day && selectedCategoryID == row.id
        return Button {
            selectedDay = day; selectedCategoryID = row.id
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(point == nil ? Color.secondary.opacity(0.08) : Color.teal.opacity(0.12 + intensity * 0.88))
                Text(point.map { percent ? "\(Int($0.percent.rounded()))" : ($0.minutes / 60).formatted(.number.precision(.fractionLength(0...1))) } ?? "—")
                    .font(.caption2).minimumScaleFactor(0.7).lineLimit(1)
                    .foregroundStyle(intensity > 0.65 ? Color.white : Color.primary)
            }.frame(height: rowHeight).padding(.horizontal, 2)
                .overlay { if isSelected { RoundedRectangle(cornerRadius: 5).stroke(Color.primary, lineWidth: 2).padding(.horizontal, 2) } }
        }.buttonStyle(.plain)
            .accessibilityLabel("\(row.row.name), \(store.dayLabel(day))")
            .accessibilityValue(point.map { "\($0.percent.formatted(.number.precision(.fractionLength(1)))) percent, \(store.duration($0.minutes))" } ?? "No data")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("report.heatmap.cell.\(row.id).\(Int(day.timeIntervalSince1970))")
    }

    private func selectedValue(grid: HistoryHeatmap, day: Date, categoryID: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(grid.rows.first { $0.id == categoryID }?.row.name ?? "Category") · \(store.dayLabel(day))").font(.subheadline.bold())
            if let point = grid.point(on: day, categoryID: categoryID) {
                Text("\(point.percent, specifier: "%.1f")% · \(store.duration(point.minutes))")
            } else { Text("No data for this day.") }
        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine).accessibilityIdentifier("report.heatmap.selection")
    }

    private func clearSelection() { selectedDay = nil; selectedCategoryID = nil }

    private func month(_ day: Date) -> String {
        var format = Date.FormatStyle().month(.abbreviated)
        format.calendar = calendar; format.timeZone = calendar.timeZone
        return day.formatted(format)
    }
}
