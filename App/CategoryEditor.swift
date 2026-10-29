import SwiftUI

struct CategoryEditor: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @Environment(\.dismiss) private var dismiss
    @State private var departmentName: String

    init(store: ShoppingStore, item: ShoppingItem) {
        self.store = store
        self.item = item
        let section = store.section(for: item)
        _departmentName = State(initialValue: section == "אחר" ? "" : section)
    }

    private var availableSections: [String] {
        store.sectionNames.filter { $0 != "אחר" }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("מקטע", text: $departmentName)
                if !availableSections.isEmpty {
                    Section("מקטעים קיימים") {
                        ForEach(availableSections, id: \.self) { name in
                            Button(name) { departmentName = name }
                        }
                    }
                }
                Button("ללא מקטע") { departmentName = "" }
            }
            .navigationTitle(store.product(for: item.productID)?.name ?? "מוצר")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        store.move(item.id, toSection: departmentName.isEmpty ? "אחר" : departmentName)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

