import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Your data") {
                    Label("Saved on this device", systemImage: "iphone")
                    Text("iCloud sync and sharing are coming later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("About") {
                    Text("Probably Groceries")
                    Text("A little less to remember.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
