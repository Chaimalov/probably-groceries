import CloudKit
import SwiftUI
import UIKit

struct ListSharingSheet: View {
    @ObservedObject var store: ShoppingStore
    let listID: UUID
    @State private var share: CKShare?
    @State private var failure: String?
    @State private var busy = false
    @State private var retryListID: UUID?
    @State private var controllerError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let share {
                    CloudSharingView(share: share, container: store.cloudSync.container,
                        onFailure: { controllerError = $0.localizedDescription },
                        onChange: { store.cloudSync.schedule() })
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "person.2.fill").font(.largeTitle).foregroundStyle(.green)
                        Text("רשימה אחת, לשניכם").font(.title2.bold())
                        Text("הזמינו אנשים להוסיף מוצרים ולסמן מה נקנה. רק הרשימה הזו והיסטוריית הקניות שלה ישותפו.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if busy { ProgressView("מכינים את הרשימה לשיתוף…") }
                        if let failure {
                            Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("ניסיון נוסף") { prepare() }.disabled(busy)
                        }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("שיתוף רשימה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגירה") { dismiss() } } }
        }
        .task { prepare() }
        .alert("השיתוף לא נשמר", isPresented: Binding(
            get: { controllerError != nil }, set: { if !$0 { controllerError = nil } })) {
            Button("סגירה", role: .cancel) {}
        } message: { Text(controllerError ?? "") }
    }

    private func prepare() {
        guard !busy else { return }
        busy = true
        failure = nil
        Task {
            defer { busy = false }
            do { share = try await store.cloudSync.prepareShare(for: retryListID ?? listID) }
            catch {
                // A failed upload may follow a completed local list migration.
                retryListID = store.selectedListID
                failure = error.localizedDescription
            }
        }
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onFailure: (Error) -> Void
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let view: CloudSharingView
        init(_ view: CloudSharingView) { self.view = view }
        func itemTitle(for csc: UICloudSharingController) -> String? {
            view.share[CKShare.SystemFieldKey.title] as? String
        }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            view.onFailure(error)
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { view.onChange() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { view.onChange() }
    }
}
