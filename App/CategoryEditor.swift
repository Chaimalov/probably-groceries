import SwiftUI

struct CategoryEditor: View {
    @ObservedObject var store: ShoppingStore
    let product: Product
    @Environment(\.dismiss) private var dismiss
    @State private var categoryName: String

    init(store: ShoppingStore, product: Product) {
        self.store = store
        self.product = product
        _categoryName = State(initialValue: product.category ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("קטגוריה", text: $categoryName)
                if !store.categories.isEmpty {
                    Section("קטגוריות קיימות") {
                        ForEach(store.categories, id: \.self) { name in
                            Button(name) { categoryName = name }
                        }
                    }
                }
                Button("ללא קטגוריה") { categoryName = "" }
            }
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        store.setCategory(for: product.id, to: categoryName)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
