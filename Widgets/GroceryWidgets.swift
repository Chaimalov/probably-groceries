import SwiftUI
import AppIntents
import WidgetKit

struct GroceryListEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "רשימת קניות"
    static var defaultQuery = GroceryListQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct GroceryListQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GroceryListEntity] {
        GroceryWidgetBridge.readAll()
            .filter { identifiers.contains($0.listID.uuidString) }
            .map { GroceryListEntity(id: $0.listID.uuidString, name: $0.title) }
    }

    func suggestedEntities() async throws -> [GroceryListEntity] {
        GroceryWidgetBridge.readAll()
            .map { GroceryListEntity(id: $0.listID.uuidString, name: $0.title) }
    }
}

struct GroceryWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "רשימת קניות"
    static var description = IntentDescription("בחירת הרשימה שתוצג")

    @Parameter(title: "רשימה")
    var list: GroceryListEntity?

    init() {}
}

struct GroceryEntry: TimelineEntry {
    let date: Date
    let snapshot: GroceryWidgetSnapshot?
    var offset: Int = 0
}

struct GroceryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GroceryEntry {
        GroceryEntry(date: .now, snapshot: GroceryWidgetSnapshot(
            listID: UUID(), title: "קניות", tintName: "green", total: 4,
            rows: [GroceryWidgetSnapshot.Row(id: UUID(), name: "חלב", quantity: 1),
                   GroceryWidgetSnapshot.Row(id: UUID(), name: "עגבניות", quantity: 2)]))
    }
    func snapshot(for configuration: GroceryWidgetConfiguration, in context: Context) async -> GroceryEntry {
        GroceryEntry(date: .now, snapshot: selected(configuration))
    }

    func timeline(for configuration: GroceryWidgetConfiguration, in context: Context) async -> Timeline<GroceryEntry> {
        let snapshot = selected(configuration)
        let key = "widgetPage.\(snapshot?.listID.uuidString ?? "").\(context.family.rawValue)"
        let offset = UserDefaults(suiteName: GroceryWidgetBridge.suite)?.integer(forKey: key) ?? 0
        return Timeline(entries: [GroceryEntry(date: .now, snapshot: snapshot, offset: offset)],
                        policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func selected(_ configuration: GroceryWidgetConfiguration) -> GroceryWidgetSnapshot? {
        let all = GroceryWidgetBridge.readAll()
        if let id = configuration.list?.id {
            return all.first(where: { $0.listID.uuidString == id })
        }
        return GroceryWidgetBridge.read() ?? all.first
    }
}

struct GroceryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44
    let entry: GroceryEntry

    private var tint: Color {
        switch entry.snapshot?.tintName {
        case "mint": .mint
        case "teal": .teal
        case "indigo": .indigo
        case "blue": .blue
        case "orange": .orange
        case "red": .red
        case "purple": .purple
        case "pink": .pink
        default: .green
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = family == .systemExtraLarge ? 2 : 1
            let height = family == .systemMedium ? max(32, rowHeight - 8) : rowHeight
            let rowsPerColumn = max(1, Int((geometry.size.height - 60) / height))
            let capacity = rowsPerColumn * columns
            let snapshot = entry.snapshot
            let page = WidgetPage(count: snapshot?.rows.count ?? 0,
                                  offset: entry.offset, capacity: capacity)
            VStack(alignment: .leading, spacing: 6) {
                header
                if family == .systemSmall {
                    Spacer(minLength: 0)
                    Text("\(snapshot?.total ?? 0)")
                        .font(.system(size: 43, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(snapshot == nil ? "פתחו את האפליקציה" : "פריטים לקנות")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let snapshot, !snapshot.rows.isEmpty {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(0..<columns, id: \.self) { column in
                            VStack(spacing: 0) {
                                ForEach(0..<rowsPerColumn, id: \.self) { row in
                                    let index = page.range.lowerBound + column * rowsPerColumn + row
                                    if index < page.range.upperBound {
                                        itemRow(snapshot.rows[index], listID: snapshot.listID)
                                            .frame(height: height)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Label(snapshot == nil ? "פתחו את האפליקציה כדי לבחור רשימה" : "הכול נקנה!",
                          systemImage: snapshot == nil ? "basket" : "checkmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                if family != .systemSmall, let snapshot {
                    footer(snapshot, page: page, capacity: capacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(.background, for: .widget)
        .widgetURL(entry.snapshot.map { listURL($0.listID) })
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "basket").foregroundStyle(tint).widgetAccentable()
            Text(entry.snapshot?.title ?? "קניות").font(.headline).lineLimit(1)
            Spacer(minLength: 0)
            if family != .systemSmall {
                Text("\(entry.snapshot?.total ?? 0)")
                    .foregroundStyle(tint).font(.headline).monospacedDigit()
            }
        }
    }

    private func itemRow(_ row: GroceryWidgetSnapshot.Row, listID: UUID) -> some View {
        HStack(spacing: 2) {
            Button(intent: BuyGroceryIntent(itemID: row.id.uuidString, listID: listID.uuidString)) {
                Image(systemName: "circle")
                    .font(.title3).foregroundStyle(tint)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("סימון \(row.name) כנקנה")
            Link(destination: URL(string: "probablygroceries://edit/\(row.id.uuidString)")!) {
                HStack(spacing: 5) {
                    Text(row.name).font(.body).lineLimit(1)
                    Spacer(minLength: 2)
                    if row.quantity > 1 || row.unit != nil {
                        Text([String(row.quantity), row.unit].compactMap { $0 }.joined(separator: " "))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("עריכת \(row.name)")
        }
    }

    private func footer(_ snapshot: GroceryWidgetSnapshot, page: WidgetPage, capacity: Int) -> some View {
        HStack(spacing: 8) {
            if snapshot.rows.count > capacity {
                Button(intent: WidgetPageIntent(listID: snapshot.listID.uuidString,
                    family: String(family.rawValue), offset: page.previous)) {
                    Image(systemName: "chevron.backward").frame(width: 32, height: 28)
                }
                .disabled(page.range.lowerBound == 0)
                .accessibilityLabel("מוצרים קודמים")
                Text("\(page.range.lowerBound + 1)–\(page.range.upperBound)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button(intent: WidgetPageIntent(listID: snapshot.listID.uuidString,
                    family: String(family.rawValue), offset: page.next)) {
                    Image(systemName: "chevron.forward").frame(width: 32, height: 28)
                }
                .accessibilityLabel("מוצרים נוספים")
            }
            Spacer(minLength: 0)
            Link(destination: URL(string: "probablygroceries://add/\(snapshot.listID.uuidString)")!) {
                Label("מוצר", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                    .frame(minHeight: 28)
            }
            .accessibilityLabel("הוספת מוצר לרשימה")
        }
        .buttonStyle(.plain)
    }

    private func listURL(_ id: UUID) -> URL {
        URL(string: "probablygroceries://list/\(id.uuidString)")!
    }
}

@main
struct GroceryWidgets: Widget {
    let kind = "GroceryWidgets"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: GroceryWidgetConfiguration.self, provider: GroceryProvider()) { entry in
            GroceryWidgetView(entry: entry)
        }
        .configurationDisplayName("רשימת קניות")
        .description("סימון קניות, מעבר בין מוצרים וגישה מהירה לעריכה")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
