import SwiftUI
import Charts
import LedgerCore

/// A small comparison by default, plus separate panels when browsing many
/// categories. These are presentation preferences, never edits to logged time.
struct CategoryTrendView: View {
    @EnvironmentObject private var store: LedgerStore
    let report: HistoryReport
    let isVisible: Bool
    @AppStorage("history.trend.categories.v1") private var savedCategories = ""
    @AppStorage("history.trend.percent") private var percent = false
    @AppStorage("history.trend.layout") private var layout = "compare"
    @State private var choosing = false
    @State private var highlightedID: String?
    @State private var selectedDate: Date?
    @State private var chartDate: Date?

    private var calendar: Calendar { store.ledger.reportingCalendar() }
    private var savedIDs: [String]? {
        guard let data = savedCategories.data(using: .utf8), !savedCategories.isEmpty else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
    private var compared: [BreakdownRow] { report.trendRows(selectedIDs: savedIDs) }
    private var selection: Binding<[String]> {
        Binding(get: { savedIDs ?? report.trendRows(selectedIDs: nil).map(\.id) }, set: saveSelection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Trend units", selection: $percent) {
                    Text("Hours").tag(false)
                    Text("Percentages").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("report.trend.units")
                Picker("Trend display", selection: $layout) {
                    Text("Compare").tag("compare")
                    Text("By category").tag("categories")
                }.pickerStyle(.segmented).accessibilityIdentifier("report.trend.layout")
                Text(percent ? "Share of each day’s tracked time" : "Hours in each category by day")
                    .font(.caption).foregroundStyle(.secondary)
                if report.dailyTotals.isEmpty {
                    Text("Log an activity to start this view.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else if layout == "categories" {
                    categoryPanels
                } else {
                    comparison
                }
                Text("Missing days break the lines. Percentages use all tracked time, including categories hidden from this chart. Today is still in progress.")
                    .font(.caption).foregroundStyle(.secondary)
                if Set(report.dailyTotals.map(\.day)).count == 1 {
                    Text("Choose Past 7 days or a longer period to compare days.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 12)
        }.accessibilityIdentifier("report.view.trend")
            .sheet(isPresented: $choosing) {
                TrendCategoryChooser(rows: report.rows, selection: selection)
            }
            .onChange(of: isVisible, initial: true) { _, visible in
                if visible, savedIDs == nil, !report.rows.isEmpty {
                    saveSelection(report.trendRows(selectedIDs: nil).map(\.id))
                }
            }
            .onChange(of: chartDate) { _, date in
                // Native chart selection can clear on finger-up. Keep the last
                // inspected day readable after the gesture finishes.
                if let date { selectedDate = date }
            }
            .onChange(of: report.start) { _, _ in selectedDate = nil }
            .onChange(of: calendar.startOfDay(for: report.end)) { _, _ in selectedDate = nil }
            .onChange(of: calendar.timeZone.identifier) { _, _ in selectedDate = nil }
            .onChange(of: report.rows.map(\.id)) { _, _ in
                if isVisible, savedIDs == nil, !report.rows.isEmpty { saveSelection(report.trendRows(selectedIDs: nil).map(\.id)) }
            }
            .onChange(of: savedCategories) { _, _ in
                if !compared.contains(where: { $0.id == highlightedID }) { highlightedID = nil }
            }
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(compared.count) categories").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("report.trend.selected-count")
                Spacer()
                Button("Choose categories", systemImage: "line.3.horizontal.decrease") { choosing = true }
                    .font(.subheadline).accessibilityIdentifier("report.trend.choose")
            }
            if compared.isEmpty {
                Text("Choose categories to compare. Your saved choices are kept when you change periods.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(compared) { row in
                            Button {
                                highlightedID = highlightedID == row.id ? nil : row.id
                            } label: {
                                Label(row.name, systemImage: glyph(row.id))
                                    .font(.caption).padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(color(row.id).opacity(highlightedID == row.id ? 0.22 : 0.09), in: Capsule())
                            }.buttonStyle(.plain).foregroundStyle(color(row.id))
                                .accessibilityIdentifier("report.trend.highlight.\(row.id)")
                                .accessibilityLabel("Highlight \(row.name)")
                                .accessibilityAddTraits(highlightedID == row.id ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                chart(points: report.trendPoints(categoryIDs: compared.map(\.id)), sharedScale: false)
                    .frame(height: 220).accessibilityIdentifier("report.trend.chart")
                Text("Tap a category to highlight it. Touch and drag the chart to inspect a day.")
                    .font(.caption).foregroundStyle(.secondary)
                dayValues(rows: compared)
            }
        }
    }

    private var categoryPanels: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            Text("One chart per top-level category · Same scale for every chart. Subcategory time is included in its parent.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(report.rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name).font(.subheadline.bold()).foregroundStyle(color(row.id))
                        Spacer()
                        Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    chart(points: report.trendPoints(categoryIDs: [row.id]), sharedScale: true)
                        .frame(height: 120).accessibilityIdentifier("report.trend.category.\(row.id)")
                    dayValues(rows: [row])
                }
                Divider()
            }
        }
    }

    private func chart(points: [DailyTotal], sharedScale: Bool) -> some View {
        let maximum = percent ? 100 : sharedScale ? report.trendMaximumHours : max(1, points.map { $0.minutes / 60 }.max() ?? 1)
        let lastDay = points.map(\.day).max()
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("Day", point.day), y: .value(percent ? "Percent" : "Hours", value(point)),
                         series: .value("Series", point.seriesID))
                    .foregroundStyle(color(point.categoryID))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: dash(point.categoryID)))
                    .interpolationMethod(.linear)
                    .opacity(opacity(point.categoryID, sharedScale: sharedScale))
                PointMark(x: .value("Day", point.day), y: .value(percent ? "Percent" : "Hours", value(point)))
                    .foregroundStyle(color(point.categoryID)).symbol(symbol(point.categoryID)).symbolSize(28)
                    .opacity(opacity(point.categoryID, sharedScale: sharedScale))
                    .accessibilityLabel("\(point.day.formatted(date: .abbreviated, time: .omitted)), \(point.name)")
                    .accessibilityValue("\(point.percent.formatted(.number.precision(.fractionLength(1)))) percent, \(store.duration(point.minutes))")
                    .annotation(position: .top, alignment: .trailing) {
                        if !sharedScale, highlightedID == point.categoryID, point.day == lastDay {
                            Text(point.name).font(.caption2.bold()).padding(3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
            }
            if let selectedDate {
                RuleMark(x: .value("Selected day", calendar.startOfDay(for: selectedDate)))
                    .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $chartDate)
        .chartXScale(domain: report.start...max(report.end, report.start.addingTimeInterval(3600)))
        .chartYScale(domain: 0...maximum)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { axis in
                AxisGridLine(); AxisTick()
                AxisValueLabel {
                    if let number = axis.as(Double.self) {
                        Text(percent ? "\(number.formatted())%" : "\(number.formatted())h")
                    }
                }
            }
        }
        .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }

    @ViewBuilder
    private func dayValues(rows: [BreakdownRow]) -> some View {
        if let selectedDate {
            let points = report.trendPoints(on: selectedDate, categoryIDs: rows.map(\.id), calendar: calendar)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.dayLabel(calendar.startOfDay(for: selectedDate))).font(.caption.bold())
                if points.isEmpty { Text("No logs for this day.").font(.caption).foregroundStyle(.secondary) }
                ForEach(points) { point in
                    HStack {
                        Text(point.name)
                        Spacer()
                        Text("\(point.percent, specifier: "%.1f")% · \(store.duration(point.minutes))")
                    }.font(.caption)
                }
            }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("report.trend.day-values")
        }
    }

    private func saveSelection(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids), let text = String(data: data, encoding: .utf8) else { return }
        savedCategories = text
    }
    private func value(_ point: DailyTotal) -> Double { percent ? point.percent : point.minutes / 60 }
    private func styleIndex(_ id: String) -> Int { compared.firstIndex(where: { $0.id == id }) ?? 0 }
    private func dash(_ id: String) -> [CGFloat] {
        let patterns: [[CGFloat]] = [[], [6, 3], [2, 3], [8, 3, 2, 3]]
        return patterns[styleIndex(id) % patterns.count]
    }
    private func symbol(_ id: String) -> BasicChartSymbolShape {
        let shapes: [BasicChartSymbolShape] = [.circle, .square, .triangle, .diamond]
        return shapes[styleIndex(id) % shapes.count]
    }
    private func glyph(_ id: String) -> String {
        ["circle.fill", "square.fill", "triangle.fill", "diamond.fill"][styleIndex(id) % 4]
    }
    private func opacity(_ id: String, sharedScale: Bool) -> Double {
        sharedScale || highlightedID == nil || highlightedID == id ? 1 : 0.18
    }
    private func color(_ id: String) -> Color {
        if id == "uncategorized" { return .orange }
        let colors: [Color] = [.teal, .blue, .purple, .pink, .indigo, .mint, .brown]
        return colors[id.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }]
    }
}

private struct TrendCategoryChooser: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [BreakdownRow]
    @Binding var selection: [String]
    @State private var query = ""
    private var filtered: [BreakdownRow] {
        rows.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { row in
                        Button {
                            if selection.contains(row.id) { selection.removeAll { $0 == row.id } }
                            else { selection.append(row.id) }
                        } label: {
                            HStack {
                                Text(row.name).foregroundStyle(.primary)
                                Spacer()
                                if selection.contains(row.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }.contentShape(Rectangle())
                        }.accessibilityIdentifier("trend-select.\(row.id)")
                            .accessibilityValue(selection.contains(row.id) ? "Selected" : "Not selected")
                    }
                } footer: {
                    Text("Start with a few categories for a clearer comparison. By category shows every category separately.")
                }
            }.navigationTitle("Compare categories").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Find a category")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("trend-select.done") } }
        }
    }
}
