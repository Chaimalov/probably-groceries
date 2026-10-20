import SwiftUI
import WatchKit

@main
struct GroceriesWatchApp: App {
    @StateObject private var store = WatchShoppingStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchShoppingView(store: store)
                .environment(\.layoutDirection, Bundle.main.preferredLocalizations.first == "en" ? .leftToRight : .rightToLeft)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refresh() }
                }
        }
    }
}

private struct WatchShoppingView: View {
    @ObservedObject var store: WatchShoppingStore
    @AppStorage("watchSelectedList") private var selectedID = ""
    @State private var choosingList = false
    @State private var showingOptions = false
    @State private var showPurchased = false
    @State private var tapLocked = false
    @State private var lastPurchase: WatchShoppingSnapshot.Row?
    @State private var lastListID: UUID?

    private var current: WatchShoppingSnapshot.List? {
        guard let snapshot = store.snapshot else { return nil }
        return snapshot.lists.first { $0.id.uuidString == selectedID }
            ?? snapshot.lists.first { $0.id == snapshot.selectedListID } ?? snapshot.lists.first
    }

    private var tint: Color {
        switch current?.tint {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "teal": return .teal
        case "mint": return .mint
        case "indigo": return .indigo
        default: return .green
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let list = current {
                    let remaining = list.rows.filter { !$0.purchased }.count
                    HStack {
                        Image(systemName: "cart").foregroundStyle(tint)
                        Text("נותרו \(remaining)").font(.headline).monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.clear)
                    if remaining == 0 {
                        Label("הכול בעגלה", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(tint)
                    }
                    ForEach(list.sections, id: \.self) { section in
                        let rows = list.rows.filter { $0.section == section && !$0.purchased }
                        if !rows.isEmpty {
                            Section(section) {
                                ForEach(rows) { row in purchaseButton(row, list: list) }
                            }
                        }
                    }
                    if let row = lastPurchase, lastListID == list.id {
                        Button {
                            mark(false, row: row, listID: list.id)
                            lastPurchase = nil
                        } label: {
                            Label("ביטול: \(row.name)", systemImage: "arrow.uturn.backward")
                                .font(.footnote)
                        }
                        .disabled(tapLocked)
                    }
                    if showPurchased {
                        Section("בעגלה") {
                            ForEach(list.rows.filter(\.purchased)) { row in
                                Button { mark(false, row: row, listID: list.id) } label: {
                                    Label(row.name, systemImage: "checkmark.circle.fill")
                                }
                                .disabled(tapLocked)
                                .accessibilityHint(Text("החזרה לרשימת הקניות"))
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("הרשימה בדרך", systemImage: "iphone.and.arrow.forward",
                        description: Text("פתחו את קניות באייפון כדי להעביר את הרשימות לשעון."))
                }
                if store.pendingCount > 0 {
                    Label("\(store.pendingCount) שינויים ממתינים לסנכרון", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !store.reachable, let date = store.snapshot?.date {
                    VStack(alignment: .leading) {
                        Text("עודכן לאחרונה")
                        Text(date, style: .relative)
                    }.font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(current?.name ?? String(localized: "קניות"))
            .tint(tint)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { choosingList = true } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel(Text("בחירת רשימה"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingOptions = true } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel(Text("אפשרויות"))
                }
            }
            .confirmationDialog("אפשרויות", isPresented: $showingOptions) {
                Button(LocalizedStringKey(showPurchased ? "הסתרת מוצרים בעגלה" : "הצגת מוצרים בעגלה")) {
                    showPurchased.toggle()
                }
                Button("רענון") { store.refresh() }
            }
            .sheet(isPresented: $choosingList) {
                NavigationStack {
                    List(store.snapshot?.lists ?? []) { list in
                        Button {
                            selectedID = list.id.uuidString
                            lastPurchase = nil
                            choosingList = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(list.name).font(.headline)
                                Text("נותרו \(list.rows.filter { !$0.purchased }.count)").font(.caption)
                            }
                        }
                    }.navigationTitle("רשימות")
                }
            }
        }
    }

    private func purchaseButton(_ row: WatchShoppingSnapshot.Row, list: WatchShoppingSnapshot.List) -> some View {
        Button {
            mark(true, row: row, listID: list.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "circle").font(.title3).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text("\(row.quantity) \(row.unit.map(ShoppingUnit.shortLabel) ?? "")")
                        .font(.callout).foregroundStyle(.secondary)
                    if let note = row.note, !note.isEmpty {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .disabled(tapLocked)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("סימון כמוצר שנוסף לעגלה"))
    }

    private func mark(_ purchased: Bool, row: WatchShoppingSnapshot.Row, listID: UUID) {
        guard !tapLocked, store.setPurchased(purchased, row: row, listID: listID) else { return }
        WKInterfaceDevice.current().play(purchased ? .success : .click)
        if purchased { lastPurchase = row; lastListID = listID }
        // A rapid second tap must not buy the row that just moved under the finger.
        tapLocked = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            tapLocked = false
        }
    }
}
