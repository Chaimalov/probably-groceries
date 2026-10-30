import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

struct ShoppingView: View {
    @ObservedObject var store: ShoppingStore
    @State private var showingSharing = false
    @State private var sharingListID: UUID?
    @State private var isAdding = false
    @State private var addingToSection: String?
    @State private var addingAfterID: UUID?
    @State private var composerSection: String?
    @State private var newName = ""
    @State private var newQuantity = 1
    @State private var preserveRawInput = false
    @State private var newQuantityOverridden = false
    @State private var editedName = ""
    @State private var quantityExpanded = false
    @State private var newUnit: String?
    @State private var newNote = ""
    @State private var newUrgent = false
    @State private var newPhotoData: Data?
    @State private var newPhoto: PhotosPickerItem?
    @State private var showingNewNote = false
    @State private var originalEditedName = ""
    @State private var editingCategory: ShoppingItem?
    @State private var editingNameID: UUID?
    @State private var showingHistory = false
    @State private var showingPreparation = false
    @State private var showingSettings = false
    @State private var shareAfterSettings = false
    @State private var confirmingDeleteList = false
    @State private var deletingListID: UUID?
    @State private var detailItem: ShoppingItem?
    @State private var placeFilter = "הכול"
    @State private var presentation = ShoppingPresentation()
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var searchReturnID: UUID?
    @State private var showingListDetails = false
    @State private var showingSectionManagement = false
    @AppStorage("collapsedShoppingSections") private var savedCollapsedSections = "{}"
    @AppStorage("shoppingHapticsEnabled") private var hapticsEnabled = true
    @State private var showingNewList = false
    @State private var showingNewSection = false
    @State private var editingSection: String?
    @State private var showingSectionEditor = false
    @State private var clarificationItem: ShoppingItem?
    @State private var reordering = false
    @State private var listName = ""
    @State private var sectionName = ""
    @State private var collapsedSections: Set<String> = []
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var itemFrames = ShoppingItemFrameRegistry()
    @State private var editMode: EditMode = .inactive
    @FocusState private var addFocused: Bool
    @FocusState private var nameFocused: UUID?
    @AppStorage("groupShoppingByCategory") private var groupBySection = true
    @AppStorage("showRecentPurchases") private var showRecentPurchases = true
    @Environment(\.undoManager) private var undoManager
    @AppStorage("showProductCompletions") private var showProductCompletions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    private var listTint: Color { Theme.tint(for: store.currentList.tintName) }
    private var showsSections: Bool {
        groupBySection
    }
    private var selectionFullyUrgent: Bool {
        !selectedItemIDs.isEmpty && store.items.filter { selectedItemIDs.contains($0.id) }.allSatisfy(\.isUrgent)
    }

    private var displayItems: [ShoppingItem] {
        presentation.rows(active: store.items, purchases: store.purchases, listID: store.selectedListID)
    }

    private var visibleItems: [ShoppingItem] {
        displayItems.filter { item in
            let matchesPlace = placeFilter == "הכול" || (placeFilter == "ללא מקום" ? item.shoppingPlace == nil : item.shoppingPlace == placeFilter)
            let matchesSearch = searchText.isEmpty || [store.product(for: item.productID)?.name, item.note, store.section(for: item)]
                .compactMap { $0 }.contains { $0.localizedStandardContains(searchText) }
            return matchesPlace && matchesSearch
        }
    }

    private var recentPurchases: [Purchase] {
        let inlineIDs = Set(displayItems.map(\.id))
        return store.recentPurchases.filter { !inlineIDs.contains($0.sourceItemID) }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    listSidebar
                } detail: {
                    shoppingContent
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                shoppingContent
            }
        }
    }

    private var listSidebar: some View {
        List {
            Section("הרשימות שלנו") {
                ForEach(store.data.lists) { list in
                    Button { switchList(to: list.id) } label: {
                        HStack {
                            Label(list.name, systemImage: list.symbolName)
                            Spacer()
                            if list.id == store.selectedListID {
                                Image(systemName: "checkmark").accessibilityLabel("הרשימה הנוכחית")
                            }
                        }
                    }
                    .listRowBackground(list.id == store.selectedListID ? listTint.opacity(0.12) : Color.clear)
                }
            }
            Button("רשימה חדשה לחנות", systemImage: "plus") {
                listName = ""; showingNewList = true
            }
        }
        .navigationTitle("קניות")
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        .tint(listTint)
    }

    private var shoppingContent: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List(selection: reordering ? nil : $selectedItemIDs) {
                    if displayItems.isEmpty && !isAdding && !reordering && searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("הרשימה פנויה")
                                .font(.title3.weight(.semibold))
                            Text("אפשר להוסיף מוצר או להכין את הקנייה הבאה.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .selectionDisabled(true)
                    }
                    if let error = store.storageError {
                        Section {
                            Text(LocalizedStringKey(error)).foregroundStyle(.red)
                            Button("ניסיון שמירה נוסף") { store.retryLocalSave() }
                        }
                    }
                    if let binding = store.currentShare, !binding.accessible {
                        Section {
                            Label(binding.accessible ? "שיתוף דרך iCloud" : "השיתוף אינו זמין — השינויים נשמרים במכשיר",
                                  systemImage: binding.accessible ? "person.2" : "icloud.slash")
                                .font(.caption).foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                                .selectionDisabled(true)
                        }
                        .listSectionSeparator(.hidden)
                    }
                    if !Set(store.items.compactMap(\.shoppingPlace)).isEmpty {
                        Picker("מקום קנייה", selection: $placeFilter) {
                            Text("הכול").tag("הכול")
                            Text("ללא מקום").tag("ללא מקום")
                            ForEach(Array(Set(store.items.compactMap(\.shoppingPlace))).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if showsSections {
                        ForEach(sectionNames, id: \.self) { section in
                            Section {
                                sectionHeader(section)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .selectionDisabled(true)
                                    .background {
                                        nativeDrag(.section(section), section: section)
                                    }
                                if !collapsedSections.contains(section) {
                                    ForEach(items(in: section)) { item in
                                        itemRow(item)
                                    .listRowBackground(Theme.canvas)
                                            .moveDisabled(!reordering)
                                            .listRowSeparator(.hidden, edges: .all)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                        if isAdding && composerSection == section && addingAfterID == item.id {
                                            inlineAddRow
                                        }
                                    }
                                    .onMove { source, destination in
                                        store.move(from: source, to: destination, inSection: section)
                                    }
                                    if isAdding && composerSection == section && !items(in: section).contains(where: { $0.id == addingAfterID }) {
                                        inlineAddRow
                                    }
                                    if !isAdding && editingNameID == nil && !editMode.isEditing && searchText.isEmpty {
                                        sectionAddRow(section, scroll: scroll)
                                    }
                                }
                            }
                            .listSectionSeparator(.hidden, edges: .all)
                        }
                    } else {
                        Section {
                            ForEach(visibleItems) { item in
                                itemRow(item)
                                    .listRowBackground(Theme.canvas)
                                    .moveDisabled(!reordering)
                                    .listRowSeparator(.hidden, edges: .all)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                if isAdding && addingAfterID == item.id { inlineAddRow }
                            }
                            .onMove { source, destination in
                                store.move(from: source, to: destination, inSection: nil)
                            }
                        }
                        .listSectionSeparator(.hidden, edges: .all)
                    }

                    if isAdding && (showsSections ? composerSection == nil : !visibleItems.contains(where: { $0.id == addingAfterID })) {
                        Section { inlineAddRow }
                            .listSectionSeparator(.hidden)
                    }



                    if showRecentPurchases && !recentPurchases.isEmpty && searchText.isEmpty {
                        Section("נקנו לאחרונה") {
                            ForEach(recentPurchases) { purchase in
                                if let product = store.product(for: purchase.productID) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                        Text(product.name).foregroundStyle(.secondary)
                                        Text(quantityLabel(purchase.quantity, unit: purchase.unit))
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                            .accessibilityLabel("כמות \(purchase.quantity) \(purchase.unit ?? "")")
                                        Spacer()
                                        Button {
                                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                                store.undo(purchase, undoManager: undoManager)
                                            }
                                        } label: {
                                            Image(systemName: "arrow.uturn.backward")
                                                .frame(minWidth: 44, minHeight: 44)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("ביטול")
                                        .accessibilityHint("ביטול הקנייה של \(product.name)")
                                    }
                                    .swipeActions {
                                        Button("ביטול קנייה", systemImage: "arrow.uturn.backward") {
                                            store.undo(purchase, undoManager: undoManager)
                                        }
                                        .labelStyle(.iconOnly)
                                        .tint(Color(uiColor: .systemBlue))
                                    }
                                    .listRowSeparator(.hidden)
                                    .selectionDisabled(true)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                }
                            }
                            Button("לכל הקניות", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .listRowSeparator(.hidden)
                                .selectionDisabled(true)
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: sizeClass == .regular ? 680 : .infinity)
                .frame(maxWidth: .infinity)
                .background { Theme.canvas.ignoresSafeArea() }
                .listRowSeparator(.hidden, edges: .all)
                .listSectionSeparator(.hidden, edges: .all)
                .overlay {
                    TwoFingerSelectionGesture { from, to in
                        guard !reordering else { return }
                        let crossed = store.items.compactMap { item -> UUID? in
                            guard let frame = itemFrames.frames[item.id],
                                  frame.minY <= max(from.y, to.y),
                                  frame.maxY >= min(from.y, to.y),
                                  frame.minX <= to.x, frame.maxX >= to.x else { return nil }
                            return item.id
                        }
                        guard !crossed.isEmpty else { return }
                        if !editMode.isEditing {
                            closeEditor()
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
                .environment(\.defaultMinListRowHeight, 52)
                .environment(\.defaultMinListHeaderHeight, 0)
                .scrollDismissesKeyboard(.interactively)
                .inspector(isPresented: Binding(
                    get: { detailItem != nil },
                    set: { if !$0 { detailItem = nil } }
                )) {
                    if let detailItem {
                        ItemDetailsSheet(store: store, item: detailItem, onClose: { self.detailItem = nil })
                            .id(detailItem.id)
                            .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
                    }
                }
                .toolbar { bottomActions(scroll) }
                .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                    if !editMode.isEditing && !isAdding && editingNameID == nil && !showingSearch {
                        HStack {
                            Spacer()
                            Button("מוצר חדש", systemImage: "plus") { startAdding(scroll: scroll) }
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .frame(minWidth: 44, minHeight: 44)
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.circle)
                                .tint(listTint)
                                .accessibilityLabel("הוספת מוצר")
                                .keyboardShortcut("n", modifiers: .command)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
                .searchable(text: $searchText, isPresented: $showingSearch, placement: .automatic, prompt: "חיפוש")
                .onChange(of: showingSearch) { _, searching in
                    if searching {
                        searchReturnID = itemFrames.frames.filter { $0.value.maxY > 160 }
                            .min { $0.value.minY < $1.value.minY }?.key
                        closeEditor()
                    } else {
                        searchText = ""
                        if let searchReturnID {
                            Task { @MainActor in
                                await Task.yield()
                                scroll.scrollTo(searchReturnID, anchor: .top)
                            }
                        }
                    }
                }
                .task(id: addingAfterID) {
                    guard isAdding, addingAfterID != nil else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    // The native List keeps the focused row above the keyboard.
                    // Re-centering after every Return fights that adjustment.
                    addFocused = true
                }
                .task(id: store.widgetNavigation?.id) {
                    guard let request = store.widgetNavigation else { return }
                    // Resolve after list-switch handlers have finished, including cold launches.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    defer {
                        if store.widgetNavigation?.id == request.id { store.widgetNavigation = nil }
                    }
                    closeEditor()
                    placeFilter = "הכול"
                    editMode = .inactive
                    reordering = false
                    if let id = request.itemID,
                       let item = store.items.first(where: { $0.id == id }),
                       let product = store.product(for: item.productID) {
                        collapsedSections.remove(store.section(for: item))
                        updateEditor {
                            editedName = product.name
                            originalEditedName = product.name
                            editingNameID = item.id
                            quantityExpanded = true
                            nameFocused = item.id
                        }
                        await Task.yield()
                        scroll.scrollTo(item.id, anchor: .center)
                    } else if request.itemID == nil {
                        beginAdding()
                        addFocused = true
                    }
                }

            }
            .navigationTitle(store.currentList.name)
            .navigationBarTitleDisplayMode(.large)
            .background(ShoppingNavigationTitleTint(color: UIColor(listTint)))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { listPicker.tint(listTint) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("שיתוף הרשימה", systemImage: "person.2") { openSharing() }
                        .labelStyle(.iconOnly)
                        #if targetEnvironment(simulator)
                        .disabled(true)
                        #endif
                    optionsMenu
                    if !isAdding && editingNameID == nil {
                        Button("חיפוש", systemImage: "magnifyingglass") { showingSearch = true }
                            .labelStyle(.iconOnly)
                    }
                }
                if !editMode.isEditing && (isAdding || editingNameID != nil) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("סיום עריכה", systemImage: "checkmark") { closeEditor() }
                            .labelStyle(.iconOnly)
                            .keyboardShortcut(.return, modifiers: .command)
                            .tint(listTint)
                    }
                }
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
            .onChange(of: store.items) { oldItems, items in
                let currentIDs = Set(items.map(\.id))
                let purchasedIDs = Set(store.purchases.map(\.sourceItemID))
                let previousRows = presentation.rows(active: oldItems, purchases: store.purchases, listID: store.selectedListID)
                for item in oldItems where !currentIDs.contains(item.id) && purchasedIDs.contains(item.id) {
                    presentation.retain(item, among: previousRows)
                }
                if placeFilter != "הכול" && placeFilter != "ללא מקום" && !items.contains(where: { $0.shoppingPlace == placeFilter }) { placeFilter = "הכול" }
            }
            .onChange(of: nameFocused) { oldID, newID in
                if oldID != newID, let oldID, editingNameID == oldID,
                   let item = store.items.first(where: { $0.id == oldID }) {
                    saveRename(item)
                }
            }
            .onChange(of: store.items.map(\.id)) { _, ids in
                if let editingNameID, !ids.contains(editingNameID) {
                    updateEditor { self.editingNameID = nil; nameFocused = nil }
                }
            }
            .sheet(isPresented: $showingListDetails) { ListAppearanceEditor(store: store) }
            .sheet(isPresented: $showingSectionManagement) {
                NavigationStack {
                    SectionSettingsView(store: store)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { showingSectionManagement = false } } }
                }
            }
            .onAppear { restoreCollapsedSections() }
            .onChange(of: collapsedSections) { _, _ in persistCollapsedSections() }
            .sheet(isPresented: $showingSectionEditor) {
                if let editingSection { SectionEditor(store: store, section: editingSection) }
            }
            .sheet(item: $clarificationItem) { ClarificationView(store: store, item: $0) }
            .sheet(item: $editingCategory) { CategoryEditor(store: store, item: $0) }
            .onChange(of: editMode) { _, mode in
                if !mode.isEditing {
                    selectedItemIDs.removeAll()
                    reordering = false
                }
            }
            .sheet(isPresented: $showingPreparation) { ShoppingPreparationView(store: store) }
            .sheet(isPresented: $showingHistory) { PurchaseHistoryView(store: store) }
            .sheet(isPresented: $showingSettings, onDismiss: {
                if shareAfterSettings {
                    shareAfterSettings = false
                    sharingListID = store.selectedListID
                    showingSharing = true
                }
            }) {
                SettingsView(store: store) { shareAfterSettings = true }
            }
            .onChange(of: store.selectedListID) { _, _ in
                undoManager?.removeAllActions(withTarget: store)
                presentation.reset()
                restoreCollapsedSections()
                searchText = ""
                showingSearch = false
                placeFilter = "הכול"
                selectedItemIDs.removeAll()
            }
            .confirmationDialog("למחוק את הרשימה ״\(store.currentList.name)״?", isPresented: $confirmingDeleteList, titleVisibility: .visible) {
                Button("מחיקת הרשימה", role: .destructive) {
                    guard deletingListID == store.selectedListID else { return }
                    store.deleteCurrentList()
                }
            } message: {
                Text(LocalizedStringKey(store.currentShare == nil
                     ? "הרשימה, הפריטים והיסטוריית הקניות שלה יימחקו מכל המכשירים שלך."
                     : "הרשימה, הפריטים והיסטוריית הקניות שלה יימחקו גם אצל מי ששותף בה."))
            }
            .alert("רשימה חדשה לחנות", isPresented: $showingNewList) {
                TextField("שם החנות", text: $listName)
                Button("יצירה") { closeEditor(); store.addList(name: listName) }
                Button("ביטול", role: .cancel) {}
            }
            .alert("מקטע חדש", isPresented: $showingNewSection) {
                TextField("שם המקטע", text: $sectionName)
                Button("יצירה") {
                    closeEditor()
                    store.addSection(sectionName)
                    groupBySection = true
                    selectedItemIDs.removeAll()
                }
                Button("ביטול", role: .cancel) {}
            }
        }
        .tint(Color(uiColor: .label))
        .sheet(isPresented: $showingSharing) {
            if let listID = sharingListID { ListSharingSheet(store: store, listID: listID) }
        }
        .task {
            #if !targetEnvironment(simulator)
            store.cloudSync.start()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { presentation.reset() }
            #if !targetEnvironment(simulator)
            if phase == .active { store.cloudSync.start() }
            #endif
        }
        .task(id: scenePhase) {
            #if !targetEnvironment(simulator)
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if !store.sharedLists.isEmpty { await store.cloudSync.synchronize() }
            }
            #endif
        }
    }

    @ToolbarContentBuilder
    private func bottomActions(_ scroll: ScrollViewProxy) -> some ToolbarContent {
if reordering {
                        ToolbarItem(placement: .bottomBar) {
                            Text("גרור את ידיות הסידור של המוצרים")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if editMode.isEditing {
                        ToolbarItem(placement: .bottomBar) {
                            Text("\(selectedItemIDs.count) נבחרו")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button(selectionFullyUrgent ? "הסר דגל" : "דגל",
                                   systemImage: selectionFullyUrgent ? "flag.slash" : "flag.fill") {
                                store.setUrgent(!selectionFullyUrgent, for: selectedItemIDs)
                                selectedItemIDs.removeAll()
                                editMode = .inactive
                            }
                            .disabled(selectedItemIDs.isEmpty)
                            Button("מחיקה", systemImage: "trash", role: .destructive) {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { store.remove(selectedItemIDs, undoManager: undoManager) }
                                selectedItemIDs.removeAll()
                                editMode = .inactive
                            }
                            .disabled(selectedItemIDs.isEmpty)
                        }
                    }
    }

    private func startAdding(scroll: ScrollViewProxy, section: String? = nil) {
        showingSearch = false
        searchText = ""
        beginAdding()
        updateEditor {
            addingToSection = section
            composerSection = section
            if let section { collapsedSections.remove(section) }
        }
        Task { @MainActor in
            await Task.yield()
            updateEditor {
                scroll.scrollTo("new-item", anchor: .bottom)
                addFocused = true
            }
        }
    }

    private func sectionAddRow(_ section: String, scroll: ScrollViewProxy) -> some View {
        Button { startAdding(scroll: scroll, section: section) } label: {
            Image(systemName: "circle.dotted")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("הוספת מוצר למקטע \(section)")
        .selectionDisabled(true)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }


    private var hasNewName: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var productCompletions: [Product] {
        guard showProductCompletions, addFocused else { return [] }
        let query = preserveRawInput ? newName : ShoppingInputParser.parse(newName).name
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return [] }
        return Array(store.matchingProducts(query).prefix(3))
    }

    private func useCompletion(_ product: Product) {
        let parsed = ShoppingInputParser.parse(newName)
        updateEditor {
            newName = product.name
            preserveRawInput = true
            if !newQuantityOverridden {
                newQuantity = parsed.unit == nil ? product.usualQuantity : parsed.quantity
                newQuantityOverridden = true
            }
            if newUnit == nil { newUnit = parsed.unit ?? product.preferredUnit }
        }
        addInline()
    }

    private var inlineAddRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "circle")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
                TextField("מה צריך לקנות?", text: $newName)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(Color(uiColor: .label))
                    .tint(listTint)
                    .focused($addFocused)
                    .submitLabel(.next)
                    .onSubmit { addInline() }
                    .onChange(of: newName) { _, value in
                        if !preserveRawInput && !newQuantityOverridden {
                            let parsed = ShoppingInputParser.parse(value)
                            newQuantity = parsed.quantity
                        }
                    }
                    .accessibilityIdentifier("inlineAddField")
                if hasNewName {
                    Button("×\(newQuantity) \(newUnit.map(ShoppingUnit.shortLabel) ?? "")") { updateEditor { quantityExpanded.toggle() } }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("newItemQuantityButton")
                        .accessibilityLabel("עריכת כמות למוצר חדש")
                        .accessibilityValue("\(newQuantity)")
                }
            }
            if !productCompletions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(productCompletions) { product in
                        Button { useCompletion(product) } label: {
                            HStack {
                                Text(product.name).foregroundStyle(.primary)
                                Spacer()
                                if store.items.contains(where: { $0.productID == product.id }) {
                                    Text("כבר ברשימה · הוספת כמות").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(quantityLabel(product.usualQuantity, unit: product.preferredUnit))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "plus").foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("הוספת \(product.name)")
                    }
                }
                .padding(.leading, 48)
                .padding(.trailing, 12)
            }
            VStack(alignment: .leading, spacing: 4) {
                    if quantityExpanded {
                        InlineQuantityControls(quantity: Binding(
                            get: { newQuantity },
                            set: { newQuantity = $0; newQuantityOverridden = true }
                        ), unit: $newUnit, isNew: true)
                    }
                    TextField("הערה למוצר…", text: $newNote, axis: .vertical)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("newItemNoteField")
                    if let newPhotoData {
                        ItemPhotoThumbnail(bytes: newPhotoData, fileURL: nil, name: newName, side: 44)
                    }
                    HStack(spacing: 8) {
                        Button("כמות", systemImage: "number") { updateEditor { quantityExpanded.toggle() } }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        PhotosPicker(selection: $newPhoto, matching: .images) {
                            Image(systemName: "photo.badge.plus")
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("צירוף תמונה")
                        .onChange(of: newPhoto) { _, selection in
                            guard let selection else { return }
                            Task {
                                if let data = try? await selection.loadTransferable(type: Data.self), newPhoto == selection, let image = UIImage(data: data) {
                                    newPhotoData = ItemPhotoEncoder.encode(image)
                                }
                            }
                        }
                        Button(newUrgent ? "הסר דגל" : "דחוף", systemImage: newUrgent ? "flag.fill" : "flag") {
                            newUrgent.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(newUrgent ? Color.orange : Color(uiColor: .label))
                        .frame(minWidth: 44, minHeight: 44)
                        sectionPicker
                    }
                    .font(.body)
                    .buttonStyle(ShoppingToolButtonStyle())
                    .tint(Color(uiColor: .label))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(minHeight: 44)
                    let parsed = ShoppingInputParser.parse(newName)
                    if parsed.unit != nil && !preserveRawInput {
                        HStack {
                            Text("\(parsed.name) · ×\(newQuantity) \((newUnit ?? parsed.unit).map(ShoppingUnit.shortLabel) ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("שמירת הטקסט המקורי", systemImage: "arrow.uturn.backward") {
                                preserveRawInput = true
                                if !newQuantityOverridden { newQuantity = 1 }
                            }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
                .padding(.leading, 48)
                .padding(.trailing, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        // Automatic List button styling makes multiple row buttons fire together.
        .buttonStyle(.borderless)
        .id("new-item")
        .selectionDisabled(true)
         .listRowBackground(Color.clear)
        .background(Theme.editor,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var sectionPicker: some View {
        Menu {
            Button("אוטומטי") { addingToSection = nil }
            ForEach(Array(Set(allSectionNames + ["אחר"])).sorted(), id: \.self) { section in
                Button(section) { addingToSection = section }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .accessibilityLabel("בחירת מקטע למוצר חדש")
        .accessibilityValue(addingToSection ?? "אוטומטי")
    }

    private var listPicker: some View {
        Menu {
            ForEach(store.data.lists) { list in
                Button(list.name, systemImage: list.symbolName) {
                    switchList(to: list.id)
                }
            }
            Divider()
            Button("רשימה חדשה לחנות", systemImage: "plus") {
                listName = ""; showingNewList = true
            }
        } label: {
            Image(systemName: store.currentList.symbolName)
                .font(.title3)
        }
        .accessibilityLabel("בחירת חנות, \(store.currentList.name)")
    }

    private var optionsMenu: some View {
        Menu {
            Section {
                Toggle("הצגת מקטעים", isOn: $groupBySection)
                Button("הצגת פרטי הרשימה", systemImage: "info.circle") { closeEditor(); showingListDetails = true }
                Button("בחירת פריטים", systemImage: "checkmark.circle") {
                    closeEditor(); presentation.reset(); reordering = false; editMode = .active
                }
                Menu("ניהול המקטעים", systemImage: "line.3.horizontal.decrease") {
                    Button("מקטע חדש", systemImage: "plus.rectangle.on.rectangle") { sectionName = ""; showingNewSection = true }
                    Button("עריכת מקטעים", systemImage: "pencil") { closeEditor(); showingSectionManagement = true }
                }
                Button("סידור מוצרים", systemImage: "arrow.up.arrow.down") {
                    closeEditor(); presentation.reset(); addingToSection = nil
                    selectedItemIDs.removeAll(); reordering = true; editMode = .active
                }
                Toggle("הצגת מוצרים שנקנו", isOn: $showRecentPurchases)
            }
            Section {
                Button("קנייה חדשה", systemImage: "cart.badge.plus") { closeEditor(); presentation.reset(); showingPreparation = true }
                Button("היסטוריית קניות", systemImage: "clock") { showingHistory = true }
                Button(store.currentShare == nil ? "שיתוף הרשימה…" : "ניהול השיתוף…", systemImage: "person.2") { openSharing() }
                    #if targetEnvironment(simulator)
                    .disabled(true)
                    #endif
            }
            Section {
                Button("ביטול", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
                    .disabled(undoManager?.canUndo != true || isAdding || editingNameID != nil)
                    .keyboardShortcut("z", modifiers: .command)
                Button("ביצוע חוזר", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
                    .disabled(undoManager?.canRedo != true || isAdding || editingNameID != nil)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Button("הגדרות", systemImage: "gearshape") { closeEditor(); showingSettings = true }
            }
            if store.canDeleteCurrentList {
                Section {
                    Button("מחיקת הרשימה", systemImage: "trash", role: .destructive) {
                        closeEditor(); deletingListID = store.selectedListID; confirmingDeleteList = true
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.title3)
        }
        .accessibilityLabel("אפשרויות נוספות")
    }

    private func openSharing() {
        closeEditor()
        sharingListID = store.selectedListID
        showingSharing = true
    }

    private func restoreCollapsedSections() {
        let saved = savedCollapsedSections.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        collapsedSections = Set(saved[store.selectedListID.uuidString] ?? [])
    }

    private func persistCollapsedSections() {
        var saved = savedCollapsedSections.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        saved[store.selectedListID.uuidString] = collapsedSections.sorted()
        if let data = try? JSONEncoder().encode(saved), let value = String(data: data, encoding: .utf8) {
            savedCollapsedSections = value
        }
    }

    private var sectionNames: [String] { searchText.isEmpty ? allSectionNames : allSectionNames.filter { !items(in: $0).isEmpty } }

    private var allSectionNames: [String] {
        store.sectionNames
    }

    private func items(in section: String) -> [ShoppingItem] {
        visibleItems.filter { store.section(for: $0) == section }
    }

    private func quantityLabel(_ quantity: Int, unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return "×\(quantity)" }
        return "\(quantity) \(ShoppingUnit.shortLabel(unit))"
    }

    private func sectionHeader(_ section: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0)) {
                if !collapsedSections.insert(section).inserted { collapsedSections.remove(section) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(section)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if collapsedSections.contains(section) {
                    Text("\(store.items.filter { store.section(for: $0) == section }.count)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: collapsedSections.contains(section) ? "chevron.backward" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section), \(store.items.filter { store.section(for: $0) == section }.count) מוצרים")
        .accessibilityHint(collapsedSections.contains(section) ? "הרחבת מקטע" : "צמצום מקטע")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if section != "אחר" {
                Button("עריכת מקטע", systemImage: "pencil") {
                    closeEditor(); editingSection = section; showingSectionEditor = true
                }.tint(.blue)
            }
        }
        .accessibilityAction(named: "עריכת מקטע") {
            guard section != "אחר" else { return }
            closeEditor(); editingSection = section; showingSectionEditor = true
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            if section != sectionNames.first { Divider() }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: ShoppingItem) -> some View {
        if let product = store.product(for: item.productID) {
            let completed = !store.items.contains { $0.id == item.id }
            VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !editMode.isEditing {
                Button {
                    updateEditor {
                        if let purchase = store.purchases.first(where: { $0.sourceItemID == item.id }) {
                            store.undo(purchase, undoManager: undoManager)
                        } else {
                            presentation.retain(item, among: displayItems)
                            store.buy(item, undoManager: undoManager)
                        }
                    }
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                } label: {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(completed ? listTint : Color(uiColor: .systemGray2))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(completed ? "ביטול קניית \(product.name)" : "נקנה \(product.name)")
                .accessibilityValue(completed ? "נקנה" : "לקנייה")
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + UIFont.preferredFont(forTextStyle: .body).capHeight / 2
                }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if editingNameID == item.id {
                        HStack(spacing: 4) {
                        TextField("שם המוצר", text: $editedName)
                            .tint(listTint)
                            .focused($nameFocused, equals: item.id)
                            .submitLabel(.next)
                            .onSubmit { continueBelow(item) }

                        }
                        .frame(minHeight: 44)
                    } else if editMode.isEditing {
                        HStack(spacing: 6) {
                            Text(product.name)
                                    .font(.body)
                                    .foregroundStyle(Color(uiColor: .label))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            if item.isUrgent {
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("דחוף")
                            }
                        }
                    } else {
                        Button {
                            if isAdding || editingNameID != nil { closeEditor() }
                            updateEditor {
                                editedName = product.name
                                originalEditedName = product.name
                                editingNameID = item.id
                                quantityExpanded = false
                                nameFocused = item.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(product.name)
                                    .font(.body)
                                    .foregroundStyle(Color(uiColor: .label))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if item.isUrgent {
                                    Image(systemName: "flag.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("דחוף")
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(completed)
                    }
                    if let clarification = item.clarification, !clarification.resolved {
                        Button {
                            closeEditor(); clarificationItem = item
                        } label: {
                            Label(clarification.answer == nil ? "צריך בירור" : "יש תשובה", systemImage: "bubble.left.and.bubble.right")
                                .font(.subheadline).foregroundStyle(.teal)
                                .frame(minHeight: 44)
                        }.buttonStyle(.borderless)
                    }
                    if item.unavailable == true {
                        Label("לא היה בחנות", systemImage: "basket")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if editingNameID != item.id, let note = item.note, !note.isEmpty {
                        Text(note).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if item.photoData != nil || item.photoFilename != nil {
                    ItemPhotoThumbnail(bytes: item.photoData, fileURL: store.legacyPhotoURL(for: item), name: product.name)
                }
                if item.quantity > 1 || item.unit != nil || editingNameID == item.id {
                    Button(quantityLabel(item.quantity, unit: item.unit)) {
                        if editingNameID != item.id {
                            if isAdding || editingNameID != nil { closeEditor() }
                            updateEditor {
                                editedName = product.name
                                originalEditedName = product.name
                                editingNameID = item.id
                                nameFocused = nil
                                quantityExpanded = true
                            }
                        } else {
                            updateEditor { quantityExpanded = true }
                        }
                    }
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, maxWidth: 110, minHeight: 44, alignment: .trailing)
                    .disabled(editMode.isEditing || completed)
                    .accessibilityLabel("עריכת כמות והערות עבור \(product.name)")
                    .accessibilityValue("כמות \(item.quantity) \(item.unit ?? "")")
                }
            }
            if editingNameID == item.id && !editMode.isEditing {
                ItemInlineDetails(store: store, item: item, showsQuantity: quantityExpanded,
                    onQuantity: { updateEditor { quantityExpanded.toggle() } },
                    onSection: { saveRename(item); editingCategory = item }, onDetails: {
                    saveRename(item)
                    detailItem = item
                })
                    .padding(.leading, 48)
                    .padding(.trailing, 12)
                    .transition(.identity)
            }
            }
            .opacity(completed ? 0.5 : 1)
            .padding(.horizontal, 0)
            .padding(.vertical, editingNameID == item.id ? 8 : 2)
            .background(editingNameID == item.id ? Theme.editor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .listRowBackground(Color.clear)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(item.isUrgent ? "הסר דגל" : "דחוף",
                       systemImage: item.isUrgent ? "flag.slash" : "flag") {
                    store.toggleUrgent(item)
                }
                .disabled(completed)
                .labelStyle(.iconOnly)
                .tint(Color(red: 0.62, green: 0.34, blue: 0.02))
                Button("צריך בירור", systemImage: "bubble.left.and.bubble.right") {
                    closeEditor(); clarificationItem = item
                }.tint(.teal).disabled(completed)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("הסר", systemImage: "trash", role: .destructive) { store.remove(item, undoManager: undoManager) }
                    .disabled(completed)
                    .labelStyle(.iconOnly)
                    .tint(.red)
                Button("מקטע", systemImage: "square.grid.2x2") { editingCategory = item }
                    .disabled(completed)
                    .labelStyle(.iconOnly)
                    .tint(Color(uiColor: .systemBlue))
            }
            .background {
                if !completed { nativeDrag(.item(item.id), section: showsSections ? store.section(for: item) : nil) }
            }
            .accessibilityAction(named: "העברה למעלה") { moveItem(item, down: false) }
            .accessibilityAction(named: "העברה למטה") { moveItem(item, down: true) }
            .selectionDisabled(!editMode.isEditing || completed)
            .tag(item.id)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { _, frame in
                itemFrames.frames[item.id] = frame
            }
            .onDisappear { itemFrames.frames[item.id] = nil }
        }
    }

    private func moveItem(_ item: ShoppingItem, down: Bool) {
        let section = showsSections ? store.section(for: item) : nil
        let ordered = section.map { items(in: $0) } ?? store.items
        guard let index = ordered.firstIndex(where: { $0.id == item.id }) else { return }
        let neighbor = index + (down ? 1 : -1)
        guard ordered.indices.contains(neighbor) else { return }
        store.place([item.id], inSection: section, relativeTo: ordered[neighbor].id, after: down)
    }

    private func dragPreviewContent(for entry: ShoppingDragEntry) -> ShoppingDragPreviewContent {
        switch entry {
        case .section(let name):
            return ShoppingDragPreviewContent(title: name, isSection: true)
        case .item(let id):
            guard let item = store.items.first(where: { $0.id == id }),
                  let product = store.product(for: item.productID) else {
                return ShoppingDragPreviewContent(title: "מוצר")
            }
            return ShoppingDragPreviewContent(title: product.name,
                quantity: quantityLabel(item.quantity, unit: item.unit), note: item.note, urgent: item.isUrgent)
        }
    }

    private func updateEditor(_ update: () -> Void) {
        // UIKit's List self-sizing and keyboard already update geometry. A
        // concurrent SwiftUI transition causes the same height to animate twice.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private func nativeDrag(_ entry: ShoppingDragEntry, section: String?) -> some View {
        NativeShoppingDrag(entry: entry, listID: store.selectedListID,
                           enabled: !editMode.isEditing && editingNameID == nil && !isAdding,
                           tint: UIColor(listTint), previewContent: dragPreviewContent(for: entry)) { entries, after in
            presentation.reset() // An explicit drop is a stable presentation transition.
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                if case .section(let source)? = entries.first,
                   case .section(let target) = entry {
                    store.placeSection(source, relativeTo: target, after: after)
                } else {
                    let draggedIDs = Set(entries.compactMap { value -> UUID? in
                        if case .item(let id) = value { return id }
                        return nil
                    })
                    let visibleOrder = showsSections ? sectionNames.flatMap { items(in: $0) } : store.items
                    let ids = visibleOrder.filter { draggedIDs.contains($0.id) }.map(\.id)
                    let target: UUID?
                    if case .item(let id) = entry { target = id } else { target = nil }
                    store.place(ids, inSection: section, relativeTo: target, after: after)
                }
            }
        }
    }

    private func beginAdding() {
        closeEditor()
        presentation.reset()
        updateEditor { isAdding = true; addingToSection = nil; addingAfterID = nil; composerSection = nil; quantityExpanded = false }
    }

    private func addInline(continueAdding: Bool = true) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateEditor {
            let parsed = preserveRawInput ? ShoppingInputParser.Result(name: trimmed, quantity: newQuantity, unit: nil) : ShoppingInputParser.parse(trimmed)
            let added = store.add(name: parsed.name, quantity: newQuantityOverridden || parsed.unit == nil ? newQuantity : parsed.quantity,
                      department: addingToSection, urgent: newUrgent)
            if let item = added {
                if let addingAfterID, addingAfterID != item.id {
                    store.place([item.id], inSection: addingToSection, relativeTo: addingAfterID, after: true)
                }
                addingToSection = store.section(for: item)
                composerSection = addingToSection
                collapsedSections.remove(store.section(for: item))
                addingAfterID = item.id
                if let unit = newUnit ?? parsed.unit { store.updateUnit(of: item, to: unit) }
                if !newNote.isEmpty { store.updateNote(of: item, to: newNote) }
                if let newPhotoData { store.setPhoto(newPhotoData, for: item) }
            }
            newQuantity = 1
            preserveRawInput = false
            newQuantityOverridden = false
            newName = ""
            newUnit = nil
            newNote = ""
            newUrgent = false
            newPhotoData = nil
            newPhoto = nil
            showingNewNote = false
            quantityExpanded = false
            addFocused = continueAdding
        }
    }

    private func saveRename(_ item: ShoppingItem) {
        guard editedName != originalEditedName else { return }
        store.rename(item, to: editedName, undoManager: undoManager)
        originalEditedName = editedName
    }

    private func continueBelow(_ item: ShoppingItem) {
        saveRename(item)
        presentation.reset()
        updateEditor {
            editingNameID = nil
            nameFocused = nil
            quantityExpanded = false
            addingToSection = store.section(for: item)
            composerSection = addingToSection
            addingAfterID = item.id
            collapsedSections.remove(store.section(for: item))
            isAdding = true
            addFocused = true
        }
    }

    private func closeEditor() {
        if isAdding { addInline(continueAdding: false) }
        if let id = editingNameID, let item = store.items.first(where: { $0.id == id }) { saveRename(item) }
        updateEditor {
            isAdding = false
            addingAfterID = nil
            addingToSection = nil
            composerSection = nil
            newName = ""
            newQuantity = 1
            newQuantityOverridden = false
            preserveRawInput = false
            newUnit = nil
            newNote = ""
            newUrgent = false
            newPhotoData = nil
            newPhoto = nil
            showingNewNote = false
            addFocused = false
            editingNameID = nil
            nameFocused = nil
            quantityExpanded = false
        }
    }

    private func switchList(to id: UUID) {
        closeEditor()
        store.selectList(id)
        presentation.reset()
        restoreCollapsedSections()
        placeFilter = "הכול"
        addingToSection = nil
        selectedItemIDs.removeAll()
        itemFrames.frames.removeAll()
        reordering = false
        editMode = .inactive
    }

}

struct ItemInlineDetails: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    let showsQuantity: Bool
    let onDetails: (() -> Void)?
    let onQuantity: (() -> Void)?
    let onSection: (() -> Void)?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraDenied = false
    @State private var showingPhoto = false
    @State private var note: String
    @State private var showingClarification = false

    init(store: ShoppingStore, item: ShoppingItem, showsQuantity: Bool = true, onQuantity: (() -> Void)? = nil,
         onSection: (() -> Void)? = nil, onDetails: (() -> Void)? = nil) {
        self.store = store
        self.item = item
        self.showsQuantity = showsQuantity
        self.onDetails = onDetails
        self.onQuantity = onQuantity
        self.onSection = onSection
        _note = State(initialValue: item.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsQuantity {
                InlineQuantityControls(quantity: Binding(
                    get: { item.quantity }, set: { store.updateQuantity(of: item, to: $0) }
                ), unit: Binding(
                    get: { item.unit }, set: { store.updateUnit(of: item, to: $0) }
                ))
            }
            TextField("הערה למוצר…", text: $note, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)
                .onChange(of: note) { _, value in store.updateNote(of: item, to: value) }
                .accessibilityIdentifier("itemNoteField")
                .onChange(of: item.note) { _, value in
                    if note != (value ?? "") { note = value ?? "" }
                }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], alignment: .leading, spacing: 8) {
                if let onQuantity {
                    Button("כמות", systemImage: "number", action: onQuantity).labelStyle(.iconOnly)
                }
                if let onSection {
                    Button("מקטע", systemImage: "square.grid.2x2", action: onSection).labelStyle(.iconOnly)
                }
                Button(item.isUrgent ? "הסר דגל" : "דחוף", systemImage: item.isUrgent ? "flag.fill" : "flag") {
                    store.toggleUrgent(item)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(item.isUrgent ? Color.orange : Color(uiColor: .label))
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(item.photoFilename == nil && item.photoData == nil ? "צירוף תמונה" : "החלפת תמונה", systemImage: "photo.badge.plus")
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .onChange(of: selectedPhoto) { _, selection in
                    guard let selection else { return }
                    Task {
                        if let data = try? await selection.loadTransferable(type: Data.self), selectedPhoto == selection {
                            store.setPhoto(data, for: item)
                        }
                    }
                }
                Menu {
                    if let onDetails { Button("פרטי מוצר", systemImage: "info.circle", action: onDetails) }
                    Button("צריך בירור", systemImage: "bubble.left.and.bubble.right") { showingClarification = true }
                    Button(item.unavailable == true ? "אפשר לקנות שוב" : "לא היה בחנות", systemImage: "basket") {
                        store.toggleUnavailable(item)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("צילום", systemImage: "camera") {
                            Task {
                                if await AVCaptureDevice.requestAccess(for: .video) { showingCamera = true }
                                else { cameraDenied = true }
                            }
                        }
                    }
                    if item.photoFilename != nil || item.photoData != nil {
                        Button("הגדלת תמונת המוצר", systemImage: "photo") { showingPhoto = true }
                        Button("הסרת תמונה", systemImage: "trash", role: .destructive) { store.removePhoto(from: item) }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("אפשרויות מוצר")
            }
            .font(.body)
            .tint(Color(uiColor: .label))
            .foregroundStyle(Color(uiColor: .label))
            .buttonStyle(ShoppingToolButtonStyle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingClarification) { ClarificationView(store: store, item: item) }
        .sheet(isPresented: $showingCamera) { ItemCamera { store.setPhoto($0, for: item) } }
        .sheet(isPresented: $showingPhoto) {
            NavigationStack {
                ItemPhotoThumbnail(bytes: item.photoData, fileURL: store.legacyPhotoURL(for: item),
                                   name: store.product(for: item.productID)?.name ?? "", fullImage: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar { Button("סגירה", systemImage: "xmark") { showingPhoto = false }.labelStyle(.iconOnly) }
            }
        }
        .alert("אין גישה למצלמה", isPresented: $cameraDenied) {
            Button("הגדרות") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("ביטול", role: .cancel) {}
        } message: { Text("אפשר לאפשר גישה בהגדרות או לבחור תמונה מהספרייה.") }
    }


}


// Selection hit testing consumes these frames inside a gesture callback, not
// while rendering. Publishing every geometry change back into SwiftUI creates
// a layout/update feedback loop during native List and keyboard animations.
private final class ShoppingItemFrameRegistry {
    var frames: [UUID: CGRect] = [:]
}




