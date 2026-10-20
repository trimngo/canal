import SwiftUI
import Charts
import LedgerCore

struct HistoryPanel: View {
    @EnvironmentObject private var store: LedgerStore
    let report: HistoryReport
    let select: (BreakdownRow) -> Void
    @State private var page: Int? = 0
    @State private var selectedGroupID: String?
    private let pages = ["Breakdown", "Pie chart", "Daily trend", "Heatmap"]
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
                        CategoryHeatmapView(report: report, select: select).padding(.horizontal, 20)
                            .frame(width: geometry.size.width, height: geometry.size.height).id(3)
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
                ForEach(report.rows) { row in
                    Button { select(row) } label: {
                        VStack(spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.name).foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Text("\(row.percent, specifier: "%.1f")% · \(store.duration(row.minutes))").font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(1, row.percent / 100)).tint(color(row.id))
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("dashboard.group.\(row.id)")
                }
                Text("Percentages start at each day’s first log and end at now today, or midnight for completed days. Days without logs are excluded.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom, 8)
        }.accessibilityIdentifier("report.view.breakdown")
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
