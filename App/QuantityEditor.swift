import SwiftUI

struct QuantityEditor: View {
    let name: String
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int

    init(name: String, quantity: Int, onSave: @escaping (Int) -> Void) {
        self.name = name
        self.onSave = onSave
        _quantity = State(initialValue: quantity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("כמות: \(quantity)", value: $quantity, in: 1...9999)
                    .accessibilityIdentifier("quantityStepper")
            }
            .navigationTitle(name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        onSave(quantity)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
