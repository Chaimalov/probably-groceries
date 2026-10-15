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
    @State private var detailItem: ShoppingItem?
    @State private var placeFilter = "הכול"
    @State private var lastMarkAt = Date.distantPast
    @State private var showingNewList = false
    @State private var showingRenameList = false
    @State private var showingNewSection = false
    @State private var showingAppearance = false
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
    @AppStorage("showEmptySections") private var showEmptySections = false
    @AppStorage("showRecentPurchases") private var showRecentPurchases = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
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

    private var visibleItems: [ShoppingItem] {
        store.items.filter { placeFilter == "הכול" || (placeFilter == "ללא מקום" ? $0.shoppingPlace == nil : $0.shoppingPlace == placeFilter) }
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
                                if !collapsedSections.contains(section) {
                                    ForEach(items(in: section)) { item in
                                        itemRow(item)
                                            .moveDisabled(!reordering)
                                            .listRowSeparator(.hidden, edges: .all)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    }
                                    .onMove { source, destination in
                                        store.move(from: source, to: destination, inSection: section)
                                    }
                                }
                            } header: {
                                sectionHeader(section)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .textCase(nil)
                                    .background {
                                        nativeDrag(.section(section), section: section)
                                    }
                            }
                            .listSectionSeparator(.hidden, edges: .all)
                        }
                    } else {
                        Section {
                            ForEach(visibleItems) { item in
                                itemRow(item)
                                    .moveDisabled(!reordering)
                                    .listRowSeparator(.hidden, edges: .all)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                            .onMove { source, destination in
                                store.move(from: source, to: destination, inSection: nil)
                            }
                        }
                        .listSectionSeparator(.hidden, edges: .all)
                    }

                    if isAdding {
                        Section { inlineAddRow }
                            .listSectionSeparator(.hidden)
                    }



                    if showRecentPurchases && !store.recentPurchases.isEmpty {
                        Section("נקנו לאחרונה") {
                            ForEach(store.recentPurchases) { purchase in
                                if let product = store.product(for: purchase.productID) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                        Text(product.name).foregroundStyle(.secondary)
                                        Spacer()
                                        Button {
                                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                                store.undo(purchase)
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
                                            store.undo(purchase)
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
                .frame(maxWidth: sizeClass == .regular ? 760 : .infinity)
                .frame(maxWidth: .infinity)
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
                .environment(\.defaultMinListRowHeight, 44)
                .environment(\.defaultMinListHeaderHeight, 0)
                .scrollDismissesKeyboard(.interactively)
                .inspector(isPresented: Binding(
                    get: { detailItem != nil },
                    set: { if !$0 { detailItem = nil } }
                )) {
                    if let detailItem {
                        ItemDetailsSheet(store: store, item: detailItem)
                            .id(detailItem.id)
                            .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
                    }
                }
                .toolbar { bottomActions(scroll) }

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
            .onChange(of: store.items) { _, items in
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
            .sheet(item: $editingCategory) { CategoryEditor(store: store, item: $0) }
            .sheet(isPresented: $showingAppearance) { ListAppearanceEditor(store: store) }
            .onChange(of: editMode) { _, mode in
                if !mode.isEditing {
                    selectedItemIDs.removeAll()
                    reordering = false
                }
            }
            .sheet(isPresented: $showingPreparation) { ShoppingPreparationView(store: store) }
            .sheet(isPresented: $showingHistory) { PurchaseHistoryView(store: store) }
            .alert("רשימה חדשה לחנות", isPresented: $showingNewList) {
                TextField("שם החנות", text: $listName)
                Button("יצירה") { closeEditor(); store.addList(name: listName) }
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
                    showEmptySections = true
                }
                Button("ביטול", role: .cancel) {}
            }
        }
        .tint(listTint)
        .sheet(isPresented: $showingSharing) {
            if let listID = sharingListID { ListSharingSheet(store: store, listID: listID) }
        }
        .task {
            #if !targetEnvironment(simulator)
            store.cloudSync.start()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
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
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { store.remove(selectedItemIDs) }
                                selectedItemIDs.removeAll()
                                editMode = .inactive
                            }
                            .disabled(selectedItemIDs.isEmpty)
                        }
                    } else if isAdding || editingNameID != nil {
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) {
                            Button("סיום עריכה", systemImage: "checkmark") { closeEditor() }
                                .labelStyle(.iconOnly)
                                .keyboardShortcut(.return, modifiers: .command)
                        }
                    } else {
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) {
                            Button("מוצר חדש", systemImage: "plus") {
                                beginAdding()
                                Task { @MainActor in
                                    await Task.yield()
                                    scroll.scrollTo("new-item", anchor: .bottom)
                                    addFocused = true
                                }
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("הוספת מוצר")
                            .keyboardShortcut("n", modifiers: .command)
                        }
                    }
    }


    private var hasNewName: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inlineAddRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
                TextField("מה צריך לקנות?", text: $newName)
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
                    Button("×\(newQuantity)") { quantityExpanded.toggle() }
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("newItemQuantityButton")
                        .accessibilityLabel("עריכת כמות למוצר חדש")
                        .accessibilityValue("\(newQuantity)")
                }
            }
            if hasNewName {
                VStack(alignment: .leading, spacing: 4) {
                    if quantityExpanded {
                        InlineQuantityControls(quantity: Binding(
                            get: { newQuantity },
                            set: { newQuantity = $0; newQuantityOverridden = true }
                        ), unit: $newUnit, isNew: true)
                    }
                    if showingNewNote {
                        TextField("הערה למוצר…", text: $newNote, axis: .vertical)
                            .lineLimit(1...3)
                            .accessibilityIdentifier("newItemNoteField")
                    }
                    if let newPhotoData {
                        ItemPhotoThumbnail(bytes: newPhotoData, fileURL: nil, name: newName, side: 44)
                    }
                    HStack(spacing: 8) {
                        Button("הערה", systemImage: "text.alignright") { showingNewNote.toggle() }
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
                        .foregroundStyle(newUrgent ? Color.orange : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        sectionPicker
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    let parsed = ShoppingInputParser.parse(newName)
                    if parsed.unit != nil && !preserveRawInput {
                        HStack {
                            Text("\(parsed.name) · ×\(newQuantity) \(newUnit ?? parsed.unit ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("שמירת הטקסט המקורי", systemImage: "arrow.uturn.backward") {
                                preserveRawInput = true
                                if !newQuantityOverridden { newQuantity = 1 }
                            }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
                .padding(.leading, 48)
            }
        }
        .id("new-item")
        .selectionDisabled(true)
         .listRowBackground(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .padding(.horizontal, 8)
        )
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
            Label(addingToSection ?? "מקטע", systemImage: "square.grid.2x2")
                .lineLimit(1)
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
            Button("קנייה חדשה", systemImage: "cart.badge.plus") { showingPreparation = true }
            Button(groupBySection ? "הצגה לפי מסלול הקנייה" : "הצגת מקטעים",
                   systemImage: "square.stack") { groupBySection.toggle() }
            Button("מקטע חדש", systemImage: "plus.rectangle.on.rectangle") {
                sectionName = ""; showingNewSection = true
            }
            Button("סידור מוצרים", systemImage: "line.3.horizontal") {
                closeEditor()
                addingToSection = nil
                selectedItemIDs.removeAll()
                reordering = true
                editMode = .active
            }
            Toggle("הצגת מקטעים ריקים", systemImage: "rectangle.dashed", isOn: $showEmptySections)
            Toggle("הצגת נקנו לאחרונה", systemImage: "checkmark.circle", isOn: $showRecentPurchases)
            Button("היסטוריית קניות", systemImage: "clock") { showingHistory = true }
            Button("בחירת פריטים", systemImage: "checkmark.circle") {
                closeEditor()
                reordering = false
                editMode = .active
            }
            Divider()
            Button(store.currentShare == nil ? "שיתוף הרשימה…" : "ניהול השיתוף…",
                   systemImage: "person.2") {
                sharingListID = store.selectedListID
                showingSharing = true
            }
            #if targetEnvironment(simulator)
            .disabled(true)
            #endif
            Button(LocalizedStringKey(syncLabel), systemImage: "arrow.triangle.2.circlepath.icloud") {
                #if !targetEnvironment(simulator)
                Task { await store.cloudSync.synchronize() }
                #endif
            }
            #if targetEnvironment(simulator)
            .disabled(true)
            #endif
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
        allSectionNames.filter { showEmptySections || reordering || !items(in: $0).isEmpty }
    }

    private var allSectionNames: [String] {
        let existing = store.currentList.sections
        let used = store.items.map { store.section(for: $0) }.filter { $0 != "אחר" }
        let names = existing + used.filter { !existing.contains($0) }
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        let needsOther = store.items.contains(where: { store.section(for: $0) == "אחר" }) ||
            (isAdding && addingToSection == "אחר")
        return needsOther && !unique.contains("אחר") ? unique + ["אחר"] : unique
    }

    private func items(in section: String) -> [ShoppingItem] {
        visibleItems.filter { store.section(for: $0) == section }
    }

    private func sectionHeader(_ section: String) -> some View {
        HStack {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    if !collapsedSections.insert(section).inserted { collapsedSections.remove(section) }
                }
            } label: {
                HStack {
                    Image(systemName: collapsedSections.contains(section) ? "chevron.left" : "chevron.down")
                        .font(.caption.weight(.semibold))
                    Text(section).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(items(in: section).count)").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(section), \(items(in: section).count) מוצרים")
            .accessibilityHint(collapsedSections.contains(section) ? "הרחבת מקטע" : "צמצום מקטע")

        }
        .buttonStyle(.plain)
        .padding(.vertical, 0)
    }

    @ViewBuilder
    private func itemRow(_ item: ShoppingItem) -> some View {
        if let product = store.product(for: item.productID) {
            VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if !editMode.isEditing {
                Button {
                    guard Date.now.timeIntervalSince(lastMarkAt) > 0.35 else { return }
                    lastMarkAt = .now
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if reduceMotion { store.buy(item) }
                    else { withAnimation(.easeOut(duration: 0.18)) { store.buy(item) } }
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 24, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("נקנה \(product.name)")
                }
                VStack(alignment: .leading, spacing: 2) {
                    if editingNameID == item.id {
                        HStack(spacing: 4) {
                        TextField("שם המוצר", text: $editedName)
                            .focused($nameFocused, equals: item.id)
                            .submitLabel(.done)
                            .onSubmit { finishRename(item) }

                        }
                        .frame(minHeight: 44)
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
                            closeEditor()
                            updateEditor {
                                editedName = product.name
                                originalEditedName = product.name
                                editingNameID = item.id
                                quantityExpanded = false
                                nameFocused = item.id
                            }
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if editingNameID != item.id, let note = item.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if item.photoData != nil || item.photoFilename != nil {
                    ItemPhotoThumbnail(bytes: item.photoData, fileURL: store.legacyPhotoURL(for: item), name: product.name)
                }
                if item.quantity > 1 || item.unit != nil || editingNameID == item.id {
                    Button("×\(item.quantity) \(item.unit ?? "")") {
                        if editingNameID != item.id {
                            closeEditor()
                            editedName = product.name
                            originalEditedName = product.name
                            editingNameID = item.id
                            quantityExpanded = false
                        }
                        updateEditor { quantityExpanded.toggle() }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(editMode.isEditing)
                    .accessibilityLabel("עריכת כמות והערות עבור \(product.name)")
                    .accessibilityValue("כמות \(item.quantity) \(item.unit ?? "")")
                }
                Spacer(minLength: 0)
                if editingNameID == item.id {
                    Button("פרטי מוצר", systemImage: "info.circle") {
                        saveRename(item)
                        detailItem = item
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            if editingNameID == item.id && !editMode.isEditing {
                ItemInlineDetails(store: store, item: item, showsQuantity: quantityExpanded)
                    .padding(.leading, 42)
                    .transition(.identity)
            }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 18)
                    .fill(editingNameID == item.id ? Color(uiColor: .secondarySystemGroupedBackground) : Color.clear)
                    .padding(.horizontal, 8)
            )
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(item.isUrgent ? "הסר דגל" : "דחוף",
                       systemImage: item.isUrgent ? "flag.slash" : "flag") {
                    store.toggleUrgent(item)
                }
                .labelStyle(.iconOnly)
                .tint(Color(red: 0.62, green: 0.34, blue: 0.02))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("הסר", systemImage: "trash", role: .destructive) { store.remove(item) }
                    .labelStyle(.iconOnly)
                    .tint(.red)
                Button("מקטע", systemImage: "square.grid.2x2") { editingCategory = item }
                    .labelStyle(.iconOnly)
                    .tint(Color(uiColor: .systemBlue))
            }
            .background {
                nativeDrag(.item(item.id), section: showsSections ? store.section(for: item) : nil)
            }
            .accessibilityAction(named: "העברה למעלה") { moveItem(item, down: false) }
            .accessibilityAction(named: "העברה למטה") { moveItem(item, down: true) }
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
                quantity: "×\(item.quantity) \(item.unit ?? "")", note: item.note, urgent: item.isUrgent)
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
                        .labelStyle(.iconOnly)
                        .tint(Color(uiColor: .systemIndigo))
                }
                .listRowSeparator(.hidden)
                .selectionDisabled(true)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
        .listSectionSeparator(.hidden)
    }

    private func beginAdding() {
        closeEditor()
        updateEditor { isAdding = true; addingToSection = nil; quantityExpanded = false }
    }

    private func addInline(continueAdding: Bool = true) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateEditor {
            let parsed = preserveRawInput ? ShoppingInputParser.Result(name: trimmed, quantity: newQuantity, unit: nil) : ShoppingInputParser.parse(trimmed)
            store.add(name: parsed.name, quantity: newQuantityOverridden || parsed.unit == nil ? newQuantity : parsed.quantity,
                      department: addingToSection, urgent: newUrgent)
            if let item = store.items.first(where: { store.product(for: $0.productID)?.name == parsed.name }) {
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
        store.rename(item, to: editedName)
        originalEditedName = editedName
    }

    private func finishRename(_ item: ShoppingItem) {
        saveRename(item)
        updateEditor { editingNameID = nil; nameFocused = nil; quantityExpanded = false }
    }

    private func closeEditor() {
        if isAdding { addInline(continueAdding: false) }
        if let id = editingNameID, let item = store.items.first(where: { $0.id == id }) { saveRename(item) }
        updateEditor {
            isAdding = false
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
        collapsedSections.removeAll()
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraDenied = false
    @State private var showingPhoto = false
    @State private var note: String

    init(store: ShoppingStore, item: ShoppingItem, showsQuantity: Bool = true) {
        self.store = store
        self.item = item
        self.showsQuantity = showsQuantity
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
                .lineLimit(1...3)
                .onChange(of: note) { _, value in store.updateNote(of: item, to: value) }
                .accessibilityIdentifier("itemNoteField")
                .onChange(of: item.note) { _, value in
                    if note != (value ?? "") { note = value ?? "" }
                }
            HStack {
                Button(item.isUrgent ? "הסר דגל" : "דחוף", systemImage: item.isUrgent ? "flag.fill" : "flag") {
                    store.toggleUrgent(item)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(item.isUrgent ? Color.orange : Color.secondary)
                .frame(minWidth: 44, minHeight: 44)
                if item.photoData != nil || item.photoFilename != nil {
                    Button { showingPhoto = true } label: {
                        ItemPhotoThumbnail(bytes: item.photoData, fileURL: store.legacyPhotoURL(for: item),
                                           name: store.product(for: item.productID)?.name ?? "", side: 52)
                    }.accessibilityLabel("הגדלת תמונת המוצר")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("צילום", systemImage: "camera") {
                        Task {
                            let allowed = await AVCaptureDevice.requestAccess(for: .video)
                            if allowed { showingCamera = true } else { cameraDenied = true }
                        }
                    }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(item.photoFilename == nil && item.photoData == nil ? "צירוף תמונה" : "החלפת תמונה", systemImage: "photo.badge.plus")
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.borderless)
                .onChange(of: selectedPhoto) { _, selection in
                    guard let selection else { return }
                    Task {
                        if let data = try? await selection.loadTransferable(type: Data.self), selectedPhoto == selection {
                            store.setPhoto(data, for: item)
                        }
                    }
                }
                if item.photoFilename != nil || item.photoData != nil {
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
