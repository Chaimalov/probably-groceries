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

    struct Ingredient: Decodable, Identifiable {
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
    @State private var error: String?

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
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("אישור", role: .cancel) {} } message: { Text(error ?? "") }
    }

    private func ingredients(_ entry: RecipeIngredientExchange.Entry) -> some View {
        List {
            if !entry.ingredients.isEmpty {
                Section {
                    ForEach(entry.ingredients) { item in
                        Toggle(isOn: Binding(
                            get: { selectedIngredients.contains(item.id) },
                            set: { if $0 { selectedIngredients.insert(item.id) } else { selectedIngredients.remove(item.id) } }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                if !item.measurement.isEmpty { Text(item.measurement).foregroundStyle(.secondary) }
                                if !item.notes.isEmpty { Text(item.notes).font(.footnote).foregroundStyle(.secondary) }
                                if item.optional { Text("לא חובה").font(.caption).foregroundStyle(.secondary) }
                                if !item.uncertainty.isEmpty {
                                    Text("כדאי לבדוק במתכון המקורי").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("מרכיבים")
                } footer: {
                    Text("כמות שברית, טווח או כמות חסרה יישמרו בהערה. פריט כזה יופיע ברשימה עם ספירה של 1.")
                }
            } else {
                Text("אין מרכיבים במתכון הזה.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(entry.title)
        .safeAreaInset(edge: .bottom) {
            Button {
                confirm(entry)
            } label: {
                Text("הוספה ל\(list.name)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(selectedIngredients.isEmpty)
            .padding()
        }
    }

    private func confirm(_ shown: RecipeIngredientExchange.Entry) {
        refresh()
        guard let current = entries.first(where: { $0.id == shown.id }),
              current.updatedAt == shown.updatedAt else {
            selectedIngredients = []
            error = "המתכון השתנה. בחר שוב את המרכיבים העדכניים."
            return
        }
        let chosen = current.ingredients.filter { selectedIngredients.contains($0.id) }
        guard !chosen.isEmpty else { return }
        do {
            try store.importRecipeIngredients(chosen, listID: list.id)
            dismiss()
        } catch ShoppingStore.RecipeImportError.incompatibleItem(let name) {
            error = "\(name) כבר ברשימה בכמות או ביחידה שונה. יש להתאים את הפריט הקיים או לבטל את בחירת המרכיב."
        } catch ShoppingStore.RecipeImportError.listUnavailable {
            error = "אין אפשרות להוסיף פריטים לרשימה הזו."
        } catch {
            error = "שמירת המרכיבים נכשלה. אפשר לנסות שוב."
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
