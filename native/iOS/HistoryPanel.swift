import SwiftUI
import Charts
import LedgerCore

struct HistoryPanel: View {
    @EnvironmentObject private var store: LedgerStore
    let report: HistoryReport
    let select: (BreakdownRow) -> Void
    @State private var page = 0
    private func color(_ id: String) -> Color {
        if id == "remaining" { return .gray }
        if id == "uncategorized" { return .orange }
        let colors: [Color] = [.teal, .blue, .purple, .pink, .indigo, .mint, .brown]
        return colors[id.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }]
    }
    private var ids: [String] { report.rows.filter { $0.id != "remaining" }.map(\.id) }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(["Breakdown", "Pie chart", "Daily trend"][page]).font(.subheadline.bold())
                Spacer()
                Text("\(page + 1) / 3").font(.caption).foregroundStyle(.secondary)
            }
            TabView(selection: $page) {
                breakdown.tag(0)
                pie.tag(1)
                trend.tag(2)
            }.tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 270).accessibilityIdentifier("report.pages")
        }
    }
    private var breakdown: some View {
        ScrollView {
            VStack(spacing: 14) {
                if report.rows.isEmpty { empty }
                ForEach(report.rows) { row in
                    Button { select(row) } label: {
                        VStack(spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.name).foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))").font(.subheadline).foregroundStyle(.secondary)
                                if row.id != "remaining" { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            }
                            ProgressView(value: min(1, row.percent / 100)).tint(color(row.id))
                        }
                    }.buttonStyle(.plain).disabled(row.id == "remaining").accessibilityIdentifier("dashboard.group.\(row.id)")
                }
            }.padding(.bottom, 30)
        }.accessibilityIdentifier("report.view.breakdown")
    }
    private var pie: some View {
        ScrollView {
            VStack(spacing: 12) {
                if report.rows.isEmpty { empty }
                else {
                    Chart(report.rows) { row in
                        SectorMark(angle: .value("Time", row.minutes), innerRadius: .ratio(0.58), angularInset: 2)
                            .foregroundStyle(color(row.id))
                            .accessibilityLabel(row.name)
                            .accessibilityValue("\(Int(row.percent.rounded())) percent, \(store.duration(row.minutes))")
                    }.frame(height: 165)
                    ForEach(report.rows) { row in
                        HStack {
                            Circle().fill(color(row.id)).frame(width: 8, height: 8)
                            Text(row.name); Spacer()
                            Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))").foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                }
            }.padding(.bottom, 30)
        }.accessibilityIdentifier("report.view.pie")
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tracked hours by day").font(.caption).foregroundStyle(.secondary)
            if report.dailyTotals.isEmpty { empty }
            else {
                Chart(report.dailyTotals) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Hours", item.minutes / 60))
                        .foregroundStyle(by: .value("Group", item.categoryID))
                        .accessibilityLabel("\(item.day.formatted(date: .abbreviated, time: .omitted)), \(item.name)")
                        .accessibilityValue(store.duration(item.minutes))
                }.chartForegroundStyleScale(domain: ids, range: ids.map(color))
                    .chartLegend(.hidden).chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            }
        }.padding(.bottom, 30).accessibilityIdentifier("report.view.trend")
    }
    private var empty: some View {
        Text("Log an activity to start this view.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 150)
    }
}
