import SwiftUI
import UIKit

struct RecipeIngredientExchange: Decodable {
    static let group = "group.com.chaimalov.recipes.exchange"
    static let filename = "recipe-ingredients-v1.json"
    static let appURL = URL(string: "chaimalov-recipes://library")!

    struct Entry: Decodable, Identifiable {
        let id: UUID
        let title: String
        let updatedAt: Date
        let ingredients: [Ingredient]
    }

    struct Ingredient: Decodable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let original: String
        let amount: String
        let unit: String
        let notes: String
        let optional: Bool
        let uncertainty: String
        let wholeQuantity: Int?

        var shoppingQuantity: Int? {
            wholeQuantity.flatMap { (1...9999).contains($0) ? $0 : nil }
        }

        var shoppingUnit: String? {
            guard shoppingQuantity != nil, !unit.isEmpty, unit.count <= 24 else { return nil }
            return ShoppingInputParser.unit(for: unit) ?? unit
        }

        var measurement: String { [amount, unit].filter { !$0.isEmpty }.joined(separator: " ") }

        var shoppingNote: String {
            let sourceNote = shoppingQuantity == nil || (!unit.isEmpty && shoppingUnit == nil)
                ? (original.isEmpty ? measurement : original) : ""
            return [sourceNote, notes, optional ? "לא חובה במתכון" : ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    let schemaVersion: Int
    let recipes: [Entry]

    static func load() throws -> [Entry] {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let data = try Data(contentsOf: directory.appendingPathComponent(filename))
        let decoder = JSONDecoder()
        guard try decoder.decode(Header.self, from: data).schemaVersion == 1 else {
            throw CocoaError(.fileReadUnknown)
        }
        return try decoder.decode(Self.self, from: data).recipes
    }

    private struct Header: Decodable { let schemaVersion: Int }
}

struct RecipeIngredientImportView: View {
    let store: ShoppingStore
    let list: ShoppingList
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var entries: [RecipeIngredientExchange.Entry] = []
    @State private var selectedRecipe: UUID?
    @State private var selectedIngredients: Set<UUID> = []
    @State private var search = ""
    @State private var unavailable: Availability?
    @State private var importError: String?

    private enum Availability: Equatable {
        case appMissing, openRecipes, fileUnavailable

        var message: String {
            switch self {
            case .appMissing: "כדי לייבא מרכיבים, צריך להתקין את מתכונים באותו מכשיר."
            case .openRecipes: "יש לפתוח את מתכונים פעם אחת כדי לשתף את הספרייה."
            case .fileUnavailable: "אין גישה לספרייה. אפשר לפתוח את מתכונים ולנסות שוב."
            }
        }
    }

    var body: some View {
        NavigationStack(path: Binding(
            get: { selectedRecipe.map { [$0] } ?? [] },
            set: { selectedRecipe = $0.last }
        )) {
            Group {
                if let unavailable {
                    ContentUnavailableView {
                        Label("ספריית המתכונים", systemImage: "book.closed")
                    } description: {
                        Text(unavailable.message)
                    } actions: {
                        if unavailable != .appMissing {
                            Button("פתיחת מתכונים") { openURL(RecipeIngredientExchange.appURL) }
                        }
                        Button("ניסיון חוזר") { refresh() }
                    }
                } else if entries.isEmpty {
                    ContentUnavailableView {
                        Label("אין עדיין מתכונים", systemImage: "book.closed")
                    } description: {
                        Text("אפשר להוסיף מתכון באפליקציית מתכונים.")
                    } actions: {
                        Button("פתיחת מתכונים") { openURL(RecipeIngredientExchange.appURL) }
                    }
                } else {
                    List(entries.filter { search.isEmpty || $0.title.localizedStandardContains(search) }) { entry in
                        NavigationLink(value: entry.id) {
                            Text(entry.title)
                        }
                    }
                    .searchable(text: $search, prompt: "חיפוש מתכון")
                }
            }
            .navigationTitle("ייבוא מרכיבים")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } } }
            .navigationDestination(for: UUID.self) { id in
                if let entry = entries.first(where: { $0.id == id }) {
                    ingredients(entry)
                } else {
                    ContentUnavailableView("המתכון לא זמין", systemImage: "book.closed")
                }
            }
        }
        .onChange(of: phase, initial: true) { _, state in if state == .active { refresh() } }
        .onChange(of: selectedRecipe) { _, id in
            refresh()
            let ingredients = entries.first(where: { $0.id == id })?.ingredients ?? []
            selectedIngredients = Set(ingredients.filter { !$0.optional && $0.uncertainty.isEmpty }.map(\.id))
        }
        .alert("ייבוא המרכיבים", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) { Button("אישור", role: .cancel) {} } message: { Text(importError ?? "") }
    }

    private func ingredients(_ entry: RecipeIngredientExchange.Entry) -> some View {
        Group {
            if entry.ingredients.isEmpty {
                ContentUnavailableView("אין מצרכים במתכון הזה", systemImage: "list.bullet")
            } else {
                RecipeIngredientSelectionList(
                    ingredients: entry.ingredients,
                    tint: UIColor(Theme.tint(for: list.tintName)),
                    selection: $selectedIngredients
                )
            }
        }
        .navigationTitle(entry.title)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                confirm(entry)
            } label: {
                Text("הוספת מצרכים")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.tint(for: list.tintName))
            .disabled(selectedIngredients.isDisjoint(with: entry.ingredients.map(\.id)))
            .accessibilityHint("הוספה לרשימת \(list.name)")
            .frame(maxWidth: 540)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    private func confirm(_ shown: RecipeIngredientExchange.Entry) {
        refresh()
        guard let current = entries.first(where: { $0.id == shown.id }),
              current.updatedAt == shown.updatedAt else {
            selectedIngredients = []
            importError = "המתכון השתנה. בחר שוב את המרכיבים העדכניים."
            return
        }
        let chosen = current.ingredients.filter { selectedIngredients.contains($0.id) }
        guard !chosen.isEmpty else { return }
        do {
            try store.importRecipeIngredients(chosen, listID: list.id)
            dismiss()
        } catch ShoppingStore.RecipeImportError.incompatibleItem(let name) {
            importError = "\(name) כבר ברשימה בכמות או ביחידה שונה. יש להתאים את הפריט הקיים או לבטל את בחירת המרכיב."
        } catch ShoppingStore.RecipeImportError.listUnavailable {
            importError = "אין אפשרות להוסיף פריטים לרשימה הזו."
        } catch {
            importError = "שמירת המרכיבים נכשלה. אפשר לנסות שוב."
        }
    }

    private func refresh() {
        guard UIApplication.shared.canOpenURL(RecipeIngredientExchange.appURL) else {
            entries = []
            unavailable = .appMissing
            return
        }
        do {
            entries = try RecipeIngredientExchange.load().sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            unavailable = nil
        } catch let problem as CocoaError where problem.code == .fileReadNoSuchFile {
            entries = []
            unavailable = .openRecipes
        } catch {
            entries = []
            unavailable = .fileUnavailable
        }
    }
}

/// UIKit handles list selection and the two-finger sweep using its system interaction.
private struct RecipeIngredientSelectionList: UIViewControllerRepresentable {
    let ingredients: [RecipeIngredientExchange.Ingredient]
    let tint: UIColor
    @Binding var selection: Set<UUID>

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(ingredients: ingredients, selection: selection, tint: tint) { id, selected in
            if selected { selection.insert(id) }
            else { selection.remove(id) }
        }
    }

    final class Controller: UICollectionViewController {
        private var ingredients: [RecipeIngredientExchange.Ingredient] = []
        private var lookup: [UUID: RecipeIngredientExchange.Ingredient] = [:]
        private var selection = Set<UUID>()
        private var onSelection: ((UUID, Bool) -> Void)?
        private var source: UICollectionViewDiffableDataSource<Int, UUID>!

        init() {
            var layout = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            layout.footerMode = .supplementary
            super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: layout))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            collectionView.semanticContentAttribute = .forceRightToLeft
            collectionView.allowsMultipleSelection = true
            collectionView.allowsMultipleSelectionDuringEditing = true
            let rows = UICollectionView.CellRegistration<UICollectionViewListCell, RecipeIngredientExchange.Ingredient> {
                cell, _, ingredient in
                cell.configurationUpdateHandler = { cell, state in
                    guard let cell = cell as? UICollectionViewListCell else { return }
                    var content = UIListContentConfiguration.subtitleCell()
                    content.text = ingredient.name
                    content.textProperties.numberOfLines = 0
                    content.image = UIImage(systemName: state.isSelected ? "checkmark.square.fill" : "square")
                    content.imageProperties.tintColor = state.isSelected ? cell.tintColor : .secondaryLabel
                    let details = [ingredient.measurement, ingredient.notes,
                                   ingredient.optional ? "לא חובה" : "",
                                   ingredient.uncertainty.isEmpty ? "" : "כדאי לבדוק במתכון המקורי"]
                        .filter { !$0.isEmpty }
                    content.secondaryText = details.isEmpty ? nil : details.joined(separator: "\n")
                    content.secondaryTextProperties.numberOfLines = 0
                    content.secondaryTextProperties.color = .secondaryLabel
                    cell.contentConfiguration = content
                }
            }
            source = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: collectionView) {
                [weak self] collection, path, id in
                guard let item = self?.lookup[id] else { return nil }
                return collection.dequeueConfiguredReusableCell(using: rows, for: path, item: item)
            }
            let note = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
                elementKind: UICollectionView.elementKindSectionFooter
            ) { cell, _, _ in
                var content = UIListContentConfiguration.groupedFooter()
                content.text = "כמות שברית, טווח או כמות חסרה יישמרו בהערה. פריט כזה יופיע ברשימה עם ספירה של 1."
                content.textProperties.numberOfLines = 0
                cell.contentConfiguration = content
            }
            source.supplementaryViewProvider = { collection, _, path in
                collection.dequeueConfiguredReusableSupplementary(using: note, for: path)
            }
        }

        func update(ingredients: [RecipeIngredientExchange.Ingredient], selection: Set<UUID>, tint: UIColor,
                    onSelection: @escaping (UUID, Bool) -> Void) {
            loadViewIfNeeded()
            self.onSelection = onSelection
            self.selection = selection
            collectionView.tintColor = tint
            if self.ingredients != ingredients {
                let previous = lookup
                self.ingredients = ingredients
                lookup = Dictionary(ingredients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
                snapshot.appendSections([0])
                var seen = Set<UUID>()
                let ids = ingredients.map(\.id).filter { seen.insert($0).inserted }
                snapshot.appendItems(ids)
                snapshot.reconfigureItems(ids.filter { previous[$0] != nil && previous[$0] != lookup[$0] })
                source.apply(snapshot, animatingDifferences: false) { [weak self] in
                    self?.applySelection()
                }
            } else {
                applySelection()
            }
        }

        private func applySelection() {
            let selected = collectionView.indexPathsForSelectedItems ?? []
            let current = Set(selected.compactMap { source.itemIdentifier(for: $0) })
            for path in selected {
                if let id = source.itemIdentifier(for: path), !selection.contains(id) {
                    collectionView.deselectItem(at: path, animated: false)
                }
            }
            for id in selection.subtracting(current) {
                if let path = source.indexPath(for: id) {
                    collectionView.selectItem(at: path, animated: false, scrollPosition: [])
                }
            }
        }

        override func collectionView(_ collectionView: UICollectionView,
                                     shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool { true }

        override func collectionView(_ collectionView: UICollectionView,
                                     didSelectItemAt indexPath: IndexPath) {
            guard let id = source.itemIdentifier(for: indexPath) else { return }
            selection.insert(id)
            onSelection?(id, true)
        }

        override func collectionView(_ collectionView: UICollectionView,
                                     didDeselectItemAt indexPath: IndexPath) {
            guard let id = source.itemIdentifier(for: indexPath) else { return }
            selection.remove(id)
            onSelection?(id, false)
        }
    }
}
