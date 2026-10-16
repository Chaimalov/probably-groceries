import SwiftUI
import AppIntents
import WidgetKit

struct GroceryWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "רשימת קניות"
    static var description = IntentDescription("בחירת הרשימה שתוצג")

    @Parameter(title: "רשימה", optionsProvider: GroceryListOptions())
    var listID: String?

    init() {}
}

struct GroceryListOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        GroceryWidgetBridge.readAll().map { $0.listID.uuidString }
    }
}

struct GroceryEntry: TimelineEntry {
    let date: Date
    let snapshot: GroceryWidgetSnapshot?
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
        Timeline(entries: [GroceryEntry(date: .now, snapshot: selected(configuration))],
                 policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func selected(_ configuration: GroceryWidgetConfiguration) -> GroceryWidgetSnapshot? {
        let all = GroceryWidgetBridge.readAll()
        if let id = configuration.listID,
           let snapshot = all.first(where: { $0.listID.uuidString == id }) { return snapshot }
        return GroceryWidgetBridge.read() ?? all.first
    }
}

struct GroceryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GroceryEntry

    private var tint: Color {
        switch entry.snapshot?.tintName {
        case "blue": .blue
        case "orange": .orange
        case "red": .red
        case "purple": .purple
        case "yellow": .yellow
        case "pink": .pink
        default: .green
        }
    }

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "basket")
                    .foregroundStyle(tint)
                Text(snapshot?.title ?? "קניות")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if family == .systemMedium {
                    Text("\(snapshot?.total ?? 0)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if family == .systemSmall {
                Spacer(minLength: 0)
                Text("\(snapshot?.total ?? 0)")
                    .font(.system(size: 43, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("פריטים לקנות")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let snapshot, !snapshot.rows.isEmpty {
                ForEach(snapshot.rows.prefix(4)) { row in
                    Button(intent: BuyGroceryIntent(itemID: row.id.uuidString)) {
                        HStack(spacing: 9) {
                            Image(systemName: "circle")
                                .foregroundStyle(tint.opacity(0.8))
                            Text(row.name).lineLimit(1)
                            Spacer(minLength: 0)
                            if row.quantity > 1 {
                                Text("×\(row.quantity)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text(snapshot == nil ? "פתחו את האפליקציה כדי להתחיל" : "הכול נקנה!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if family == .systemMedium {
                HStack {
                    Spacer()
                    Link(destination: URL(string: "probablygroceries://add/\(snapshot?.listID.uuidString ?? "")")!) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(tint)
                    }
                    .accessibilityLabel("הוספת מוצר")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "probablygroceries://open"))
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
        .description("הרשימה שלך במבט מהיר")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
