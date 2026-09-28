import SwiftUI
import UIKit
import PhotosUI

struct ShoppingView: View {
    @StateObject private var store = ShoppingStore()
    @State private var isAdding = false
    @State private var addingToSection: String?
    @State private var newName = ""
    @State private var editedName = ""
    @State private var expandedItemID: UUID?
    @State private var editingCategory: ShoppingItem?
    @State private var editingNameID: UUID?
    @State private var showingHistory = false
    @State private var showingNewList = false
    @State private var showingRenameList = false
    @State private var showingNewSection = false
    @State private var showingAppearance = false
    @State private var reordering = false
    @State private var listName = ""
    @State private var sectionName = ""
    @State private var collapsedSections: Set<String> = []
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var editMode: EditMode = .inactive
    @FocusState private var addFocused: Bool
    @FocusState private var nameFocused: UUID?
    @AppStorage("groupShoppingByCategory") private var groupBySection = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var likely: [Suggestion] { store.suggestions.filter { $0.tier == .likely } }
    private var maybe: [Suggestion] { store.suggestions.filter { $0.tier == .maybe } }
    private var listTint: Color { Theme.tint(for: store.currentList.tintName) }
    private var showsSections: Bool {
        groupBySection && (!store.currentList.sections.isEmpty || store.items.contains {
            store.section(for: $0) != "אחר"
        })
    }
    private var selectionFullyUrgent: Bool {
        !selectedItemIDs.isEmpty && store.items.filter { selectedItemIDs.contains($0.id) }.allSatisfy(\.isUrgent)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List(selection: reordering ? nil : $selectedItemIDs) {
                    if showsSections {
                        ForEach(sectionNames, id: \.self) { section in
                            Section {
                                if !collapsedSections.contains(section) {
                                    ForEach(items(in: section)) { item in
                                        itemRow(item)
                                            .moveDisabled(!reordering)
                                            .listRowSeparator(.hidden, edges: .all)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                            .listRowBackground(Color.clear)
                                    }
                                    .onMove { source, destination in
                                        store.move(from: source, to: destination, inSection: section)
                                    }
                                }
                            } header: {
                                sectionHeader(section)
                            }
                            .listSectionSeparator(.hidden, edges: .all)
                        }
                    } else {
                        Section {
                            ForEach(store.items) { item in
                                itemRow(item)
                                    .moveDisabled(!reordering)
                                    .listRowSeparator(.hidden, edges: .all)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .listRowBackground(Color.clear)
                            }
                            .onMove { source, destination in
                                store.move(from: source, to: destination, inSection: nil)
                            }
                        }
                        .listSectionSeparator(.hidden, edges: .all)
                    }

                    if isAdding {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "circle")
                                    .font(.title2.weight(.ultraLight))
                                    .foregroundStyle(listTint)
                                    .frame(width: 28)
                                TextField(addingToSection.map { "מוצר ל\($0)" } ?? "מה צריך לקנות?", text: $newName)
                                    .focused($addFocused)
                                    .submitLabel(.next)
                                    .onSubmit(addInline)
                                    .onChange(of: newName) { _, value in
                                        if value.contains("\n") { addInline() }
                                    }
                                    .accessibilityIdentifier("inlineAddField")
                            }
                            .id("new-item")
                            .selectionDisabled(true)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                        .listSectionSeparator(.hidden)
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
                                    .listRowSeparator(.hidden)
                                    .selectionDisabled(true)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                }
                            }
                            Button("לכל הקניות") { showingHistory = true }
                                .font(.subheadline)
                                .listRowSeparator(.hidden)
                                .selectionDisabled(true)
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden, edges: .all)
                .listSectionSeparator(.hidden, edges: .all)
                .overlay {
                    TwoFingerSelectionGesture { from, to in
                        guard !reordering else { return }
                        let crossed = store.items.compactMap { item -> UUID? in
                            guard let frame = itemFrames[item.id],
                                  frame.minY <= max(from.y, to.y),
                                  frame.maxY >= min(from.y, to.y),
                                  frame.minX <= to.x, frame.maxX >= to.x else { return nil }
                            return item.id
                        }
                        guard !crossed.isEmpty else { return }
                        if !editMode.isEditing {
                            addFocused = false
                            editMode = .active
                        }
                        selectedItemIDs.formUnion(crossed)
                    }
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
                .environment(\.editMode, $editMode)
                .listRowSpacing(0)
                .listSectionSpacing(0)
                .environment(\.defaultMinListRowHeight, 44)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack {
                        if reordering {
                            Text("גרור את ידיות הסידור של המוצרים")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                        } else if editMode.isEditing {
                            Text("\(selectedItemIDs.count) נבחרו")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(selectionFullyUrgent ? "הסר דגל" : "דגל",
                                   systemImage: selectionFullyUrgent ? "flag.slash" : "flag.fill") {
                                store.setUrgent(!selectionFullyUrgent, for: selectedItemIDs)
                                selectedItemIDs.removeAll()
                                editMode = .inactive
                            }
                            .disabled(selectedItemIDs.isEmpty)
                            Button("מחיקה", systemImage: "trash", role: .destructive) {
                                withAnimation(.smooth) { store.remove(selectedItemIDs) }
                                selectedItemIDs.removeAll()
                                editMode = .inactive
                            }
                            .disabled(selectedItemIDs.isEmpty)
                        } else {
                            Button {
                                addingToSection = nil
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
                if editMode.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("סיום") {
                            selectedItemIDs.removeAll()
                            reordering = false
                            editMode = .inactive
                        }
                    }
                }
            }
            .sheet(item: $editingCategory) { CategoryEditor(store: store, item: $0) }
            .sheet(isPresented: $showingAppearance) { ListAppearanceEditor(store: store) }
            .onChange(of: editMode) { _, mode in
                if !mode.isEditing {
                    selectedItemIDs.removeAll()
                    reordering = false
                }
            }
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
            .alert("מקטע חדש", isPresented: $showingNewSection) {
                TextField("שם המקטע", text: $sectionName)
                Button("יצירה") {
                    store.addSection(sectionName)
                    groupBySection = true
                }
                Button("ביטול", role: .cancel) {}
            }
        }
        .tint(listTint)
        .task { store.cloudSync.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.cloudSync.start() }
        }
    }

    private var listPicker: some View {
        Menu {
            ForEach(store.data.lists) { list in
                Button(list.name, systemImage: list.symbolName) {
                    store.selectList(list.id)
                    collapsedSections.removeAll()
                    isAdding = false
                    addingToSection = nil
                    selectedItemIDs.removeAll()
                    itemFrames.removeAll()
                    reordering = false
                    editMode = .inactive
                }
            }
            Divider()
            Button("רשימה חדשה לחנות", systemImage: "plus") {
                listName = ""; showingNewList = true
            }
            Button("שינוי שם הרשימה", systemImage: "pencil") {
                listName = store.currentList.name; showingRenameList = true
            }
            Button("צבע וסמל הרשימה", systemImage: "paintpalette") { showingAppearance = true }
        } label: {
            Image(systemName: store.currentList.symbolName)
                .font(.title3)
        }
        .accessibilityLabel("בחירת חנות, \(store.currentList.name)")
    }

    private var optionsMenu: some View {
        Menu {
            Button(groupBySection ? "הצגה לפי מסלול הקנייה" : "הצגת מקטעים",
                   systemImage: "square.stack") { groupBySection.toggle() }
            Button("מקטע חדש", systemImage: "plus.rectangle.on.rectangle") {
                sectionName = ""; showingNewSection = true
            }
            Button("סידור מוצרים", systemImage: "line.3.horizontal") {
                addFocused = false
                isAdding = false
                addingToSection = nil
                newName = ""
                selectedItemIDs.removeAll()
                reordering = true
                editMode = .active
            }
            Button("היסטוריית קניות", systemImage: "clock") { showingHistory = true }
            Button("בחירת פריטים", systemImage: "checkmark.circle") {
                addFocused = false
                reordering = false
                editMode = .active
            }
            Divider()
            Button(syncLabel, systemImage: "arrow.triangle.2.circlepath.icloud") {
                Task { await store.cloudSync.synchronize() }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
        .accessibilityLabel("אפשרויות נוספות")
    }

    private var syncLabel: String {
        switch store.syncStatus {
        case .local: return "סנכרון iCloud"
        case .syncing: return "מסנכרן עם iCloud…"
        case .current: return "iCloud מעודכן"
        case .unavailable: return "iCloud אינו זמין — נסה שוב"
        case .accountChanged: return "חשבון iCloud השתנה — הנתונים נשמרו במכשיר"
        case .failed: return "הסנכרון ממתין לחיבור — נסה שוב"
        }
    }

    private var sectionNames: [String] {
        let existing = store.currentList.sections
        let used = store.items.map { store.section(for: $0) }.filter { $0 != "אחר" }
        let names = existing + used.filter { !existing.contains($0) }
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        return store.items.contains(where: { store.section(for: $0) == "אחר" })
            ? unique + ["אחר"] : unique
    }

    private func items(in section: String) -> [ShoppingItem] {
        store.items.filter { store.section(for: $0) == section }
    }

    private func sectionHeader(_ section: String) -> some View {
        HStack {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
                    if !collapsedSections.insert(section).inserted { collapsedSections.remove(section) }
                }
            } label: {
                HStack {
                    Image(systemName: collapsedSections.contains(section) ? "chevron.left" : "chevron.down")
                        .font(.caption.weight(.semibold))
                    Text(section).font(.headline).foregroundStyle(listTint)
                    Text("\(items(in: section).count)").foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(section), \(items(in: section).count) מוצרים")
            .accessibilityHint(collapsedSections.contains(section) ? "הרחבת מקטע" : "צמצום מקטע")
            Button {
                addingToSection = section == "אחר" ? nil : section
                isAdding = true
                addFocused = true
            } label: {
                Image(systemName: "plus.circle")
            }
            .accessibilityLabel("הוספת מוצר למקטע \(section)")
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func itemRow(_ item: ShoppingItem) -> some View {
        if let product = store.product(for: item.productID) {
            VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if !editMode.isEditing {
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
                }
                VStack(alignment: .leading, spacing: 2) {
                    if editingNameID == item.id {
                        TextField("שם המוצר", text: $editedName)
                            .focused($nameFocused, equals: item.id)
                            .submitLabel(.done)
                            .onSubmit { finishRename(item) }
                    } else if editMode.isEditing {
                        HStack(spacing: 6) {
                            Text(product.name).foregroundStyle(.primary)
                            if item.isUrgent {
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("דחוף")
                            }
                        }
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
                if editMode.isEditing {
                    Text("×\(item.quantity) \(item.unit ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                Button("×\(item.quantity) \(item.unit ?? "")") {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                        expandedItemID = expandedItemID == item.id ? nil : item.id
                    }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.bordered)
                .accessibilityLabel("עריכת כמות והערות עבור \(product.name)")
                .accessibilityValue("כמות \(item.quantity) \(item.unit ?? "")")
                }
            }
            if expandedItemID == item.id && !editMode.isEditing {
                ItemInlineDetails(store: store, item: item)
                    .padding(.leading, 42)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(item.isUrgent ? "הסר דגל" : "דחוף",
                       systemImage: item.isUrgent ? "flag.slash" : "flag") {
                    store.toggleUrgent(item)
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("הסר", systemImage: "trash", role: .destructive) { store.remove(item) }
                Button("פרטים", systemImage: "slider.horizontal.3") { editingCategory = item }
                    .tint(listTint)
            }
            .contextMenu {
                Button("כמות, הערה ותמונה", systemImage: "square.and.pencil") { expandedItemID = item.id }
                Button("מקטע וקטגוריה", systemImage: "square.grid.2x2") { editingCategory = item }
                if !store.currentList.sections.isEmpty {
                    Menu("העבר למקטע", systemImage: "square.stack") {
                        ForEach(store.currentList.sections, id: \.self) { section in
                            Button(section) { store.move(item.id, toSection: section) }
                        }
                        Button("ללא מקטע") { store.move(item.id, toSection: "אחר") }
                    }
                }
                Button(item.isUrgent ? "הסר דגל דחוף" : "סמן כדחוף", systemImage: "flag") {
                    store.toggleUrgent(item)
                }
                Button("הסר", systemImage: "trash", role: .destructive) { store.remove(item) }
            }
            .tag(item.id)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { _, frame in
                itemFrames[item.id] = frame
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
                        if suggestion.quantity > 1 || suggestion.product.preferredUnit != nil {
                            Text("בדרך כלל ×\(suggestion.quantity) \(suggestion.product.preferredUnit ?? "")")
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
                .listRowSeparator(.hidden)
                .selectionDisabled(true)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
        .listSectionSeparator(.hidden)
    }

    private func addInline() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(name: trimmed, quantity: 1, department: addingToSection)
        newName = ""
        addFocused = true
    }

    private func finishRename(_ item: ShoppingItem) {
        store.rename(item, to: editedName)
        editingNameID = nil
    }
}

private struct ItemInlineDetails: View {
    private static let commonUnits = ["יחידות", "חבילות", "ליטרים", "מ״ל", "ק״ג", "גרם", "בקבוקים", "קופסאות", "שקיות", "גלילים"]
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var note: String
    @State private var customUnit = ""
    @State private var editingCustomUnit = false
    @FocusState private var customUnitFocused: Bool

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
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("inlineQuantity")
                Button {
                    store.updateQuantity(of: item, to: min(9999, item.quantity + 1))
                } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(item.quantity >= 9999)
                    .accessibilityLabel("הגדלת כמות")
                Menu {
                    Button("ללא יחידה") { store.updateUnit(of: item, to: nil) }
                    ForEach(Self.commonUnits, id: \.self) { unit in
                        Button(unit) { store.updateUnit(of: item, to: unit) }
                    }
                    Button("יחידה אחרת…", systemImage: "pencil") {
                        customUnit = item.unit ?? ""
                        editingCustomUnit = true
                        customUnitFocused = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.unit ?? "יחידת מידה")
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(item.unit == nil ? .secondary : .primary)
                }
                .accessibilityLabel("בחירת יחידת מידה")
                .accessibilityValue(item.unit ?? "ללא יחידה")
            }
            if editingCustomUnit {
                HStack {
                    TextField("שם היחידה", text: $customUnit)
                        .focused($customUnitFocused)
                        .submitLabel(.done)
                        .onSubmit(saveCustomUnit)
                        .accessibilityIdentifier("customUnitField")
                    Button("שמירה", action: saveCustomUnit)
                }
                .transition(.opacity)
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

    private func saveCustomUnit() {
        store.updateUnit(of: item, to: customUnit)
        editingCustomUnit = false
    }
}
