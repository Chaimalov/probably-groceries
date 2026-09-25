import SwiftUI

struct AddItemSheet: View {
    @ObservedObject var store: ShoppingStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var name = ""
    @State private var quantity = 1
    @State private var category = ""
    @State private var department = ""
    @State private var urgent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("מה צריך לקנות?", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(save)
                    Stepper("כמות: \(quantity)", value: $quantity, in: 1...99)
                    TextField("מחלקה (לא חובה)", text: $department)
                    TextField("קטגוריה (לא חובה)", text: $category)
                    Toggle("דחוף", isOn: $urgent)
                }

                if !store.departments.isEmpty {
                    Section("מחלקות") {
                        ForEach(store.departments, id: \.self) { existing in
                            Button(existing) { department = existing }
                        }
                    }
                }

                if !store.categories.isEmpty {
                    Section("קטגוריות") {
                        ForEach(store.categories, id: \.self) { existing in
                            Button(existing) { category = existing }
                        }
                    }
                }

                if !name.isEmpty {
                    let matches = store.matchingProducts(name)
                    if !matches.isEmpty {
                        Section("מהקניות הקודמות") {
                            ForEach(matches.prefix(6)) { product in
                                Button(product.name) {
                                    name = product.name
                                    quantity = product.usualQuantity
                                    category = product.category ?? ""
                                    department = product.department ?? ""
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("הוספת מוצר")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("הוספה", action: save)
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
        store.add(name: name, quantity: quantity, category: category,
                  department: department, urgent: urgent)
        dismiss()
    }
}
