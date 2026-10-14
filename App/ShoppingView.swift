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
    @State private var editedName = ""
    @State private var expandedItemID: UUID?
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
    @AppStorage("showRecentPurchases") private var showRecentPurchases = true
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

    private var visibleItems: [ShoppingItem] {
        store.items.filter { placeFilter == "הכול" || (placeFilter == "ללא מקום" ? $0.shoppingPlace == nil : $0.shoppingPlace == placeFilter) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                List(selection: reordering ? nil : $selectedItemIDs) {
                    if let error = store.storageError {
                        Section {
                            Text(LocalizedStringKey(error)).foregroundStyle(.red)
                            Button("ניסיון שמירה נוסף") { store.retryLocalSave() }
                        }
                    }
                    if let binding = store.currentShare {
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
                                            .listRowBackground(Color.clear)
                                    }
                                    .onMove { source, destination in
                                        store.move(from: source, to: destination, inSection: section)
                                    }
                                    if isAdding && addingToSection == section { inlineAddRow }
                                }
                            } header: {
                                sectionHeader(section)
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
                                    .listRowBackground(Color.clear)
                            }
                            .onMove { source, destination in
                                store.move(from: source, to: destination, inSection: nil)
                            }
                        }
                        .listSectionSeparator(.hidden, edges: .all)
                    }

                    if isAdding && (!showsSections || addingToSection == nil) {
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
                .onChange(of: addingToSection) { _, section in
                    guard isAdding, section != nil else { return }
                    Task { @MainActor in
                        await Task.yield()
                        scroll.scrollTo("new-item", anchor: .bottom)
                        addFocused = true
                    }
                }
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
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel("הוספת מוצר")
                            Spacer()
                            Button("קנייה חדשה", systemImage: "cart.badge.plus") { showingPreparation = true }
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
            .onChange(of: store.items) { _, items in
                if placeFilter != "הכול" && placeFilter != "ללא מקום" && !items.contains(where: { $0.shoppingPlace == placeFilter }) { placeFilter = "הכול" }
            }
            .onChange(of: nameFocused) { oldID, newID in
                if oldID != newID, let oldID, editingNameID == oldID,
                   let item = store.items.first(where: { $0.id == oldID }) {
                    finishRename(item)
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
            .sheet(item: $detailItem) { ItemDetailsSheet(store: store, item: $0) }
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

    private var inlineAddRow: some View {
        VStack(alignment: .leading) {
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
            Button {
                newQuantity = max(1, newQuantity - 1)
            } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(newQuantity == 1)
            .accessibilityLabel("הפחתת כמות למוצר חדש")
            Text("\(newQuantity)")
                .monospacedDigit()
                .frame(minWidth: 20)
            Button {
                newQuantity = min(9999, newQuantity + 1)
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(newQuantity == 9999)
            .accessibilityLabel("הגדלת כמות למוצר חדש")
        }
        .buttonStyle(.borderless)
        let parsed = ShoppingInputParser.parse(newName)
        if parsed.unit != nil && !preserveRawInput {
            HStack {
                Text("\(parsed.name) · ×\(parsed.quantity) \(parsed.unit ?? "")").font(.caption).foregroundStyle(.secondary)
                Button("שמירת הטקסט המקורי", systemImage: "arrow.uturn.backward") { preserveRawInput = true }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
        }
        }
        .id("new-item")
        .selectionDisabled(true)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var listPicker: some View {
        Menu {
            ForEach(store.data.lists) { list in
                Button(list.name, systemImage: list.symbolName) {
                    store.selectList(list.id)
                    collapsedSections.removeAll()
                    placeFilter = "הכול"
                    addingToSection = nil
                    selectedItemIDs.removeAll()
                    itemFrames.frames.removeAll()
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
            Button("קנייה חדשה", systemImage: "cart.badge.plus") { showingPreparation = true }
            Button(groupBySection ? "הצגה לפי מסלול הקנייה" : "הצגת מקטעים",
                   systemImage: "square.stack") { groupBySection.toggle() }
            Button("מקטע חדש", systemImage: "plus.rectangle.on.rectangle") {
                sectionName = ""; showingNewSection = true
            }
            Button("סידור מוצרים", systemImage: "line.3.horizontal") {
                addFocused = false
                isAdding = false
                addingToSection = nil
                selectedItemIDs.removeAll()
                reordering = true
                editMode = .active
            }
            Toggle("הצגת נקנו לאחרונה", systemImage: "checkmark.circle", isOn: $showRecentPurchases)
            Button("היסטוריית קניות", systemImage: "clock") { showingHistory = true }
            Button("בחירת פריטים", systemImage: "checkmark.circle") {
                addFocused = false
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
                    Text(section).font(.headline).foregroundStyle(listTint)
                    Text("\(items(in: section).count)").foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(section), \(items(in: section).count) מוצרים")
            .accessibilityHint(collapsedSections.contains(section) ? "הרחבת מקטע" : "צמצום מקטע")
            Button {
                collapsedSections.remove(section)
                addingToSection = section
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
                            if let previousID = editingNameID,
                               let previous = store.items.first(where: { $0.id == previousID }) {
                                finishRename(previous)
                            }
                            updateEditor {
                                editedName = product.name
                                editingNameID = item.id
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let note = item.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let url = store.photoURL(for: item), let photo = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("תמונה של \(product.name)")
                }
                Button("פרטי מוצר", systemImage: "info.circle") { detailItem = item }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                if editMode.isEditing {
                    Text("×\(item.quantity) \(item.unit ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                Button("×\(item.quantity) \(item.unit ?? "")") {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    updateEditor {
                        expandedItemID = expandedItemID == item.id ? nil : item.id
                    }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("עריכת כמות והערות עבור \(product.name)")
                .accessibilityValue("כמות \(item.quantity) \(item.unit ?? "")")
                }
            }
            if expandedItemID == item.id && !editMode.isEditing {
                ItemInlineDetails(store: store, item: item)
                    .padding(.leading, 42)
                    .transition(.identity)
            }
            }
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
                           enabled: !editMode.isEditing && editingNameID == nil,
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

    private func addInline() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateEditor {
            let parsed = preserveRawInput ? ShoppingInputParser.Result(name: trimmed, quantity: newQuantity, unit: nil) : ShoppingInputParser.parse(trimmed)
            store.add(name: parsed.name, quantity: parsed.unit == nil ? newQuantity : parsed.quantity, department: addingToSection)
            if let unit = parsed.unit, let item = store.items.first(where: { store.product(for: $0.productID)?.name == parsed.name }) {
                store.updateUnit(of: item, to: unit)
            }
            newQuantity = 1
            preserveRawInput = false
            newName = ""
            addFocused = true
        }
    }

    private func finishRename(_ item: ShoppingItem) {
        store.rename(item, to: editedName)
        updateEditor { editingNameID = nil }
    }
}

struct ItemInlineDetails: View {
    private static let commonUnits = ["יחידות", "חבילות", "ליטרים", "מ״ל", "ק״ג", "גרם", "בקבוקים", "קופסאות", "שקיות", "גלילים"]
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraDenied = false
    @State private var showingPhoto = false
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
                    Button { showingPhoto = true } label: {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 9))
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
                .buttonStyle(.borderless)
                .onChange(of: selectedPhoto) { _, selection in
                    guard let selection else { return }
                    Task {
                        if let data = try? await selection.loadTransferable(type: Data.self) {
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
            if let url = store.photoURL(for: item), let photo = UIImage(contentsOfFile: url.path) {
                NavigationStack {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .toolbar { Button("סגירה", systemImage: "xmark") { showingPhoto = false }.labelStyle(.iconOnly) }
                }
            }
        }
        .alert("אין גישה למצלמה", isPresented: $cameraDenied) {
            Button("הגדרות") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("ביטול", role: .cancel) {}
        } message: { Text("אפשר לאפשר גישה בהגדרות או לבחור תמונה מהספרייה.") }
    }

    private func saveCustomUnit() {
        store.updateUnit(of: item, to: customUnit)
        editingCustomUnit = false
    }
}


// Selection hit testing consumes these frames inside a gesture callback, not
// while rendering. Publishing every geometry change back into SwiftUI creates
// a layout/update feedback loop during native List and keyboard animations.
private final class ShoppingItemFrameRegistry {
    var frames: [UUID: CGRect] = [:]
}
