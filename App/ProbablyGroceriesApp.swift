import SwiftUI

@main
struct ProbablyGroceriesApp: App {
    @UIApplicationDelegateAdaptor(SharingAppDelegate.self) private var appDelegate
    @StateObject private var store = ShoppingStore()
    @StateObject private var invitations = ShareInvitationInbox.shared
    @State private var accepting = false
    @State private var invitationError: String?

    var body: some Scene {
        WindowGroup {
            ShoppingView(store: store)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .environment(\.layoutDirection, .rightToLeft)
                .onReceive(invitations.$generation) { _ in acceptPending() }
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
