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
                TextField("Category", text: $categoryName)
                if !store.categories.isEmpty {
                    Section("Existing categories") {
                        ForEach(store.categories, id: \.self) { name in
                            Button(name) { categoryName = name }
                        }
                    }
                }
                Button("No category") { categoryName = "" }
            }
            .navigationTitle(product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setCategory(for: product.id, to: categoryName)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
