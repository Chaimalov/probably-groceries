import SwiftUI

struct ShoppingPreparationView: View {
    @ObservedObject var store: ShoppingStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ShoppingDraft
    @State private var filter = "הכול"
    @State private var manualName = ""
    @State private var details: ShoppingItem?

    init(store: ShoppingStore) {
        self.store = store
        _draft = State(initialValue: store.shoppingDraft())
    }
    private var places: [String] {
        Array(Set(store.items.compactMap(\.shoppingPlace) + draft.entries.compactMap(\.place))).filter { !$0.isEmpty }.sorted()
    }
    private func visible(_ place: String?) -> Bool {
        filter == "הכול" || (filter == "ללא מקום" ? place == nil || place == "" : place == filter)
    }
    var body: some View {
        NavigationStack {
            List {
                if !places.isEmpty {
                    Picker("מקום קנייה", selection: $filter) {
                        Text("הכול").tag("הכול")
                        Text("ללא מקום").tag("ללא מקום")
                        ForEach(places, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("נשארו ברשימה") {
                    ForEach(store.items.filter { visible($0.shoppingPlace) }) { item in
                        Button { details = item } label: {
                            HStack {
                                Text(store.product(for: item.productID)?.name ?? "מוצר")
                                Spacer()
                                Text("×\(item.quantity) \(item.unit ?? "")").foregroundStyle(.secondary)
                                Image(systemName: "info.circle")
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if store.items.isEmpty { Text("אין מוצרים שנותרו").foregroundStyle(.secondary) }
                }
                Section("השלמות מוצעות") {
                    ForEach($draft.entries) { $entry in
                        if visible(entry.place) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("שם המוצר", text: $entry.name)
                                    Button {
                                        entry.included.toggle()
                                    } label: {
                                        Image(systemName: entry.included ? "minus.circle" : "arrow.uturn.backward")
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(entry.included ? "החרגת \(entry.name)" : "החזרת \(entry.name)")
                                }
                                if entry.included {
                                    Stepper("כמות: \(entry.quantity)", value: $entry.quantity, in: 1...9999)
                                    TextField("יחידת מידה", text: Binding(get: { entry.unit ?? "" }, set: { entry.unit = $0.isEmpty ? nil : $0 }))
                                    TextField("הערה", text: Binding(get: { entry.note ?? "" }, set: { entry.note = $0.isEmpty ? nil : $0 }))
                                    TextField("מקום קנייה (אופציונלי)", text: Binding(get: { entry.place ?? "" }, set: { entry.place = $0.isEmpty ? nil : $0 }))
                                    if let reason = entry.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .foregroundStyle(entry.included ? .primary : .secondary)
                        }
                    }
                    if draft.entries.isEmpty {
                        Text("אפשר להוסיף מוצרים. הצעות יופיעו לאחר כמה קניות חוזרות.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("מוצר נוסף", text: $manualName).submitLabel(.next).onSubmit(addManual)
                    Button("הוספת מוצר", systemImage: "plus", action: addManual)
                        .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if filter != "הכול" {
                    Text("האישור כולל את כל הרשימה").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("קנייה חדשה")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("אישור") {
                        addManual()
                        store.confirmDraft(draft)
                        dismiss()
                    }
                }
            }
            .onChange(of: draft) { _, value in store.saveDraft(value) }
            .sheet(item: $details) { ItemDetailsSheet(store: store, item: $0) }
        }
    }
    private func addManual() {
        let parsed = ShoppingInputParser.parse(manualName)
        guard !parsed.name.isEmpty else { return }
        draft.entries.append(DraftEntry(name: parsed.name, quantity: parsed.quantity, unit: parsed.unit))
        manualName = ""
        store.saveDraft(draft)
    }
}

struct ItemDetailsSheet: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @Environment(\.dismiss) private var dismiss
    @State private var place = ""
    var body: some View {
        NavigationStack {
            Form {
                if let current = store.items.first(where: { $0.id == item.id }) {
                    ItemInlineDetails(store: store, item: current)
                    Section("מקום קנייה") {
                        TextField("אופציונלי", text: $place)
                            .onChange(of: place) { _, value in store.updatePlace(of: current, to: value) }
                    }
                    Section {
                        CategoryEditorLink(store: store, item: current)
                    }
                } else { Text("המוצר כבר אינו ברשימה") }
            }
            .navigationTitle(store.product(for: item.productID)?.name ?? "פרטי מוצר")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגירה", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .onAppear { place = item.shoppingPlace ?? "" }
        }
    }
}

private struct CategoryEditorLink: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @State private var showing = false
    var body: some View {
        Button("מקטע: \(store.section(for: item))") { showing = true }
            .sheet(isPresented: $showing) { CategoryEditor(store: store, item: item) }
    }
}
