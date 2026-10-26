import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ShoppingStore
    let onShare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("groupShoppingByCategory") private var groupBySection = true
    @AppStorage("showRecentPurchases") private var showRecentPurchases = true
    @AppStorage("showProductCompletions") private var showProductCompletions = true
    @State private var showingAppearance = false
    @State private var showingRename = false
    @State private var showingDecisions = false
    @State private var showingDiagnostics = false
    @State private var confirmingDelete = false
    @State private var listName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("הרשימה הזו") {
                    Button("שינוי שם הרשימה", systemImage: "pencil") {
                        listName = store.currentList.name
                        showingRename = true
                    }
                    Button("צבע וסמל הרשימה", systemImage: "paintpalette") { showingAppearance = true }
                    Button(store.currentShare == nil ? "שיתוף הרשימה…" : "ניהול השיתוף…", systemImage: "person.2") {
                        dismiss()
                        onShare()
                    }
                    #if targetEnvironment(simulator)
                    .disabled(true)
                    #endif
                }
                Section("בזמן הקנייה") {
                    Toggle("הצגת מקטעים", isOn: $groupBySection)
                    Toggle("הצגת נקנו לאחרונה", isOn: $showRecentPurchases)
                    Toggle("הצעות בזמן ההקלדה", isOn: $showProductCompletions)
                }
                Section {
                    Button("זיהוי מוצרים", systemImage: "sparkles") { showingDecisions = true }
                    Label(LocalizedStringKey(syncLabel), systemImage: "icloud")
                    Text("הסנכרון פועל אוטומטית כשיש חיבור. אפשר להמשיך לקנות גם בלעדיו.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("עובד ברקע") }
                Section("עזרה") {
                    Text("סימנת מוצר בטעות? אפשר לבטל דרך החץ בתפריט, בשקשוק האייפון או בקיצור ⌘Z. בזמן הקלדה הביטול חל על הטקסט.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("אבחון הצעות חכמות", systemImage: "chart.bar.doc.horizontal") { showingDiagnostics = true }
                    Button("ניסיון סנכרון נוסף", systemImage: "arrow.triangle.2.circlepath.icloud") {
                        #if !targetEnvironment(simulator)
                        Task { await store.cloudSync.synchronize() }
                        #endif
                    }
                }
                Section {
                    if store.canDeleteCurrentList {
                        Button("מחיקת הרשימה", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } else {
                        Text("כדי לצאת מרשימה שמשותפת איתך, פתחו את ניהול השיתוף.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("הגדרות")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } } }
            .sheet(isPresented: $showingAppearance) { ListAppearanceEditor(store: store) }
            .sheet(isPresented: $showingDecisions) { ProductDecisionSettings(store: store) }
            .sheet(isPresented: $showingDiagnostics) { PredictionDebugView(store: store) }
            .alert("שינוי שם הרשימה", isPresented: $showingRename) {
                TextField("שם החנות", text: $listName)
                Button("שמירה") { store.renameCurrentList(to: listName) }
                Button("ביטול", role: .cancel) {}
            }
            .confirmationDialog("למחוק את הרשימה ״\(store.currentList.name)״?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("מחיקת הרשימה", role: .destructive) {
                    store.deleteCurrentList()
                    dismiss()
                }
            } message: {
                Text(store.currentShare == nil
                     ? "הרשימה, הפריטים והיסטוריית הקניות שלה יימחקו מכל המכשירים שלך."
                     : "הרשימה, הפריטים והיסטוריית הקניות שלה יימחקו גם אצל מי ששותף בה.")
            }
        }
    }

    private var syncLabel: String {
        switch store.syncStatus {
        case .local: return "סנכרון iCloud"
        case .syncing: return "מסנכרן עם iCloud…"
        case .current: return "iCloud מעודכן"
        case .unavailable: return "iCloud אינו זמין — נסה שוב"
        case .accountChanged: return "חשבון iCloud השתנה — הנתונים נשמרו במכשיר"
        case .failed: return "הסנכרון ממתין לחיבור — נסה שוב"
        }
    }
}

