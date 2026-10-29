import SwiftUI
import Charts
import LedgerCore

struct HistoryPanel: View {
    @EnvironmentObject private var store: LedgerStore
    let report: HistoryReport
    var forecast: CalendarDayForecast? = nil
    var hideZeroTime = true
    let selectDirect: (BreakdownRow) -> Void
    let select: (BreakdownRow) -> Void
    @State private var page: Int? = 0
    @State private var selectedGroupID: String?
    @State private var expandedCategories = Set<String>()
    @State private var breakdownHeight: CGFloat = 150
    @State private var showingHelp = false
    private struct PlanRequest: Identifiable {
        let id = UUID()
        let categoryID: String?
        let directOnly: Bool
    }
    @State private var planRequest: PlanRequest?
    private let pages = ["Breakdown", "Pie chart", "Daily trend", "Heatmap", "Day comparison"]
    private var displayed: HistoryReport { forecast?.preview(of: report, in: store.ledger) ?? report }
    private var selectedRow: BreakdownRow? { displayed.rows.first { $0.id == selectedGroupID } }
    private var hasPlan: Bool { (forecast?.minutes ?? 0) > 0 }
    private var previewMinutes: Double { max(Double.leastNormalMagnitude, displayed.trackedMinutes) }
    private struct PieSlice: Identifiable {
        let row: BreakdownRow
        let minutes: Double
        let planned: Bool
        var id: String { row.id + (planned ? ":planned" : ":recorded") }
    }
    private var pieSlices: [PieSlice] {
        displayed.rows.flatMap { row -> [PieSlice] in
            let planned = forecast?.minutes(for: row.id, in: store.ledger) ?? 0
            var slices: [PieSlice] = []
            if row.minutes > planned { slices.append(PieSlice(row: row, minutes: row.minutes - planned, planned: false)) }
            if planned > 0 { slices.append(PieSlice(row: row, minutes: planned, planned: true)) }
            return slices
        }
    }
    private func color(_ id: String) -> Color {
        if id == "uncategorized" { return .orange }
        let colors: [Color] = [.teal, .blue, .purple, .pink, .indigo, .mint, .brown]
        return colors[id.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }]
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(hasPlan && (page ?? 0) < 2 ? "Recorded and planned time" : "Where your time went").font(.headline).accessibilityIdentifier("dashboard.breakdown-title")
                Button { showingHelp = true } label: { Image(systemName: "info.circle").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("About time estimates").accessibilityIdentifier("dashboard.help")
                    .popover(isPresented: $showingHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About time estimates").font(.headline)
                            Text("Percentages use the estimated period from half a notification interval before the first log to half an interval after the last. Random mode uses your configured average interval. Estimates stop at now and calendar-day boundaries. Days without logs are excluded.")
                            Text("Parent totals include their subcategories. Percentages use the same total throughout.")
                            if hasPlan {
                                Text("Pale portions are planned calendar time; stripes also mark them in the breakdown. The preview combines recorded time with the remaining timed events today. Overlaps share their time, and unscheduled time is not invented. Plans do not count toward history or goals until an ended event is confirmed. Trends, heatmap and day comparison still use recorded time.")
                            }
                        }.font(.subheadline).padding(20).frame(idealWidth: 300, maxWidth: 340)
                            .accessibilityIdentifier("dashboard.help-content").presentationCompactAdaptation(.popover)
                    }
                Spacer()
                Text("\((page ?? 0) + 1) / \(pages.count)").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20)
            if hasPlan && (page ?? 0) < 2 { calendarPlanSummary.padding(.horizontal, 20) }
            // A paging ScrollView avoids nesting UIPageViewController inside
            // the app's TabView, which can draw over the other tabs on iOS.
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        breakdown.padding(.horizontal, 20)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(0)
                        Group {
                            if page == 1 { pie(diameter: max(160, min(360, geometry.size.width - 40, geometry.size.height * 0.6))) }
                            else { Color.clear.accessibilityHidden(true) }
                        }.padding(.horizontal, 20)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(1)
                        Group {
                            if page == 2 { CategoryTrendView(report: report, isVisible: true, chartHeight: max(220, min(360, geometry.size.height * 0.45))) }
                            else { Color.clear.accessibilityHidden(true) }
                        }.padding(.horizontal, 20)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(2)
                        CategoryHeatmapView(report: report) { item in
                            if item.direct { selectDirect(item.row) }
                            else { select(item.row) }
                        }.padding(.horizontal, 20)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(3)
                        DailyComparisonView().padding(.horizontal, 16)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(4)
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.paging).scrollPosition(id: $page).scrollIndicators(.hidden)
                    .accessibilityIdentifier("report.pages")
            }.frame(height: (page ?? 0) == 0 ? breakdownHeight : 460)
            HStack {
                Text(pages[page ?? 0]).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button { withAnimation { page = index } } label: {
                            Circle().fill(index == (page ?? 0) ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Show \(pages[index].lowercased())")
                            .accessibilityAddTraits(index == (page ?? 0) ? .isSelected : [])
                    }
                }
            }.padding(.horizontal, 20)
        }.frame(maxWidth: .infinity)
        .onPreferenceChange(BreakdownHeightKey.self) { breakdownHeight = max(150, $0) }
        .onChange(of: report.start) { _, _ in clearSelection() }
        .onChange(of: report.end) { _, _ in
            if !displayed.rows.contains(where: { $0.id == selectedGroupID }) { clearSelection() }
        }
        .sheet(item: $planRequest) { request in
            if let forecast { CalendarForecastListView(forecast: forecast, categoryID: request.categoryID, directOnly: request.directOnly) }
        }
    }
    private var calendarPlanSummary: some View {
        Button {
            planRequest = PlanRequest(categoryID: nil, directOnly: false)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Label("Recorded", systemImage: "circle.fill")
                    Label("Planned", systemImage: "circle.dashed")
                }.font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("\(store.duration(forecast?.minutes ?? 0)) planned · \((forecast?.minutes ?? 0) / previewMinutes * 100, specifier: "%.0f")% of preview")
                    Spacer()
                    Image(systemName: "chevron.right")
                }.font(.subheadline)
                Text("Tentative calendar time · confirm after events end").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("dashboard.calendar-plan")
    }
    private var breakdown: some View {
            VStack(spacing: 14) {
                if displayed.rows.isEmpty { empty }
                ForEach(displayed.categoryOutline(in: store.ledger, expanded: expandedCategories, hideZeroTime: hideZeroTime)) { item in
                    breakdownRow(item)
                }
            }.padding(.bottom, 8).fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: BreakdownHeightKey.self, value: geometry.size.height)
                    }
                }.accessibilityIdentifier("report.view.breakdown")
    }
    private func breakdownRow(_ item: HistoryCategoryRow) -> some View {
        HStack(spacing: 4) {
            if item.hasChildren {
                Button {
                    if expandedCategories.contains(item.row.id) { expandedCategories.remove(item.row.id) }
                    else { expandedCategories.insert(item.row.id) }
                } label: {
                    Image(systemName: expandedCategories.contains(item.row.id) ? "chevron.down" : "chevron.right")
                        .font(.caption).frame(width: 28, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(expandedCategories.contains(item.row.id) ? "Collapse" : "Expand") \(item.row.name)")
                    .accessibilityValue(expandedCategories.contains(item.row.id) ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("dashboard.children.\(item.row.id)")
            } else { Color.clear.frame(width: 28, height: 1).accessibilityHidden(true) }
            if item.direct {
                Button { openBreakdown(item) } label: { breakdownValue(item) }
                    .buttonStyle(.plain).accessibilityIdentifier("dashboard.direct.\(item.row.id)")
            } else {
                Button { openBreakdown(item) } label: { breakdownValue(item) }
                    .buttonStyle(.plain).accessibilityIdentifier("dashboard.group.\(item.row.id)")
            }
        }.padding(.leading, CGFloat(item.depth) * 16)
            .accessibilityElement(children: .contain)
    }
    private func breakdownValue(_ item: HistoryCategoryRow) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.row.name).fontWeight(item.hasChildren ? .semibold : .regular)
                    .foregroundStyle(item.direct ? Color.secondary : Color.primary)
                Spacer(minLength: 4)
                Text("\(item.row.percent, specifier: "%.1f")% · \(store.duration(item.row.minutes))").font(.subheadline).foregroundStyle(.secondary)
                if !item.direct { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
            }
            if let planned = forecast?.minutes(for: item.row.id, in: store.ledger, direct: item.direct), planned > 0 {
                let recorded = max(0, item.row.minutes - planned)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle().fill(color(item.row.id)).frame(width: geometry.size.width * CGFloat(recorded / previewMinutes))
                        Rectangle().fill(color(item.row.id).opacity(0.25)).overlay { CalendarPlanHatching(color: color(item.row.id)) }
                            .frame(width: geometry.size.width * CGFloat(planned / previewMinutes))
                        Spacer(minLength: 0)
                    }.background(Color.secondary.opacity(0.12)).clipShape(Capsule())
                }.frame(height: 6).accessibilityHidden(true)
                Text("\(store.duration(recorded)) recorded · \(store.duration(planned)) planned")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dashboard.plan-share.\(item.id)")
            } else {
                ProgressView(value: min(1, item.row.percent / 100)).tint(color(item.row.id))
            }
            let pending = report.unreviewed(for: item.row.id, in: store.ledger, direct: item.direct)
            if pending > 0 { Text("Includes \(store.duration(pending)) awaiting category review").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
    private func openBreakdown(_ item: HistoryCategoryRow) {
        let planned = forecast?.minutes(for: item.row.id, in: store.ledger, direct: item.direct) ?? 0
        if planned > 0 && item.row.minutes - planned < 0.001 {
            planRequest = PlanRequest(categoryID: item.row.id, directOnly: item.direct)
        } else if item.direct { selectDirect(item.row) }
        else { select(item.row) }
    }
    private func pie(diameter: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if displayed.rows.isEmpty { empty }
                else {
                    ZStack {
                        Chart(pieSlices) { slice in
                            SectorMark(angle: .value("Time", slice.minutes), innerRadius: .ratio(0.58), angularInset: 2)
                                .foregroundStyle(color(slice.row.id).opacity(slice.planned ? 0.3 : 1))
                                .opacity(selectedGroupID == nil || selectedGroupID == slice.row.id ? 1 : 0.4)
                                .accessibilityLabel(slice.row.name + (slice.planned ? ", planned" : ", recorded"))
                                .accessibilityValue("\(Int((slice.minutes / previewMinutes * 100).rounded())) percent, \(store.duration(slice.minutes))")
                        }.chartOverlay { proxy in
                            GeometryReader { geometry in
                                if let anchor = proxy.plotFrame {
                                    let frame = geometry[anchor]
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(SpatialTapGesture().onEnded { value in selectSlice(at: value.location, in: frame) })
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        // Recreate sector geometry when categories merge or
                        // disappear. Reusing the old Charts plot can trap while
                        // interpolating a removed sector on iOS 18.
                        .id(pieSlices.map(\.id))
                        .transaction { $0.animation = nil }
                        .accessibilityIdentifier("report.pie.chart")
                        // Keep the label outside Chart's generated accessibility
                        // tree so VoiceOver can read the selected group as well.
                        VStack(spacing: 3) {
                            if let row = selectedRow {
                                Text(row.name).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                                Text("\(row.percent, specifier: "%.1f")%").font(.caption)
                                Text(store.duration(row.minutes)).font(.caption2).foregroundStyle(.secondary)
                                if let planned = forecast?.minutes(for: row.id, in: store.ledger), planned > 0 {
                                    Text("\(store.duration(planned)) planned").font(.caption2).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Tap a slice").font(.caption).foregroundStyle(.secondary)
                            }
                        }.multilineTextAlignment(.center).frame(width: diameter * 0.44, height: diameter * 0.44)
                            .accessibilityElement(children: .combine).accessibilityIdentifier("report.pie.selection")
                            .allowsHitTesting(false)
                    }.frame(width: diameter, height: diameter).frame(maxWidth: .infinity)
                    if let row = selectedRow {
                        let pending = report.unreviewed(for: row.id, in: store.ledger)
                        if pending > 0 { Text("Includes \(store.duration(pending)) awaiting category review").font(.caption2).foregroundStyle(.secondary) }
                    }
                    ForEach(displayed.rows) { row in
                        Button { selectedGroupID = row.id } label: {
                            HStack {
                                Circle().fill(color(row.id)).frame(width: 8, height: 8)
                                Text(row.name).foregroundStyle(.primary); Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))").foregroundStyle(.secondary)
                                    if let planned = forecast?.minutes(for: row.id, in: store.ledger), planned > 0 {
                                        Text("\(store.duration(planned)) planned").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("report.pie.group.\(row.id)")
                            .accessibilityAddTraits(selectedGroupID == row.id ? .isSelected : [])
                    }
                }
            }.padding(.bottom, 8)
        }.accessibilityIdentifier("report.view.pie")
    }
    private var empty: some View {
        Text("Log an activity to start this view.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 150)
    }
    private func clearSelection() { selectedGroupID = nil }
    private func selectSlice(at point: CGPoint, in frame: CGRect) {
        let dx = Double(point.x - frame.midX), dy = Double(point.y - frame.midY)
        let radius = Double(min(frame.width, frame.height)) / 2
        let distance = hypot(dx, dy)
        guard distance >= radius * 0.58, distance <= radius else { return }
        var angle = atan2(dx, -dy) // Clockwise from twelve, matching SectorMark.
        if angle < 0 { angle += 2 * Double.pi }
        let value = angle / (2 * Double.pi) * pieSlices.reduce(0) { $0 + $1.minutes }
        var total = 0.0
        selectedGroupID = pieSlices.first { slice in
            total += slice.minutes
            return value < total
        }?.row.id
    }
}

private struct BreakdownHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 150
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
