import SwiftUI
import Charts
import LedgerCore

struct HistoryPanel: View {
    @EnvironmentObject private var store: LedgerStore
    let report: HistoryReport
    var hideZeroTime = true
    let selectDirect: (BreakdownRow) -> Void
    let select: (BreakdownRow) -> Void
    @State private var page: Int? = 0
    @State private var selectedGroupID: String?
    @State private var expandedCategories = Set<String>()
    private let pages = ["Breakdown", "Pie chart", "Daily trend", "Heatmap", "Day comparison"]
    private var selectedRow: BreakdownRow? { report.rows.first { $0.id == selectedGroupID } }
    private func color(_ id: String) -> Color {
        if id == "uncategorized" { return .orange }
        let colors: [Color] = [.teal, .blue, .purple, .pink, .indigo, .mint, .brown]
        return colors[id.utf8.reduce(0) { ($0 * 31 + Int($1)) % colors.count }]
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Where your time went").font(.headline).accessibilityIdentifier("dashboard.breakdown-title")
                Spacer()
                Text("\((page ?? 0) + 1) / \(pages.count)").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20)
            // A paging ScrollView avoids nesting UIPageViewController inside
            // the app's TabView, which can draw over the other tabs on iOS.
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        breakdown.padding(.horizontal, 20)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(0)
                        pie(diameter: max(160, min(360, geometry.size.width - 40, geometry.size.height * 0.6)))
                            .padding(.horizontal, 20)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(1)
                        CategoryTrendView(report: report, isVisible: page == 2, chartHeight: max(220, min(360, geometry.size.height * 0.45)))
                            .padding(.horizontal, 20)
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
            }
            HStack {
                Text(pages[page ?? 0]).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        Button { withAnimation { page = index } } label: {
                            Circle().fill(index == (page ?? 0) ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Show \(pages[index].lowercased())")
                            .accessibilityAddTraits(index == (page ?? 0) ? .isSelected : [])
                    }
                }
            }.padding(.horizontal, 20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: report.start) { _, _ in clearSelection() }
        .onChange(of: report.end) { _, _ in
            if !report.rows.contains(where: { $0.id == selectedGroupID }) { clearSelection() }
        }
    }
    private var breakdown: some View {
        ScrollView {
            VStack(spacing: 14) {
                if report.rows.isEmpty { empty }
                ForEach(report.categoryOutline(in: store.ledger, expanded: expandedCategories, hideZeroTime: hideZeroTime)) { item in
                    breakdownRow(item)
                }
                if report.rows.contains(where: { !store.ledger.children(of: $0.id).isEmpty }) {
                    Text("Parent totals include their subcategories. Percentages use the same total throughout.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Percentages use the estimated period from half a notification interval before the first log to half an interval after the last. Random mode uses your configured average interval. Estimates stop at now and calendar-day boundaries. Days without logs are excluded.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom, 8)
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
                Button { selectDirect(item.row) } label: { breakdownValue(item) }
                    .buttonStyle(.plain).accessibilityIdentifier("dashboard.direct.\(item.row.id)")
            } else {
                Button { select(item.row) } label: { breakdownValue(item) }
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
            ProgressView(value: min(1, item.row.percent / 100)).tint(color(item.row.id))
            let pending = report.unreviewed(for: item.row.id, in: store.ledger, direct: item.direct)
            if pending > 0 { Text("Includes \(store.duration(pending)) awaiting category review").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
    private func pie(diameter: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if report.rows.isEmpty { empty }
                else {
                    ZStack {
                        Chart(report.rows) { row in
                            SectorMark(angle: .value("Time", row.minutes), innerRadius: .ratio(0.58), angularInset: 2)
                                .foregroundStyle(color(row.id))
                                .opacity(selectedGroupID == nil || selectedGroupID == row.id ? 1 : 0.4)
                                .accessibilityLabel(row.name)
                                .accessibilityValue("\(Int(row.percent.rounded())) percent, \(store.duration(row.minutes))")
                        }.chartOverlay { proxy in
                            GeometryReader { geometry in
                                if let anchor = proxy.plotFrame {
                                    let frame = geometry[anchor]
                                    Rectangle().fill(.clear).contentShape(Rectangle())
                                        .gesture(SpatialTapGesture().onEnded { value in selectSlice(at: value.location, in: frame) })
                                        .accessibilityHidden(true)
                                }
                            }
                        }.accessibilityIdentifier("report.pie.chart")
                        // Keep the label outside Chart's generated accessibility
                        // tree so VoiceOver can read the selected group as well.
                        VStack(spacing: 3) {
                            if let row = selectedRow {
                                Text(row.name).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                                Text("\(row.percent, specifier: "%.1f")%").font(.caption)
                                Text(store.duration(row.minutes)).font(.caption2).foregroundStyle(.secondary)
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
                    ForEach(report.rows) { row in
                        Button { selectedGroupID = row.id } label: {
                            HStack {
                                Circle().fill(color(row.id)).frame(width: 8, height: 8)
                                Text(row.name).foregroundStyle(.primary); Spacer()
                                Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))").foregroundStyle(.secondary)
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
        let value = angle / (2 * Double.pi) * report.rows.reduce(0) { $0 + $1.minutes }
        var total = 0.0
        selectedGroupID = report.rows.first { row in
            total += row.minutes
            return value < total
        }?.id
    }
}
