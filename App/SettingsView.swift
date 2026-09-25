import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("הנתונים שלך") {
                    Label("שמורים במכשיר הזה", systemImage: "iphone")
                    Text("סנכרון ושיתוף באמצעות iCloud יתווספו בהמשך.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("אודות") {
                    Text("רשימת הקניות")
                    Text("קצת פחות לזכור.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("הגדרות")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
    }
}
