import SwiftUI

@main
struct ProbablyGroceriesApp: App {
    @UIApplicationDelegateAdaptor(SharingAppDelegate.self) private var appDelegate
    @StateObject private var store = ShoppingStore()
    @StateObject private var invitations = ShareInvitationInbox.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var widgetPurchaseWatcher: Task<Void, Never>?
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

    var body: some Scene {
        WindowGroup {
            ShoppingView(store: store)
                .preferredColorScheme(testAppearance)
                .environment(\.locale, Locale(identifier: usesHebrew ? "he_IL" : "en"))
                .environment(\.layoutDirection, usesHebrew ? .rightToLeft : .leftToRight)
                .onReceive(invitations.$generation) { _ in acceptPending() }
                .onAppear { watchWidgetPurchases() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { watchWidgetPurchases() }
                    else { widgetPurchaseWatcher?.cancel() }
                }
                .onOpenURL { url in
                    guard url.scheme == "probablygroceries" else { return }
                    let parts = url.pathComponents.filter { $0 != "/" }
                    if url.host == "list", let id = parts.first.flatMap(UUID.init(uuidString:)) {
                        store.selectList(id)
                    }
                    if url.host == "add" {
                        if let id = parts.first.flatMap(UUID.init(uuidString:)) { store.selectList(id) }
                        NotificationCenter.default.post(name: .groceryWidgetAdd, object: nil)
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

    private func watchWidgetPurchases() {
        widgetPurchaseWatcher?.cancel()
        widgetPurchaseWatcher = Task { @MainActor in
            // AppIntent can finish after the app has already become active.
            // Short-lived polling closes that launch race without a permanent timer.
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                processWidgetPurchase()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func processWidgetPurchase() {
        let defaults = UserDefaults(suiteName: GroceryWidgetBridge.suite)
        guard let request = defaults?.dictionary(forKey: "pendingWidgetPurchase") as? [String: String],
              let value = request["itemID"],
              let id = UUID(uuidString: value) else { return }
        defaults?.removeObject(forKey: "pendingWidgetPurchase")
        guard let rawTime = request["requestedAt"],
              let timestamp = Double(rawTime),
              Date().timeIntervalSince1970 - timestamp < 120,
              Date().timeIntervalSince1970 >= timestamp - 10 else { return }
        // Only act on a still-active row; repeated check-offs are idempotent.
        guard let item = store.data.items.first(where: { $0.id == id }) else { return }
        store.selectList(item.listID)
        store.buy(item)
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


extension Notification.Name {
    static let groceryWidgetAdd = Notification.Name("groceryWidgetAdd")
}
