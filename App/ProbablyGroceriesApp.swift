import SwiftUI

@main
struct ProbablyGroceriesApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(SharingAppDelegate.self) private var appDelegate
    @StateObject private var store = ShoppingStore.shared
    @StateObject private var invitations = ShareInvitationInbox.shared
    @State private var accepting = false
    @State private var invitationError: String?

    // Explicit test-only appearance avoids macOS defaults that iOS ignores.
    // Normal launches continue to follow the user's system appearance.
    private var testAppearance: ColorScheme? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return nil }
        switch ProcessInfo.processInfo.environment["UITEST_APPEARANCE"] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private var usesHebrew: Bool {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return true }
        return Bundle.main.preferredLocalizations.first != "en"
    }

    init() {
        PhoneWatchBridge.shared.start()
        if ShoppingStore.shared.storageError == nil {
            PhoneWatchBridge.shared.publish(ShoppingStore.shared.watchSnapshot())
        }
    }

    var body: some Scene {
        WindowGroup {
            ShoppingView(store: store)
                .task { ProductDecisionService.shared.schedule(store: store); store.refreshBadge() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { ProductDecisionService.shared.schedule(store: store); store.refreshBadge() }
                }
                .preferredColorScheme(testAppearance)
                .environment(\.locale, Locale(identifier: usesHebrew ? "he_IL" : "en"))
                .environment(\.layoutDirection, usesHebrew ? .rightToLeft : .leftToRight)
                .onReceive(invitations.$generation) { _ in acceptPending() }
                .onOpenURL { url in
                    guard url.scheme == "probablygroceries" else { return }
                    let parts = url.pathComponents.filter { $0 != "/" }
                    if url.host == "list", let id = parts.first.flatMap(UUID.init(uuidString:)) {
                        store.selectList(id)
                    }
                    if url.host == "edit", let id = parts.first.flatMap(UUID.init(uuidString:)),
                       let item = store.data.items.first(where: { $0.id == id }) {
                        store.selectList(item.listID)
                        store.widgetNavigation = ShoppingStore.WidgetNavigation(itemID: id)
                    }
                    if url.host == "add" {
                        if let id = parts.first.flatMap(UUID.init(uuidString:)) { store.selectList(id) }
                        store.widgetNavigation = ShoppingStore.WidgetNavigation()
                    }
                }
                .alert("לא ניתן להצטרף כרגע", isPresented: Binding(
                    get: { invitationError != nil },
                    set: { if !$0 { invitationError = nil } })) {
                    Button("ניסיון נוסף") { invitations.retry() }
                    Button("מאוחר יותר", role: .cancel) {}
                } message: { Text(invitationError ?? "") }
        }
    }

    private func acceptPending() {
        guard !accepting, !invitations.pending.isEmpty else { return }
        accepting = true
        Task {
            defer { accepting = false }
            while let metadata = invitations.pending.first {
                do {
                    try await store.cloudSync.accept(metadata)
                    invitations.removeFirst()
                } catch { invitationError = error.localizedDescription; break }
            }
        }
    }
}


