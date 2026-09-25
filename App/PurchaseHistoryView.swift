import SwiftUI

struct PurchaseHistoryView: View {
    @ObservedObject var store: ShoppingStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingPurchase: Purchase?

    var body: some View {
        NavigationStack {
            List(store.purchases) { purchase in
                if let product = store.product(for: purchase.productID) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                            Text(purchase.purchasedAt, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("×\(purchase.quantity)") { editingPurchase = purchase }
                            .accessibilityLabel("עריכת כמות שנקנתה עבור \(product.name)")
                            .accessibilityValue("כמות \(purchase.quantity)")
                        Button("ביטול קנייה") { store.undo(purchase) }
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle("היסטוריית קניות")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        .sheet(item: $editingPurchase) { purchase in
            QuantityEditor(name: store.product(for: purchase.productID)?.name ?? "מוצר",
                           quantity: purchase.quantity) { quantity in
                store.correctQuantity(of: purchase, to: quantity)
            }
        }
    }
}
