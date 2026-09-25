import SwiftUI
import UIKit

struct ShoppingView: View {
    @StateObject private var store = ShoppingStore()
    @State private var showingAdd = false
    @State private var showingHistory = false
    @State private var showingInsights = false
    @State private var showingSettings = false
    @State private var editingItem: ShoppingItem?
    @State private var editingCategory: Product?
    @State private var showingNewList = false
    @State private var showingRenameList = false
    @State private var listName = ""
    @AppStorage("groupShoppingByCategory") private var groupByCategory = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var likely: [Suggestion] { store.suggestions.filter { $0.tier == .likely } }
    private var maybe: [Suggestion] { store.suggestions.filter { $0.tier == .maybe } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if store.items.isEmpty && store.suggestions.isEmpty {
                        emptyState
                    }

                    if !store.items.isEmpty {
                        sectionTitle("Your list", count: store.items.count)
                        if groupByCategory {
                            ForEach(categoryNames, id: \.self) { name in
                                sectionTitle(name)
                                itemRows(store.items.filter {
                                    (store.product(for: $0.productID)?.category ?? "Other") == name
                                })
                            }
                        } else {
                            itemRows(store.items)
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
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) { AddItemSheet(store: store) }
            .sheet(isPresented: $showingHistory) { PurchaseHistoryView(store: store) }
            .sheet(isPresented: $showingInsights) { PredictionDebugView(store: store) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $editingItem) { item in
                QuantityEditor(name: store.product(for: item.productID)?.name ?? "Item",
                               quantity: item.quantity) { quantity in
                    store.updateQuantity(of: item, to: quantity)
                }
            }
            .sheet(item: $editingCategory) { product in
                CategoryEditor(store: store, product: product)
            }
            .alert("New store list", isPresented: $showingNewList) {
                TextField("Store name", text: $listName)
                Button("Create") { store.addList(name: listName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename list", isPresented: $showingRenameList) {
                TextField("Store name", text: $listName)
                Button("Save") { store.renameCurrentList(to: listName) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
    }

    private var categoryNames: [String] {
        var seen = Set<String>()
        return store.items.compactMap { item in
            let name = store.product(for: item.productID)?.category ?? "Other"
            return seen.insert(name).inserted ? name : nil
        }
    }

    private func itemRows(_ items: [ShoppingItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                if let product = store.product(for: item.productID) {
                    HStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if reduceMotion { store.buy(item) }
                            else { withAnimation(.smooth) { store.buy(item) } }
                        } label: {
                            Image(systemName: "circle")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 48)
                        }
                        .accessibilityLabel("Bought \(product.name)")
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(product.name).font(.body.weight(.medium)).lineLimit(2)
                                if item.isUrgent {
                                    Image(systemName: "flag.fill")
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Urgent")
                                }
                            }
                            Text(product.category ?? "On your list")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button("×\(item.quantity)") { editingItem = item }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                            .accessibilityLabel("Edit quantity for \(product.name)")
                            .accessibilityValue("Quantity \(item.quantity)")
                        Menu {
                            Button("Edit quantity", systemImage: "number") { editingItem = item }
                            Button("Category", systemImage: "square.grid.2x2") { editingCategory = product }
                            Button(item.isUrgent ? "Not urgent" : "Mark urgent",
                                   systemImage: item.isUrgent ? "flag.slash" : "flag") {
                                store.toggleUrgent(item)
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) { store.remove(item) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 44)
                        }
                        .accessibilityLabel("More actions for \(product.name)")
                    }
                    .padding(.vertical, 8)
                    if item.id != items.last?.id { Divider().padding(.leading, 44) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(groupByCategory ? "Use shopping route" : "Group by category",
                           systemImage: "square.grid.2x2") { groupByCategory.toggle() }
                    Button("History", systemImage: "clock") { showingHistory = true }
                    Button("Insights", systemImage: "chart.bar") { showingInsights = true }
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.medium))
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .accessibilityLabel("More options")
            }
            Menu {
                ForEach(store.data.lists) { list in
                    Button(list.name, systemImage: list.id == store.selectedListID ? "checkmark" : "storefront") {
                        store.selectList(list.id)
                    }
                }
                Divider()
                Button("New store list", systemImage: "plus") {
                    listName = ""
                    showingNewList = true
                }
                Button("Rename current list", systemImage: "pencil") {
                    listName = store.currentList.name
                    showingRenameList = true
                }
            } label: {
                Label(store.currentList.name, systemImage: "storefront")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("Choose store list, \(store.currentList.name)")
            Text(store.items.isEmpty && store.suggestions.isEmpty
                 ? "A little less to remember."
                 : store.items.isEmpty ? "You'll probably need" : "Your shopping list")
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(store.items.isEmpty && store.suggestions.isEmpty
                 ? "Add what you need. Your purchases will help this list learn."
                 : store.suggestions.isEmpty ? "Ready for your next trip." : "Based on your past purchases")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "basket")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing on the list yet")
                .font(.title3.weight(.medium))
            Text("Start with a few things you need today.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let count { Text("\(count)").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func suggestionSection(_ title: String, items: [Suggestion]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if title == "Maybe" {
                    HStack {
                        Text("MAYBE")
                            .font(.caption.weight(.medium))
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
                    }
                    .padding(.bottom, 4)
                } else {
                    sectionTitle(title).padding(.bottom, 4)
                }
                ForEach(items) { suggestion in
                    HStack(spacing: 12) {
                        Image(systemName: "circle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.tertiary)
                            .frame(width: 32, height: 48)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.product.name).font(.body.weight(.medium))
                            Text(suggestion.quantity > 1
                                 ? "Usually ×\(suggestion.quantity)" : "From your history")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button("Not yet") { store.deferSuggestion(suggestion) }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button { store.add(suggestion) } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .accessibilityLabel("Add \(suggestion.product.name) to list")
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button { showingAdd = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent, in: Circle())
                    Text("Add an item...").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .glassEffect(.regular, in: Capsule())
            }
            .accessibilityLabel("Add item")

            HStack {
                tab("List", icon: "cart.fill", selected: true) {}
                tab("History", icon: "clock") { showingHistory = true }
                tab("Insights", icon: "chart.bar") { showingInsights = true }
                tab("Settings", icon: "gearshape") { showingSettings = true }
            }
            .padding(.vertical, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 25))
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func tab(_ title: String, icon: String, selected: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19))
                Text(title).font(.caption2)
            }
            .foregroundStyle(selected ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
        }
    }
}
