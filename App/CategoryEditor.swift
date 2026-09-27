import SwiftUI

struct CategoryEditor: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @Environment(\.dismiss) private var dismiss
    @State private var categoryName: String
    @State private var departmentName: String

    init(store: ShoppingStore, item: ShoppingItem) {
        self.store = store
        self.item = item
        _categoryName = State(initialValue: store.product(for: item.productID)?.category ?? "")
        let section = store.section(for: item)
        _departmentName = State(initialValue: section == "אחר" ? "" : section)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("מקטע", text: $departmentName)
                TextField("קטגוריה", text: $categoryName)
                if !store.currentList.sections.isEmpty || !store.departments.isEmpty {
                    Section("מקטעים קיימים") {
                        ForEach(Array(Set(store.currentList.sections + store.departments)).sorted(), id: \.self) { name in
                            Button(name) { departmentName = name }
                        }
                    }
                }
                if !store.categories.isEmpty {
                    Section("קטגוריות קיימות") {
                        ForEach(store.categories, id: \.self) { name in
                            Button(name) { categoryName = name }
                        }
                    }
                }
                Button("ללא קטגוריה") { categoryName = "" }
                Button("ללא מקטע") { departmentName = "" }
            }
            .navigationTitle(store.product(for: item.productID)?.name ?? "מוצר")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        store.setGrouping(for: item.id, department: departmentName,
                                          category: categoryName)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
