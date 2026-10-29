import SwiftUI

struct SectionEditor: View {
    @ObservedObject var store: ShoppingStore
    let section: String
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var tint: String
    @State private var deleting = false
    @State private var error = false
    private let listID: UUID
    private let symbols = ["basket", "carrot", "leaf", "mug", "birthday.cake", "snowflake", "fish", "bubbles.and.sparkles", "waterbottle", "cabinet", "bag", "house", "heart", "star", "shippingbox"]

    init(store: ShoppingStore, section: String) {
        self.store = store; self.section = section; listID = store.selectedListID
        _name = State(initialValue: section)
        let appearance = store.currentList.sectionStyles?[section] ?? Theme.sectionAppearance(for: section, listTint: store.currentList.tintName)
        _symbol = State(initialValue: appearance.symbol)
        _tint = State(initialValue: appearance.tint)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(name, systemImage: symbol).font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.tint(for: tint))
                        .frame(maxWidth: .infinity, minHeight: 64)
                    TextField("שם המקטע", text: $name)
                }
                Section("צבע וסמל") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                        ForEach(Theme.listColors, id: \.name) { option in
                            Button { tint = option.name } label: {
                                Circle().fill(option.color).frame(width: 36, height: 36)
                                    .overlay { if tint == option.name { Image(systemName: "checkmark").foregroundStyle(.white) } }
                                    .frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(LocalizedStringKey(option.name))
                                .accessibilityAddTraits(tint == option.name ? .isSelected : [])
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                        ForEach(symbols, id: \.self) { value in
                            Button { symbol = value } label: {
                                Image(systemName: value).font(.title3).frame(minWidth: 44, minHeight: 44)
                                    .background(symbol == value ? Theme.tint(for: tint).opacity(0.15) : .clear,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityLabel(LocalizedStringKey(value))
                                .accessibilityAddTraits(symbol == value ? .isSelected : [])
                        }
                    }
                }
                Section {
                    Button("מחיקת מקטע", systemImage: "trash", role: .destructive) { deleting = true }
                }
            }
            .navigationTitle("עריכת מקטע").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        guard store.selectedListID == listID else { dismiss(); return }
                        if store.editSection(section, name: name, appearance: SectionAppearance(symbol: symbol, tint: tint)) { dismiss() }
                        else { error = true }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("לא ניתן לשמור את השם", isPresented: $error) {
                Button("סיום", role: .cancel) {}
            } message: { Text("בחרו שם אחר. ייתכן שמקטע בשם הזה כבר קיים או שהמקטע השתנה במכשיר אחר.") }
            .confirmationDialog("מחיקת מקטע", isPresented: $deleting, titleVisibility: .visible) {
                Button("מחיקת המקטע והעברה לאחר") { delete(includingItems: false) }
                Button("מחיקת המקטע והמוצרים שבו", role: .destructive) { delete(includingItems: true) }
                Button("ביטול", role: .cancel) {}
            } message: { Text("השינוי יחול גם ברשימה המשותפת. היסטוריית הקניות תישמר.") }
        }
    }

    private func delete(includingItems: Bool) {
        guard store.selectedListID == listID else { dismiss(); return }
        store.deleteSection(section, includingItems: includingItems)
        dismiss()
    }
}

struct SectionSettingsView: View {
    @ObservedObject var store: ShoppingStore
    @State private var editing: String?
    @State private var showingEditor = false
    var body: some View {
        List {
            ForEach(store.sectionNames.filter { $0 != "אחר" }, id: \.self) { section in
                Button { editing = section; showingEditor = true } label: {
                    let appearance = store.currentList.sectionStyles?[section] ?? Theme.sectionAppearance(for: section, listTint: store.currentList.tintName)
                    Label(section, systemImage: appearance.symbol).foregroundStyle(Theme.tint(for: appearance.tint))
                }
            }
            .onMove { store.moveSection(from: $0, to: $1) }
        }
        .sheet(isPresented: $showingEditor) { if let editing { SectionEditor(store: store, section: editing) } }
        .navigationTitle("ניהול מקטעים")
        .toolbar { EditButton() }
        .overlay {
            if store.sectionNames.count == 1 {
                ContentUnavailableView("אין מקטעים", systemImage: "square.grid.2x2", description: Text("אפשר ליצור מקטע מתפריט הרשימה."))
            }
        }
    }
}
