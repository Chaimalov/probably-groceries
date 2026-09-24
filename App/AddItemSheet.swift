import SwiftUI

struct AddItemSheet: View {
    @ObservedObject var store: ShoppingStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var name = ""
    @State private var quantity = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you need?", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(save)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                }

                if !name.isEmpty {
                    let matches = store.matchingProducts(name)
                    if !matches.isEmpty {
                        Section("From your history") {
                            ForEach(matches.prefix(6)) { product in
                                Button(product.name) {
                                    name = product.name
                                    quantity = product.usualQuantity
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.add(name: name, quantity: quantity)
        dismiss()
    }
}
