import SwiftUI
import WidgetKit

struct GroceryEntry: TimelineEntry {
    let date: Date
    let snapshot: GroceryWidgetSnapshot?
}

struct GroceryProvider: TimelineProvider {
    func placeholder(in context: Context) -> GroceryEntry {
        GroceryEntry(date: .now, snapshot: GroceryWidgetSnapshot(
            listID: UUID(), title: "קניות", tintName: "green", total: 4,
            rows: [GroceryWidgetSnapshot.Row(id: UUID(), name: "חלב", quantity: 1),
                   GroceryWidgetSnapshot.Row(id: UUID(), name: "עגבניות", quantity: 2)]))
    }
    func getSnapshot(in context: Context, completion: @escaping (GroceryEntry) -> Void) {
        completion(GroceryEntry(date: .now, snapshot: GroceryWidgetBridge.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GroceryEntry>) -> Void) {
        let entry = GroceryEntry(date: .now, snapshot: GroceryWidgetBridge.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
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
                    Link(destination: URL(string: "probablygroceries://list/\(snapshot.listID.uuidString)/item/\(row.id.uuidString)")!) {
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
                    .tint(.primary)
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
                    Link(destination: URL(string: "probablygroceries://add")!) {
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
        StaticConfiguration(kind: kind, provider: GroceryProvider()) { entry in
            GroceryWidgetView(entry: entry)
        }
        .configurationDisplayName("רשימת קניות")
        .description("הרשימה שלך במבט מהיר")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
