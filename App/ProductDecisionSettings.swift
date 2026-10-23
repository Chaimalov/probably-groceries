import SwiftUI

struct ProductDecisionSettings: View {
    @ObservedObject var store: ShoppingStore
    @ObservedObject private var service = ProductDecisionService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var code = ""
    @State private var connecting = false
    @State private var error: String?
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(LocalizedStringKey(service.status), systemImage: service.connected ? "checkmark.shield" : "link")
                    Text("כדי לזהות שמות שונים של אותו מוצר, נשלחים לשירות שמות מוצרים ויחידות מידה בלבד. הקניות ממשיכות לעבוד גם בלי חיבור.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if service.connected {
                    Section {
                        Text(service.endpoint).font(.footnote).textSelection(.enabled)
                        LabeledContent("מזהה מכשיר") {
                            Text(service.deviceID).font(.caption2).textSelection(.enabled)
                        }
                        Button("ניתוק השירות", role: .destructive) { service.disconnect() }
                    }
                } else {
                    Section("חיבור חד־פעמי") {
                        TextField("כתובת השרת", text: $serverURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                        SecureField("קוד חיבור", text: $code)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                        Button("חיבור וזיהוי מוצרים") {
                            connecting = true; error = nil
                            Task {
                                defer { connecting = false }
                                do {
                                    try await service.connect(endpoint: serverURL, code: code, store: store)
                                    code = ""
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .disabled(connecting || serverURL.isEmpty || code.isEmpty)
                        if connecting { ProgressView() }
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                }
                Section {
                    Button("איפוס קישורים שנלמדו", role: .destructive) { confirmingReset = true }
                    Text("האיפוס משאיר את שמות המוצרים ואת כל היסטוריית הקניות כפי שהם.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("זיהוי מוצרים")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } } }
            .onAppear { serverURL = service.endpoint }
            .confirmationDialog("לאפס את הקישורים שנלמדו?", isPresented: $confirmingReset) {
                Button("איפוס", role: .destructive) { service.disconnect(); store.resetProductLearning() }
            }
        }
    }
}
