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
                        sectionTitle("הרשימה שלי", count: store.items.count)
                        if groupByCategory {
                            ForEach(departmentNames, id: \.self) { department in
                                sectionTitle(department)
                                ForEach(categoryNames(in: department), id: \.self) { category in
                                    if category != "כללי" {
                                        Text(category)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    itemRows(store.items.filter { item in
                                        let product = store.product(for: item.productID)
                                        return (product?.department ?? "אחר") == department
                                            && (product?.category ?? "כללי") == category
                                    })
                                }
                            }
                        } else {
                            itemRows(store.items)
                        }
                    }

                    suggestionSection("כנראה תצטרכו", items: likely)
                    suggestionSection("אולי", items: maybe)

                    if !store.recentPurchases.isEmpty {
                        sectionTitle("נקנו לאחרונה")
                        Button("לכל הקניות") { showingHistory = true }
                            .font(.subheadline)
                        ForEach(store.recentPurchases) { purchase in
                            if let product = store.product(for: purchase.productID) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                    Text(product.name).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("ביטול") { withAnimation { store.undo(purchase) } }
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
                QuantityEditor(name: store.product(for: item.productID)?.name ?? "מוצר",
                               quantity: item.quantity) { quantity in
                    store.updateQuantity(of: item, to: quantity)
                }
            }
            .sheet(item: $editingCategory) { product in
                CategoryEditor(store: store, product: product)
            }
            .alert("רשימה חדשה לחנות", isPresented: $showingNewList) {
                TextField("שם החנות", text: $listName)
                Button("יצירה") { store.addList(name: listName) }
                Button("ביטול", role: .cancel) {}
            }
            .alert("שינוי שם הרשימה", isPresented: $showingRenameList) {
                TextField("שם החנות", text: $listName)
                Button("שמירה") { store.renameCurrentList(to: listName) }
                Button("ביטול", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
    }

    private var departmentNames: [String] {
        var seen = Set<String>()
        return store.items.compactMap { item in
            let name = store.product(for: item.productID)?.department ?? "אחר"
            return seen.insert(name).inserted ? name : nil
        }
    }

    private func categoryNames(in department: String) -> [String] {
        var seen = Set<String>()
        return store.items.compactMap { item in
            guard let product = store.product(for: item.productID),
                  (product.department ?? "אחר") == department else { return nil }
            let name = product.category ?? "כללי"
            return seen.insert(name).inserted ? name : nil
        }
    }

    private func details(for product: Product) -> String {
        let parts = [product.department, product.category].compactMap { $0 }
        return parts.isEmpty ? "ברשימה" : parts.joined(separator: " · ")
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
                        .accessibilityLabel("נקנה \(product.name)")
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(product.name).font(.body.weight(.medium)).lineLimit(2)
                                if item.isUrgent {
                                    Image(systemName: "flag.fill")
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("דחוף")
                                }
                            }
                            Text(details(for: product))
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
                            .accessibilityLabel("עריכת כמות עבור \(product.name)")
                            .accessibilityValue("כמות \(item.quantity)")
                        Menu {
                            Button("עריכת כמות", systemImage: "number") { editingItem = item }
                            Button("מחלקה וקטגוריה", systemImage: "square.grid.2x2") { editingCategory = product }
                            Button(item.isUrgent ? "הסרת דגל דחוף" : "סימון כדחוף",
                                   systemImage: item.isUrgent ? "flag.slash" : "flag") {
                                store.toggleUrgent(item)
                            }
                            Button("הסרה", systemImage: "trash", role: .destructive) { store.remove(item) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 44)
                        }
                        .accessibilityLabel("פעולות נוספות עבור \(product.name)")
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
                    Button(groupByCategory ? "מיון לפי מסלול הקנייה" : "קיבוץ לפי מחלקה וקטגוריה",
                           systemImage: "square.grid.2x2") { groupByCategory.toggle() }
                    Button("היסטוריה", systemImage: "clock") { showingHistory = true }
                    Button("תובנות", systemImage: "chart.bar") { showingInsights = true }
                    Button("הגדרות", systemImage: "gearshape") { showingSettings = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.medium))
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular, in: Circle())
                }
                .accessibilityLabel("אפשרויות נוספות")
            }
            Menu {
                ForEach(store.data.lists) { list in
                    Button(list.name, systemImage: list.id == store.selectedListID ? "checkmark" : "storefront") {
                        store.selectList(list.id)
                    }
                }
                Divider()
                Button("רשימה חדשה לחנות", systemImage: "plus") {
                    listName = ""
                    showingNewList = true
                }
                Button("שינוי שם הרשימה", systemImage: "pencil") {
                    listName = store.currentList.name
                    showingRenameList = true
                }
            } label: {
                Label(store.currentList.name, systemImage: "storefront")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("בחירת חנות, \(store.currentList.name)")
            Text(store.items.isEmpty && store.suggestions.isEmpty
                 ? "קצת פחות לזכור."
                 : store.items.isEmpty ? "כנראה תצטרכו" : "רשימת הקניות")
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(store.items.isEmpty && store.suggestions.isEmpty
                 ? "מוסיפים מה שצריך. הקניות יעזרו לרשימה ללמוד."
                 : store.suggestions.isEmpty ? "מוכנים לקנייה הבאה." : "לפי הקניות הקודמות שלכם")
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
            Text("הרשימה עדיין ריקה")
                .font(.title3.weight(.medium))
            Text("אפשר להתחיל עם כמה דברים שצריך היום.")
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
                if title == "אולי" {
                    HStack {
                        Text("אולי")
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
                                 ? "בדרך כלל ×\(suggestion.quantity)" : "מהקניות הקודמות")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button("לא עכשיו") { store.deferSuggestion(suggestion) }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button { store.add(suggestion) } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .accessibilityLabel("הוספת \(suggestion.product.name) לרשימה")
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
                    Text("הוספת מוצר...").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .glassEffect(.regular, in: Capsule())
            }
            .accessibilityLabel("הוספת מוצר")

            HStack {
                tab("רשימה", icon: "cart.fill", selected: true) {}
                tab("היסטוריה", icon: "clock") { showingHistory = true }
                tab("תובנות", icon: "chart.bar") { showingInsights = true }
                tab("הגדרות", icon: "gearshape") { showingSettings = true }
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
