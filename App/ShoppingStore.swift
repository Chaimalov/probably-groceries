import Combine
import Foundation
import UIKit

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var data: ShoppingData
    @Published private(set) var selectedListID: UUID
    @Published private(set) var storageError: String?
    private var loadFailed = false
    @Published private(set) var syncStatus: PersonalCloudSync.Status = .local

    private let fileURL: URL
    private let journalURL: URL
    private var lastJournaledData: ShoppingData
    var syncJournal: SyncJournal
    lazy var cloudSync = PersonalCloudSync(store: self)

    var sharedLists: [SharedListBinding] { syncJournal.sharedLists ?? [] }
    var currentShare: SharedListBinding? { sharedLists.first { $0.listID == selectedListID } }

    func registerSharedList(_ binding: SharedListBinding) {
        var bindings = sharedLists
        if let index = bindings.firstIndex(where: { $0.listID == binding.listID }) {
            var updated = binding
            updated.keys.formUnion(bindings[index].keys)
            bindings[index] = updated
        } else { bindings.append(binding) }
        syncJournal.sharedLists = bindings
        saveSyncMetadata()
    }

    // Each shared list has its own product identities and a globally unique
    // list ID. Two accounts' built-in default lists must never overwrite each other.
    func prepareCurrentListForSharing(ownerName: String) -> SharedListBinding {
        if let existing = currentShare { return existing }
        let oldID = selectedListID
        let newID = UUID()
        let keys = SharedListBinding.keys(in: data, listID: oldID)
        var productIDs: [UUID: UUID] = [:]
        for product in data.products where keys.contains("product_\(product.id.uuidString)") {
            var copy = product
            copy.id = UUID()
            productIDs[product.id] = copy.id
            data.products.append(copy)
        }
        if let index = data.lists.firstIndex(where: { $0.id == oldID }) { data.lists[index].id = newID }
        for index in data.items.indices where data.items[index].listID == oldID {
            data.items[index].listID = newID
            data.items[index].productID = productIDs[data.items[index].productID] ?? data.items[index].productID
        }
        for index in data.purchases.indices where data.purchases[index].listID == oldID {
            data.purchases[index].listID = newID
            data.purchases[index].productID = productIDs[data.purchases[index].productID] ?? data.purchases[index].productID
        }
        for index in data.deferrals.indices where data.deferrals[index].listID == oldID {
            data.deferrals[index].listID = newID
            data.deferrals[index].productID = productIDs[data.deferrals[index].productID] ?? data.deferrals[index].productID
        }
        var binding = SharedListBinding(listID: newID, zoneName: SharedListBinding.zoneName(for: newID),
                                        ownerName: ownerName, isOwner: true)
        binding.includeRecords(in: data)
        syncJournal.sharedLists = sharedLists + [binding]
        selectedListID = newID
        UserDefaults.standard.set(newID.uuidString, forKey: "selectedShoppingListID")
        persist()
        return binding
    }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let path = directory.appendingPathComponent("shopping.json")
        fileURL = path
        journalURL = directory.appendingPathComponent("sync-journal.json")
        let loadedData: ShoppingData
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                loadedData = try JSONDecoder().decode(ShoppingData.self, from: Data(contentsOf: path))
            } else { loadedData = ShoppingData() }
        } catch {
            loadedData = ShoppingData()
            loadFailed = true
            storageError = "לא ניתן לפתוח את הרשימה שנשמרה. הנתונים המקוריים לא הוחלפו."
        }
        let savedID = UserDefaults.standard.string(forKey: "selectedShoppingListID")
            .flatMap(UUID.init(uuidString:))
        let listID = loadedData.lists.contains(where: { $0.id == savedID })
            ? savedID! : loadedData.lists.first?.id ?? ShoppingList.defaultID
        data = loadedData
        lastJournaledData = loadedData
        syncJournal = (try? Data(contentsOf: journalURL))
            .flatMap { try? JSONDecoder().decode(SyncJournal.self, from: $0) } ?? SyncJournal()
        syncJournal.seed(loadedData)
        selectedListID = listID
        migrateLegacyPhotos()
        if let index = data.lists.firstIndex(where: {
            $0.id == ShoppingList.defaultID && $0.name == "Groceries"
        }) {
            data.lists[index].name = "קניות"
            persist()
        }
    }

    var currentList: ShoppingList {
        data.lists.first { $0.id == selectedListID }
            ?? ShoppingList(id: ShoppingList.defaultID, name: "קניות")
    }

    func selectList(_ id: UUID) {
        guard data.lists.contains(where: { $0.id == id }) else { return }
        selectedListID = id
        UserDefaults.standard.set(id.uuidString, forKey: "selectedShoppingListID")
    }

    func addList(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let list = ShoppingList(id: UUID(), name: name)
        data.lists.append(list)
        persist()
        selectList(list.id)
    }

    func renameCurrentList(to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = data.lists.firstIndex(where: { $0.id == selectedListID }) else { return }
        data.lists[index].name = name
        persist()
    }

    func setAppearance(tintName: String, symbolName: String) {
        guard let index = data.lists.firstIndex(where: { $0.id == selectedListID }),
              Theme.listColors.contains(where: { $0.name == tintName }),
              Theme.listSymbols.contains(symbolName) else { return }
        data.lists[index].tintName = tintName
        data.lists[index].symbolName = symbolName
        persist()
    }

    var items: [ShoppingItem] {
        let positions = ShoppingRouteOrder.positions(from: data.purchases.filter { $0.listID == selectedListID })
        return data.items.filter { $0.listID == selectedListID }.sorted { left, right in
            switch (left.manualOrder, right.manualOrder) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            switch (positions[left.productID], positions[right.productID]) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if left.addedAt != right.addedAt { return left.addedAt < right.addedAt }
                return left.id.uuidString < right.id.uuidString
            }
        }
    }
    var purchases: [Purchase] {
        data.purchases.filter { $0.listID == selectedListID }
            .sorted { $0.purchasedAt > $1.purchasedAt }
    }
    var recentPurchases: [Purchase] {
        Array(purchases.prefix(5))
    }

    func product(for id: UUID) -> Product? { data.products.first { $0.id == id } }

    func productBelongsToCurrentScope(_ product: Product) -> Bool {
        let key = "product_\(product.id.uuidString)"
        if let binding = currentShare { return binding.keys.contains(key) }
        return !sharedLists.contains { $0.keys.contains(key) }
    }

    func matchingProducts(_ query: String) -> [Product] {
        let value = Self.normalize(query)
        guard !value.isEmpty else { return [] }
        return data.products.filter {
            Self.normalize($0.name).localizedStandardContains(value) &&
            productBelongsToCurrentScope($0)
        }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func add(name: String, quantity: Int, category: String? = nil,
             department: String? = nil, urgent: Bool = false) {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        let normalized = Self.normalize(displayName)
        let productID: UUID
        if let existing = data.products.first(where: {
            Self.normalize($0.name) == normalized &&
            productBelongsToCurrentScope($0)
        }) {
            productID = existing.id
            if let category, !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let index = data.products.firstIndex(where: { $0.id == productID }) {
                data.products[index].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            let product = Product(id: UUID(), name: displayName, usualQuantity: max(1, quantity),
                                  category: category?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  department: nil)
            data.products.append(product)
            productID = product.id
        }
        if let index = data.items.firstIndex(where: {
            $0.productID == productID && $0.listID == selectedListID
        }) {
            data.items[index].quantity += max(1, quantity)
            data.items[index].isUrgent = data.items[index].isUrgent || urgent
            if let department { data.items[index].sectionName = department.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            data.items.append(ShoppingItem(id: UUID(), productID: productID,
                                           quantity: max(1, quantity), addedAt: .now,
                                           listID: selectedListID, isUrgent: urgent))
            data.items[data.items.count - 1].unit = product(for: productID)?.preferredUnit
            data.items[data.items.count - 1].sectionName = department?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? data.purchases.filter { $0.productID == productID && $0.listID == selectedListID }
                    .max(by: { $0.purchasedAt < $1.purchasedAt })?.sectionName
        }
        data.deferrals.removeAll { $0.productID == productID && $0.listID == selectedListID }
        persist()
    }

    func add(_ suggestion: Suggestion) {
        add(name: suggestion.product.name, quantity: suggestion.quantity)
    }

    private func recordRemoval(_ item: ShoppingItem) {
        data.deferrals.removeAll { $0.productID == item.productID && $0.listID == item.listID }
        var removal = Deferral(productID: item.productID, until: .now.addingTimeInterval(3 * 86400), listID: item.listID)
        removal.recordedAt = .now
        data.deferrals.append(removal)
    }

    func remove(_ item: ShoppingItem) {
        recordRemoval(item)
        data.items.removeAll { $0.id == item.id }
        if let name = item.photoFilename { try? FileManager.default.removeItem(at: photoDirectory.appendingPathComponent(name)) }
        persist()
    }

    func updateNote(of item: ShoppingItem, to value: String) {
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        data.items[index].note = value.isEmpty ? nil : value
        persist()
    }

    private var photoDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("ItemPhotos", isDirectory: true)
    }

    func photoURL(for item: ShoppingItem) -> URL? {
        if let bytes = item.photoData {
            let url = photoDirectory.appendingPathComponent("\(item.id.uuidString)-synced.jpg")
            try? FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
            if (try? Data(contentsOf: url)) != bytes { try? bytes.write(to: url, options: .atomic) }
            return url
        }
        if let name = item.photoFilename {
            let url = photoDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func migrateLegacyPhotos() {
        guard !loadFailed else { return }
        var changed = false
        for index in data.items.indices where data.items[index].photoData == nil {
            if let name = data.items[index].photoFilename,
               let bytes = try? Data(contentsOf: photoDirectory.appendingPathComponent(name)),
               let image = UIImage(data: bytes), let encoded = ItemPhotoEncoder.encode(image) {
                data.items[index].photoData = encoded; changed = true
            }
        }
        for index in data.purchases.indices where data.purchases[index].photoData == nil {
            if let name = data.purchases[index].photoFilename,
               let bytes = try? Data(contentsOf: photoDirectory.appendingPathComponent(name)),
               let image = UIImage(data: bytes), let encoded = ItemPhotoEncoder.encode(image) {
                data.purchases[index].photoData = encoded; changed = true
            }
        }
        if changed { persist() }
    }

    func setPhoto(_ bytes: Data, for item: ShoppingItem) {
        guard let image = UIImage(data: bytes),
              let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        guard let jpeg = ItemPhotoEncoder.encode(image) else {
            storageError = "לא ניתן לצרף את התמונה. נסה תמונה אחרת."
            return
        }
        do {
            try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
            let name = "\(item.id.uuidString).jpg"
            try jpeg.write(to: photoDirectory.appendingPathComponent(name), options: .atomic)
            data.items[index].photoFilename = name
            data.items[index].photoData = jpeg
            persist()
        } catch { storageError = "לא ניתן לשמור את התמונה. נסה שוב." }
    }

    func removePhoto(from item: ShoppingItem) {
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        let name = data.items[index].photoFilename
        data.items[index].photoFilename = nil
        data.items[index].photoData = nil
        if let name { try? FileManager.default.removeItem(at: photoDirectory.appendingPathComponent(name)) }
        persist()
    }

    func rename(_ item: ShoppingItem, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = data.products.firstIndex(where: { $0.id == item.productID }),
              !data.products.contains(where: {
                  $0.id != item.productID && productBelongsToCurrentScope($0) &&
                    Self.normalize($0.name) == Self.normalize(name)
              }) else { return }
        data.products[index].name = name
        persist()
    }

    func addSection(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = data.lists.firstIndex(where: { $0.id == selectedListID }),
              !data.lists[index].sections.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }
        data.lists[index].sections.append(name)
        persist()
    }

    func moveSection(from source: IndexSet, to destination: Int) {
        guard let index = data.lists.firstIndex(where: { $0.id == selectedListID }) else { return }
        var sections = data.lists[index].sections
        for item in items {
            let name = section(for: item)
            if name != "אחר" && !sections.contains(name) { sections.append(name) }
        }
        sections.move(fromOffsets: source, toOffset: destination)
        data.lists[index].sections = sections
        persist()
    }

    func move(_ itemID: UUID, toSection section: String) {
        guard let index = data.items.firstIndex(where: { $0.id == itemID && $0.listID == selectedListID }) else { return }
        data.items[index].sectionName = section == "אחר" ? "" : section
        persist()
    }

    func section(for item: ShoppingItem) -> String {
        if let explicit = item.sectionName {
            let name = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "אחר" : name
        }
        let name = [product(for: item.productID)?.department, product(for: item.productID)?.category]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        return name.isEmpty ? "אחר" : name
    }

    func place(_ itemID: UUID, inSection destination: String?, before targetID: UUID? = nil) {
        place([itemID], inSection: destination, relativeTo: targetID)
    }

    // Commit the entire drag in one persistence/sync operation. Keep the group's
    // visual order supplied by the caller, rather than finger pickup order.
    func place(_ itemIDs: [UUID], inSection destination: String?,
               relativeTo targetID: UUID? = nil, after: Bool = false) {
        let requested = Set(itemIDs)
        let validIDs = Set(items.map(\.id))
        var seen = Set<UUID>()
        let moving = itemIDs.filter { validIDs.contains($0) && seen.insert($0).inserted }
        guard !moving.isEmpty, targetID.map({ !requested.contains($0) }) ?? true,
              targetID == nil || items.contains(where: { $0.id == targetID }) else { return }
        var ordered = items.map(\.id).filter { !requested.contains($0) }
        for index in data.items.indices
            where data.items[index].listID == selectedListID && requested.contains(data.items[index].id) {
            if let destination {
                data.items[index].sectionName = destination == "אחר" ? "" : destination
            }
        }
        if let targetID, let position = ordered.firstIndex(of: targetID) {
            ordered.insert(contentsOf: moving, at: position + (after ? 1 : 0))
        } else if let destination,
                  let last = ordered.lastIndex(where: { id in
                      guard let item = data.items.first(where: { $0.id == id }) else { return false }
                      return section(for: item) == destination
                  }) {
            ordered.insert(contentsOf: moving, at: last + 1)
        } else {
            ordered.append(contentsOf: moving)
        }
        applyManualOrder(ordered)
    }

    func placeSection(_ name: String, relativeTo target: String, after: Bool) {
        guard name != target,
              let index = data.lists.firstIndex(where: { $0.id == selectedListID }) else { return }
        var sections = data.lists[index].sections
        for item in items {
            let used = section(for: item)
            if !sections.contains(used) { sections.append(used) }
        }
        guard sections.contains(name), sections.contains(target) else { return }
        sections.removeAll { $0 == name }
        let position = sections.firstIndex(of: target).map { $0 + (after ? 1 : 0) } ?? sections.count
        sections.insert(name, at: position)
        data.lists[index].sections = sections
        persist()
    }

    private func applyManualOrder(_ orderedIDs: [UUID]) {
        for (order, id) in orderedIDs.enumerated() {
            guard let index = data.items.firstIndex(where: { $0.id == id }) else { continue }
            data.items[index].manualOrder = order
        }
        persist()
    }

    func move(from source: IndexSet, to destination: Int, inSection section: String?) {
        let ordered = items
        var sectionIDs = ordered.filter { item in
            section == nil || self.section(for: item) == section
        }.map(\.id)
        sectionIDs.move(fromOffsets: source, toOffset: destination)
        var iterator = sectionIDs.makeIterator()
        let merged = ordered.map { item in
            if section == nil || self.section(for: item) == section {
                return iterator.next()!
            }
            return item.id
        }
        applyManualOrder(merged)
    }

    func setGrouping(for itemID: UUID, department: String?, category: String?) {
        guard let itemIndex = data.items.firstIndex(where: { $0.id == itemID && $0.listID == selectedListID }),
              let index = data.products.firstIndex(where: { $0.id == data.items[itemIndex].productID }) else { return }
        let trimmedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDepartment = department?.trimmingCharacters(in: .whitespacesAndNewlines)
        data.products[index].category = trimmedCategory?.isEmpty == false ? trimmedCategory : nil
        data.items[itemIndex].sectionName = trimmedDepartment?.isEmpty == false ? trimmedDepartment : ""
        persist()
    }

    func toggleUrgent(_ item: ShoppingItem) {
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        data.items[index].isUrgent.toggle()
        persist()
    }

    func setUrgent(_ urgent: Bool, for ids: Set<UUID>) {
        for index in data.items.indices where ids.contains(data.items[index].id) {
            data.items[index].isUrgent = urgent
        }
        persist()
    }

    func remove(_ ids: Set<UUID>) {
        for item in data.items where ids.contains(item.id) {
            recordRemoval(item)
            if let name = item.photoFilename {
                try? FileManager.default.removeItem(at: photoDirectory.appendingPathComponent(name))
            }
        }
        data.items.removeAll { ids.contains($0.id) }
        persist()
    }

    var categories: [String] {
        Array(Set(data.products.compactMap(\.category)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var departments: [String] {
        Array(Set(data.products.compactMap(\.department)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func updateQuantity(of item: ShoppingItem, to quantity: Int) {
        guard (1...9999).contains(quantity),
              let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        data.items[index].quantity = quantity
        persist()
    }

    func updateUnit(of item: ShoppingItem, to rawValue: String?) {
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = trimmed?.isEmpty == false ? String(trimmed!.prefix(24)) : nil
        data.items[index].unit = unit
        if let productIndex = data.products.firstIndex(where: { $0.id == item.productID }) {
            data.products[productIndex].preferredUnit = unit
        }
        persist()
    }

    func buy(_ item: ShoppingItem) {
        guard let current = data.items.first(where: { $0.id == item.id }) else { return }
        let originalOrder = items.firstIndex(where: { $0.id == current.id })
        // Freeze the remaining route before new learning changes positions.
        for (order, visible) in items.enumerated() {
            if let index = data.items.firstIndex(where: { $0.id == visible.id }) {
                data.items[index].manualOrder = order
            }
        }
        data.items.removeAll { $0.id == current.id }
        // Concurrent check-offs of the same active row converge to one event.
        data.purchases.append(Purchase(id: current.id, productID: current.productID,
                                       quantity: current.quantity, purchasedAt: .now,
                                       sourceItemID: current.id, listID: current.listID,
                                       wasUrgent: current.isUrgent))
        let actor = UserDefaults.standard.string(forKey: "shoppingActorID") ?? UUID().uuidString
        UserDefaults.standard.set(actor, forKey: "shoppingActorID")
        data.purchases[data.purchases.count - 1].actorID = actor
        data.purchases[data.purchases.count - 1].originalOrder = originalOrder
        data.purchases[data.purchases.count - 1].photoData = current.photoData
        data.purchases[data.purchases.count - 1].note = current.note
        data.purchases[data.purchases.count - 1].photoFilename = current.photoFilename
        data.purchases[data.purchases.count - 1].unit = current.unit
        data.purchases[data.purchases.count - 1].sectionName = current.sectionName
        data.purchases[data.purchases.count - 1].shoppingPlace = current.shoppingPlace
        updateUsualQuantity(for: current.productID)
        persist()
    }

    func correctQuantity(of purchase: Purchase, to quantity: Int) {
        guard (1...9999).contains(quantity),
              let index = data.purchases.firstIndex(where: { $0.id == purchase.id }) else { return }
        data.purchases[index].quantity = quantity
        updateUsualQuantity(for: purchase.productID)
        persist()
    }

    func undo(_ purchase: Purchase) {
        guard let current = data.purchases.first(where: { $0.id == purchase.id }) else { return }
        data.purchases.removeAll { $0.id == purchase.id }
        if let index = data.items.firstIndex(where: {
            $0.productID == current.productID && $0.listID == current.listID
        }) {
            data.items[index].quantity += current.quantity
            data.items[index].isUrgent = data.items[index].isUrgent || current.wasUrgent
            data.items[index].photoData = data.items[index].photoData ?? current.photoData
            data.items[index].note = data.items[index].note ?? current.note
            data.items[index].photoFilename = data.items[index].photoFilename ?? current.photoFilename
            data.items[index].unit = data.items[index].unit ?? current.unit
            data.items[index].sectionName = data.items[index].sectionName ?? current.sectionName
            data.items[index].shoppingPlace = data.items[index].shoppingPlace ?? current.shoppingPlace
        } else {
            data.items.append(ShoppingItem(id: current.sourceItemID,
                                           productID: current.productID,
                                           quantity: current.quantity, addedAt: .now,
                                           listID: current.listID, isUrgent: current.wasUrgent))
            data.items[data.items.count - 1].manualOrder = current.originalOrder
            data.items[data.items.count - 1].photoData = current.photoData
            data.items[data.items.count - 1].note = current.note
            data.items[data.items.count - 1].photoFilename = current.photoFilename
            data.items[data.items.count - 1].unit = current.unit
            data.items[data.items.count - 1].sectionName = current.sectionName
            data.items[data.items.count - 1].shoppingPlace = current.shoppingPlace
        }
        updateUsualQuantity(for: current.productID)
        persist()
    }

    func deferSuggestion(_ suggestion: Suggestion) {
        data.deferrals.removeAll { $0.productID == suggestion.id && $0.listID == selectedListID }
        data.deferrals.append(Deferral(productID: suggestion.id,
                                       until: Calendar.current.date(byAdding: .day, value: 3, to: .now)!,
                                       listID: selectedListID))
        persist()
    }

    var predictionEvaluations: [PredictionEvaluation] {
        PredictionEngine.evaluate(data, listID: selectedListID)
    }

    var suggestions: [Suggestion] {
        let positions = ShoppingRouteOrder.positions(from: data.purchases.filter { $0.listID == selectedListID })
        return predictionEvaluations.compactMap(\.suggestion).sorted { left, right in
            switch (positions[left.id], positions[right.id]) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if left.progress != right.progress { return left.progress > right.progress }
                return left.product.name.localizedStandardCompare(right.product.name) == .orderedAscending
            }
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func updateUsualQuantity(for productID: UUID) {
        guard let index = data.products.firstIndex(where: { $0.id == productID }) else { return }
        data.products[index].usualQuantity = data.purchases
            .filter { $0.productID == productID }
            .max(by: { $0.purchasedAt < $1.purchasedAt })?.quantity ?? 1
    }

    func applyDraftData(_ updated: ShoppingData) -> Bool {
        guard !loadFailed else { return false }
        data = updated
        persist()
        return storageError == nil
    }

    func updatePlace(of item: ShoppingItem, to value: String) {
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        let place = value.trimmingCharacters(in: .whitespacesAndNewlines)
        data.items[index].shoppingPlace = place.isEmpty ? nil : place
        persist()
    }

    func persist() {
        guard !loadFailed else { return }
        syncJournal.recordChanges(from: lastJournaledData, to: data)
        if var bindings = syncJournal.sharedLists {
            for index in bindings.indices { bindings[index].includeRecords(in: data) }
            syncJournal.sharedLists = bindings
        }
        lastJournaledData = data
        saveLocal()
        cloudSync.schedule()
    }

    private func saveLocal() {
        guard !loadFailed else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
            try JSONEncoder().encode(syncJournal).write(to: journalURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "השינויים עדיין לא נשמרו במכשיר. נסה שוב."
        }
    }

    func retryLocalSave() { saveLocal() }

    func saveSyncMetadata() { saveLocal() }
    func updateSyncStatus(_ status: PersonalCloudSync.Status) { syncStatus = status }

    func mergeRemote(_ revisions: [SyncRevision]) {
        guard !loadFailed else { return }
        var changed = false
        for revision in revisions {
            changed = syncJournal.merge(revision, into: &data) || changed
        }
        guard changed else { return }
        lastJournaledData = data
        if !data.lists.contains(where: { $0.id == selectedListID }) {
            selectedListID = data.lists.first?.id ?? ShoppingList.defaultID
        }
        saveLocal()
    }
}

