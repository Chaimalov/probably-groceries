import SwiftUI

struct ListAppearanceEditor: View {
    @ObservedObject var store: ShoppingStore
    @Environment(\.dismiss) private var dismiss
    @State private var tintName: String
    @State private var symbolName: String

    init(store: ShoppingStore) {
        self.store = store
        _tintName = State(initialValue: store.currentList.tintName)
        _symbolName = State(initialValue: store.currentList.symbolName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(store.currentList.name, systemImage: symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.tint(for: tintName))
                        .frame(maxWidth: .infinity, minHeight: 76)
                }
                Section("צבע הרשימה") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 18) {
                        ForEach(Theme.listColors, id: \.name) { option in
                            Button {
                                tintName = option.name
                            } label: {
                                Circle().fill(option.color)
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        if tintName == option.name {
                                            Image(systemName: "checkmark")
                                                .font(.headline.bold()).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("צבע \(option.name)")
                            .accessibilityAddTraits(tintName == option.name ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section("סמל הרשימה") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Theme.listSymbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(symbolName == symbol ? Theme.tint(for: tintName).opacity(0.18) : .clear,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("סמל \(symbol)")
                            .accessibilityAddTraits(symbolName == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("מראה הרשימה")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.tint(for: tintName))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        store.setAppearance(tintName: tintName, symbolName: symbolName)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
