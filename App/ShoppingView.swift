import SwiftUI

struct ShoppingView: View {
    @StateObject private var store = ShoppingStore()
    @State private var showingAdd = false
    @State private var showingHistory = false
    @State private var editingItem: ShoppingItem?

    private var likely: [Suggestion] { store.suggestions.filter { $0.tier == .likely } }
    private var maybe: [Suggestion] { store.suggestions.filter { $0.tier == .maybe } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if store.items.isEmpty && store.suggestions.isEmpty {
                        emptyState
                    }

                    if !store.items.isEmpty {
                        sectionTitle("Your list", count: store.items.count)
                        VStack(spacing: 0) {
                            ForEach(store.items) { item in
                                if let product = store.product(for: item.productID) {
                                    HStack(spacing: 16) {
                                        Button { withAnimation(.smooth) { store.buy(item) } } label: {
                                            Image(systemName: "circle")
                                                .font(.title2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .accessibilityLabel("Bought \(product.name)")
                                        Text(product.name).font(.body)
                                        Spacer()
                                        Button("×\(item.quantity)") { editingItem = item }
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("Edit quantity for \(product.name)")
                                            .accessibilityValue("Quantity \(item.quantity)")
                                        Button(role: .destructive) { store.remove(item) } label: {
                                            Image(systemName: "xmark").font(.caption)
                                        }
                                        .tint(.secondary)
                                        .accessibilityLabel("Remove \(product.name)")
                                    }
                                    .padding(.vertical, 13)
                                    Divider()
                                }
                            }
                        }
                    }

                    suggestionSection("You'll probably need", items: likely)
                    suggestionSection("Maybe", items: maybe)

                    if !store.recentPurchases.isEmpty {
                        sectionTitle("Recently bought")
                        Button("See all purchases") { showingHistory = true }
                            .font(.subheadline)
                        ForEach(store.recentPurchases) { purchase in
                            if let product = store.product(for: purchase.productID) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                    Text(product.name).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Undo") { withAnimation { store.undo(purchase) } }
                                        .font(.subheadline)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom) {
                Button { showingAdd = true } label: {
                    Label("Add item", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) { AddItemSheet(store: store) }
            .sheet(isPresented: $showingHistory) { PurchaseHistoryView(store: store) }
            .sheet(item: $editingItem) { item in
                QuantityEditor(name: store.product(for: item.productID)?.name ?? "Item",
                               quantity: item.quantity) { quantity in
                    store.updateQuantity(of: item, to: quantity)
                }
            }
        }
        .tint(.primary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROBABLY")
                .font(.caption.weight(.semibold))
                .tracking(3)
                .foregroundStyle(.secondary)
            Text("A little less\nto remember.")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("Your next grocery trip starts here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "basket")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing on the list yet")
                .font(.title3.weight(.medium))
            Text("Add what you need. Checking things off when you buy them helps this list learn your rhythm.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let count { Text("\(count)").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func suggestionSection(_ title: String, items: [Suggestion]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(title)
                ForEach(items) { suggestion in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.product.name)
                            if suggestion.quantity > 1 {
                                Text("Usually ×\(suggestion.quantity)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Not yet") { withAnimation { store.deferSuggestion(suggestion) } }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button { withAnimation { store.add(suggestion) } } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .accessibilityLabel("Add \(suggestion.product.name) to list")
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}
