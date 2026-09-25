import SwiftUI

struct CategoryEditor: View {
    @ObservedObject var store: ShoppingStore
    let product: Product
    @Environment(\.dismiss) private var dismiss
    @State private var categoryName: String
    @State private var departmentName: String

    init(store: ShoppingStore, product: Product) {
        self.store = store
        self.product = product
        _categoryName = State(initialValue: product.category ?? "")
        _departmentName = State(initialValue: product.department ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("מחלקה", text: $departmentName)
                TextField("קטגוריה", text: $categoryName)
                if !store.departments.isEmpty {
                    Section("מחלקות קיימות") {
                        ForEach(store.departments, id: \.self) { name in
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
                Button("ללא מחלקה") { departmentName = "" }
            }
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        store.setGrouping(for: product.id, department: departmentName,
                                          category: categoryName)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
