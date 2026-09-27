import SwiftUI
import UIKit
import PhotosUI

struct ShoppingView: View {
    @StateObject private var store = ShoppingStore()
    @State private var isAdding = false
    @State private var newName = ""
    @State private var editedName = ""
    @State private var expandedItemID: UUID?
    @State private var editingCategory: Product?
    @State private var editingNameID: UUID?
    @State private var showingHistory = false
    @State private var showingNewList = false
    @State private var showingRenameList = false
    @State private var showingNewSection = false
    @State private var listName = ""
    @State private var sectionName = ""
    @State private var collapsedSections: Set<String> = []
    @FocusState private var addFocused: Bool
    @FocusState private var nameFocused: UUID?
    @AppStorage("groupShoppingByCategory") private var groupBySection = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var likely: [Suggestion] { store.suggestions.filter { $0.tier == .likely } }
    private var maybe: [Suggestion] { store.suggestions.filter { $0.tier == .maybe } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List {
                    if groupBySection {
                        ForEach(sectionNames, id: \.self) { section in
                            Section {
                                if !collapsedSections.contains(section) {
                                    ForEach(items(in: section)) { item in itemRow(item) }
                                }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    } else {
                        Section {
                            ForEach(store.items) { item in itemRow(item) }
                        }
                    }

                    if isAdding {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "circle")
                                    .font(.title2.weight(.ultraLight))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 28)
                                TextField("מה צריך לקנות?", text: $newName)
                                    .focused($addFocused)
                                    .submitLabel(.next)
                                    .onSubmit(addInline)
                                    .onChange(of: newName) { _, value in
                                        if value.contains("\n") { addInline() }
                                    }
                                    .accessibilityIdentifier("inlineAddField")
                            }
                            .id("new-item")
                        }
                    }

                    if !likely.isEmpty { suggestionSection("כנראה צריך", items: likely) }
                    if !maybe.isEmpty { suggestionSection("אולי", items: maybe) }

                    if !store.recentPurchases.isEmpty {
                        Section("נקנו לאחרונה") {
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
                                    .swipeActions {
                                        Button("ביטול קנייה", systemImage: "arrow.uturn.backward") {
                                            store.undo(purchase)
                                        }
                                    }
                                }
                            }
                            Button("לכל הקניות") { showingHistory = true }
                                .font(.subheadline)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack {
                        Button {
                            isAdding = true
                            Task { @MainActor in
                                await Task.yield()
                                scroll.scrollTo("new-item", anchor: .bottom)
                                addFocused = true
                            }
                        } label: {
                            Label("מוצר חדש", systemImage: "plus.circle.fill")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("הוספת מוצר")
                        Spacer()
                        if isAdding && !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("הוסף", action: addInline)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle(store.currentList.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { listPicker }
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            .sheet(item: $editingCategory) { CategoryEditor(store: store, product: $0) }
            .sheet(isPresented: $showingHistory) { PurchaseHistoryView(store: store) }
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
            .alert("מחלקה חדשה", isPresented: $showingNewSection) {
                TextField("שם המחלקה", text: $sectionName)
                Button("יצירה") {
                    store.addSection(sectionName)
                    groupBySection = true
                }
                Button("ביטול", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
    }

    private var listPicker: some View {
        Menu {
            ForEach(store.data.lists) { list in
                Button(list.name, systemImage: list.id == store.selectedListID ? "checkmark" : "list.bullet") {
                    store.selectList(list.id)
                    collapsedSections.removeAll()
                    isAdding = false
                }
            }
            Divider()
            Button("רשימה חדשה לחנות", systemImage: "plus") {
                listName = ""; showingNewList = true
            }
            Button("שינוי שם הרשימה", systemImage: "pencil") {
                listName = store.currentList.name; showingRenameList = true
            }
        } label: {
            Image(systemName: "chevron.down.circle")
                .font(.title3)
        }
        .accessibilityLabel("בחירת חנות, \(store.currentList.name)")
    }

    private var optionsMenu: some View {
        Menu {
            Button(groupBySection ? "הצגה לפי מסלול הקנייה" : "קיבוץ לפי מחלקות",
                   systemImage: "square.stack") { groupBySection.toggle() }
            Button("מחלקה חדשה", systemImage: "plus.rectangle.on.rectangle") {
                sectionName = ""; showingNewSection = true
            }
            Button("היסטוריית קניות", systemImage: "clock") { showingHistory = true }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
        .accessibilityLabel("אפשרויות נוספות")
    }

    private var sectionNames: [String] {
        let existing = store.currentList.sections
        let used = store.items.compactMap { store.product(for: $0.productID)?.department }
        let names = existing + used.filter { !existing.contains($0) }
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        return store.items.contains(where: { store.product(for: $0.productID)?.department == nil })
            ? unique + ["אחר"] : unique
    }

    private func items(in section: String) -> [ShoppingItem] {
        store.items.filter { (store.product(for: $0.productID)?.department ?? "אחר") == section }
    }

    private func sectionHeader(_ section: String) -> some View {
        Button {
            if !collapsedSections.insert(section).inserted { collapsedSections.remove(section) }
        } label: {
            HStack {
                Text(section).font(.headline).foregroundStyle(Theme.accent)
                Text("\(items(in: section).count)").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: collapsedSections.contains(section) ? "chevron.left" : "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            store.move(id, toSection: section)
            collapsedSections.remove(section)
            return true
        }
    }

    @ViewBuilder
    private func itemRow(_ item: ShoppingItem) -> some View {
        if let product = store.product(for: item.productID) {
            VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if reduceMotion { store.buy(item) }
                    else { withAnimation(.smooth) { store.buy(item) } }
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 24, weight: .light))
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("נקנה \(product.name)")
                VStack(alignment: .leading, spacing: 2) {
                    if editingNameID == item.id {
                        TextField("שם המוצר", text: $editedName)
                            .focused($nameFocused, equals: item.id)
                            .submitLabel(.done)
                            .onSubmit { finishRename(item) }
                    } else {
                        Button {
                            editedName = product.name
                            editingNameID = item.id
                            nameFocused = item.id
                        } label: {
                            HStack(spacing: 6) {
                                Text(product.name).foregroundStyle(.primary)
                                if item.isUrgent {
                                    Image(systemName: "flag.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("דחוף")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let category = product.category {
                        Text(category).font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = item.note, !note.isEmpty, expandedItemID != item.id {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if item.photoFilename != nil, expandedItemID != item.id {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
                Button("×\(item.quantity)") {
                    expandedItemID = expandedItemID == item.id ? nil : item.id
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.bordered)
                .accessibilityLabel("עריכת כמות והערות עבור \(product.name)")
                .accessibilityValue("כמות \(item.quantity)")
            }
            if expandedItemID == item.id {
                ItemInlineDetails(store: store, item: item)
                    .padding(.leading, 42)
            }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(item.isUrgent ? "הסר דגל" : "דחוף",
                       systemImage: item.isUrgent ? "flag.slash" : "flag") {
                    store.toggleUrgent(item)
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("הסר", systemImage: "trash", role: .destructive) { store.remove(item) }
                Button("פרטים", systemImage: "slider.horizontal.3") { editingCategory = product }
                    .tint(Theme.accent)
            }
            .contextMenu {
                Button("כמות, הערה ותמונה", systemImage: "square.and.pencil") { expandedItemID = item.id }
                Button("מחלקה וקטגוריה", systemImage: "square.grid.2x2") { editingCategory = product }
                Button(item.isUrgent ? "הסר דגל דחוף" : "סמן כדחוף", systemImage: "flag") {
                    store.toggleUrgent(item)
                }
                Button("הסר", systemImage: "trash", role: .destructive) { store.remove(item) }
            }
            .draggable(item.id.uuidString)
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                store.move(id, before: item.id, grouping: groupBySection)
                return true
            }
        }
    }

    private func suggestionSection(_ title: String, items: [Suggestion]) -> some View {
        Section(title) {
            ForEach(items) { suggestion in
                HStack(spacing: 12) {
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.tertiary)
                        .frame(width: 30)
                    VStack(alignment: .leading) {
                        Text(suggestion.product.name)
                        if suggestion.quantity > 1 {
                            Text("בדרך כלל ×\(suggestion.quantity)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        store.add(suggestion)
                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel("הוספת \(suggestion.product.name) לרשימה")
                }
                .swipeActions(edge: .trailing) {
                    Button("לא עכשיו", systemImage: "clock") { store.deferSuggestion(suggestion) }
                }
            }
        }
    }

    private func addInline() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(name: trimmed, quantity: 1)
        newName = ""
        addFocused = true
    }

    private func finishRename(_ item: ShoppingItem) {
        store.rename(item, to: editedName)
        editingNameID = nil
    }
}

private struct ItemInlineDetails: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var note: String

    init(store: ShoppingStore, item: ShoppingItem) {
        self.store = store
        self.item = item
        _note = State(initialValue: item.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    store.updateQuantity(of: item, to: max(1, item.quantity - 1))
                } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    .disabled(item.quantity <= 1)
                    .accessibilityLabel("הפחתת כמות")
                Text("\(item.quantity)").monospacedDigit().font(.headline)
                    .accessibilityIdentifier("inlineQuantity")
                Button {
                    store.updateQuantity(of: item, to: min(9999, item.quantity + 1))
                } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(item.quantity >= 9999)
                    .accessibilityLabel("הגדלת כמות")
            }
            TextField("הערה למוצר…", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .onChange(of: note) { _, value in store.updateNote(of: item, to: value) }
                .accessibilityIdentifier("itemNoteField")
            HStack {
                if let url = store.photoURL(for: item), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 9))
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(item.photoFilename == nil ? "צירוף תמונה" : "החלפת תמונה", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .onChange(of: selectedPhoto) { _, selection in
                    guard let selection else { return }
                    Task {
                        if let data = try? await selection.loadTransferable(type: Data.self) {
                            store.setPhoto(data, for: item)
                        }
                    }
                }
                if item.photoFilename != nil {
                    Button("הסרת תמונה", systemImage: "xmark.circle") {
                        store.removePhoto(from: item)
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
    }
}
