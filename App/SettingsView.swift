import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var store: ShoppingStore
    let onShare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("groupShoppingByCategory") private var groupBySection = true
    @AppStorage("showRecentPurchases") private var showRecentPurchases = true
    @AppStorage("showProductCompletions") private var showProductCompletions = true
    @AppStorage("shoppingHapticsEnabled") private var hapticsEnabled = true
    @AppStorage("clarificationNotificationsEnabled") private var clarificationAlerts = true
    @State private var alertsAllowed = true
    @State private var showingAppearance = false
    @State private var showingRename = false
    @State private var showingDecisions = false
    @State private var showingDiagnostics = false
    @State private var confirmingDelete = false
    @State private var deletingListID: UUID?
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
                    NavigationLink("ניהול מקטעים") { SectionSettingsView(store: store) }
                    Button(store.currentShare == nil ? "שיתוף הרשימה…" : "ניהול השיתוף…", systemImage: "person.2") {
                        dismiss()
                        onShare()
                    }
                    #if targetEnvironment(simulator)
                    .disabled(true)
                    #endif
                }
                Section("בזמן הקנייה") {
                    NavigationLink("תג האפליקציה") { BadgeSettingsView(store: store) }
                    Toggle("הצגת מקטעים", isOn: $groupBySection)
                        .tint(.green)
                    Toggle("הצגת נקנו לאחרונה", isOn: $showRecentPurchases)
                        .tint(.green)
                    Toggle("הצעות בזמן ההקלדה", isOn: $showProductCompletions)
                        .tint(.green)
                    Toggle("משוב רטט בסימון", isOn: $hapticsEnabled)
                        .tint(.green)
                }
                Section("עדכונים מהשותף") {
                    Toggle("התראות על בירור מוצרים", isOn: $clarificationAlerts)
                        .tint(.green)
                    if clarificationAlerts && !alertsAllowed {
                        Text("כדי לקבל התראה על שאלה או תשובה, אפשר לאפשר התראות בהגדרות האייפון.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("פתיחת הגדרות האייפון") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
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
                        Button("מחיקת הרשימה", systemImage: "trash", role: .destructive) { deletingListID = store.selectedListID; confirmingDelete = true }
                    } else {
                        Text("כדי לצאת מרשימה שמשותפת איתך, פתחו את ניהול השיתוף.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.blue)
            .navigationTitle("הגדרות")
            .task { await readAlertPermission() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await readAlertPermission() } }
            }
            .onChange(of: clarificationAlerts) { _, enabled in
                guard enabled else { return }
                Task {
                    await ClarificationNotifications.requestPermission(hasSharedLists: !store.sharedLists.isEmpty)
                    await readAlertPermission()
                }
            }
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
                    guard deletingListID == store.selectedListID else { return }
                    store.deleteCurrentList()
                    dismiss()
                }
            } message: {
                Text(LocalizedStringKey(store.currentShare == nil
                     ? "הרשימה, הפריטים והיסטוריית הקניות שלה יימחקו מכל המכשירים שלך."
                     : "הרשימה, הפריטים והיסטוריית הקניות שלה יימחקו גם אצל מי ששותף בה."))
            }
        }
    }

    private func readAlertPermission() async {
        alertsAllowed = await UNUserNotificationCenter.current().notificationSettings().alertSetting == .enabled
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


