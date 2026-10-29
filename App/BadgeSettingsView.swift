import SwiftUI
import UserNotifications

struct BadgeSettingsView: View {
    @ObservedObject var store: ShoppingStore
    @AppStorage("shoppingBadgeEnabled") private var enabled = false
    @AppStorage("shoppingBadgeLists") private var lists = "selected"
    @AppStorage("shoppingBadgeUrgentOnly") private var urgentOnly = false
    @AppStorage("shoppingBadgeQuantities") private var quantities = false
    @AppStorage("shoppingBadgeExcludeUnavailable") private var excludeUnavailable = false
    @AppStorage("shoppingBadgeListIDsText") private var chosenLists = ""
    @State private var badgeAllowed = true
    @State private var permissionError = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Toggle("מספר מוצרים על אייקון האפליקציה", isOn: $enabled)
            } footer: { Text("כשהמספר אפס, התג נעלם. הספירה מתעדכנת אחרי שינוי ברשימה או קבלת סנכרון.") }
            if enabled {
                Section("מה סופרים") {
                    Picker("רשימות", selection: $lists) {
                        Text("הרשימה הפתוחה").tag("selected")
                        Text("כל הרשימות").tag("all")
                        Text("רשימות נבחרות").tag("chosen")
                    }
                    if lists == "chosen" {
                        ForEach(store.data.lists) { list in
                            Toggle(list.name, isOn: Binding(
                                get: { chosenLists.split(separator: ",").contains(Substring(list.id.uuidString)) },
                                set: { included in
                                    var ids = Set(chosenLists.split(separator: ",").map(String.init))
                                    if included { ids.insert(list.id.uuidString) } else { ids.remove(list.id.uuidString) }
                                    chosenLists = ids.sorted().joined(separator: ",")
                                    UserDefaults.standard.set(ids.sorted(), forKey: "shoppingBadgeListIDs")
                                    store.refreshBadge()
                                }))
                        }
                    }
                    Toggle("דחופים בלבד", isOn: $urgentOnly)
                    Toggle("סכום כמויות במקום שורות", isOn: $quantities)
                    Toggle("ללא מוצרים שלא היו בחנות", isOn: $excludeUnavailable)
                }
                Section {
                    LabeledContent("המספר כרגע", value: "\(BadgePolicy.count(in: store.data, selectedListID: store.selectedListID))")
                    Text("שורות: 3 יחידות חלב נספרות כמוצר אחד. כמויות: הן נספרות כ־3.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !badgeAllowed {
                        Text("יש לאפשר תגים בהגדרות האייפון כדי להציג את המספר.")
                        Button("פתיחת הגדרות האייפון") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
        }
        .navigationTitle("תג האפליקציה")
        .task { await readPermission() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await readPermission(); store.refreshBadge() } } }
        .onChange(of: enabled) { _, value in
            if value {
                Task {
                    do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) }
                    catch { permissionError = true }
                    await readPermission()
                    store.refreshBadge()
                }
            } else { store.refreshBadge() }
        }
        .onChange(of: lists) { _, _ in store.refreshBadge() }
        .onChange(of: urgentOnly) { _, _ in store.refreshBadge() }
        .onChange(of: quantities) { _, _ in store.refreshBadge() }
        .onChange(of: excludeUnavailable) { _, _ in store.refreshBadge() }
        .alert("לא ניתן להפעיל את התג כרגע", isPresented: $permissionError) { Button("סיום", role: .cancel) {} }
    }

    private func readPermission() async {
        badgeAllowed = await UNUserNotificationCenter.current().notificationSettings().badgeSetting == .enabled
    }
}
