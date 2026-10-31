import SwiftUI

struct GroceryDecisionSettings: View {
    @ObservedObject var store: ShoppingStore
    @ObservedObject private var service = GroceryDecisionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var provider: GroceryDecisionProvider = .openAI
    @State private var key = ""
    @State private var sponsor = ""
    @State private var consent = false
    @State private var testing = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(service.online ? service.status : "אין חיבור לאינטרנט", systemImage: "sparkles")
                    if let batch = store.data.decisionBatches.first(where: { $0.listID == store.selectedListID }) {
                        Text("עודכן על ידי \(batch.sponsor) · \(batch.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("אפשר להשתמש ברשימה גם בלי ספק. המלצות חכמות זמינות כשיש חיבור לאינטרנט.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("ספק החלטות") {
                    Picker("ספק", selection: $provider) {
                        ForEach(GroceryDecisionProvider.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("מודל", value: provider.model)
                    SecureField("מפתח API", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                    TextField("השם שלך לשותפים ברשימה", text: $sponsor)
                    Text("המפתח נשמר רק במכשיר הזה ונשלח ישירות לספק שבחרת. לרשימה מסתנכרנות רק התוצאות. החלפת החיבור תפעיל אותו לרשימה הנוכחית בלבד.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(testing)
                Section {
                    Toggle("אני מאשר שימוש בחשבון שלי להמלצות עבור ״\(store.currentList.name)״", isOn: $consent)
                        .tint(.green)
                    Text("לספק נשלחים שמות ויחידות של עד 32 מוצרים, ועד שש קניות אחרונות לכל מוצר עם כמות ומספר הימים שעברו. לא נשלחים תמונות, הערות או פרטי חשבון. יש לוודא שהשותפים מסכימים לשיתוף היסטוריית הקניות. הבדיקה משתמשת במידע לדוגמה בלבד. הבדיקה וההמלצות עשויות להיות בתשלום לפי החשבון שלך אצל הספק.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("בדיקת חיבור והפעלת המלצות") {
                        testing = true; message = nil
                        operation = Task { @MainActor in
                            defer { testing = false; key = "" }
                            do {
                                try await service.connect(provider: provider, key: key, sponsor: sponsor, store: store)
                                service.schedule(store: store)
                                message = "החיבור נבדק ונשמר."
                            } catch is CancellationError { } catch {
                                message = (error as? GroceryDecisionError)?.errorDescription
                                    ?? "לא הצלחנו לבדוק את החיבור. אפשר לנסות שוב."
                            }
                        }
                    }
                    .disabled(testing || service.busy || !service.online || !consent || key.isEmpty)
                    if testing { ProgressView("בודק חיבור…") }
                    if let message { Text(message).font(.footnote) }
                }
                if service.provider != nil {
                    Section {
                        Button("רענון המלצות לרשימה") { service.schedule(store: store, force: true) }
                            .disabled(!service.online || service.busy || !service.sponsors(store.selectedListID))
                        Button("ניתוק ומחיקת המפתח מהמכשיר", role: .destructive) {
                            do { try service.disconnect(store: store) }
                            catch { message = GroceryDecisionError.keyStorage.errorDescription }
                        }
                        .disabled(testing)
                        Text("החישוב פועל מהמכשיר שלך. כשהוא אינו זמין, השותפים מקבלים את ההמלצות האחרונות שעדיין בתוקף. הניתוק אינו מבטל מפתח באתר הספק.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Link("ניהול החשבון אצל הספק", destination: provider == .openAI
                         ? URL(string: "https://platform.openai.com/settings/organization/billing/overview")!
                         : URL(string: "https://typesafe.ai")!)
                    Text("עד 20 בקשות ביום במכשיר, כולל בדיקות חיבור. המכסה הזו אינה מגבלת חיוב כספית אצל הספק.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("המלצות חכמות")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } } }
            .onAppear { provider = service.provider ?? .openAI; sponsor = service.sponsorName }
            .onDisappear { operation?.cancel(); key = "" }
        }
    }
}
