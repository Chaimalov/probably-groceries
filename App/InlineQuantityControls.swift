import SwiftUI

// Both new and saved rows use the same quantity editor. It appears only on demand.
struct InlineQuantityControls: View {
    private static let units = ["יחידות", "חבילות", "ליטרים", "מ״ל", "ק״ג", "גרם", "בקבוקים", "קופסאות", "שקיות", "גלילים"]
    @Binding var quantity: Int
    @Binding var unit: String?
    var isNew = false
    @State private var customUnit = ""
    @State private var editingCustomUnit = false
    @FocusState private var customUnitFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { stepper; unitPicker }
                VStack(alignment: .leading, spacing: 4) { stepper; unitPicker }
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
            }
        }
        .buttonStyle(.borderless)
        .tint(Color.primary)
    }

    private var stepper: some View {
        HStack(spacing: 4) {
            Button { quantity = max(1, quantity - 1) } label: {
                Image(systemName: "minus.circle").font(.title3)
            }
            .disabled(quantity <= 1)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(isNew ? "הפחתת כמות למוצר חדש" : "הפחתת כמות")
            Text("\(quantity)")
                .monospacedDigit().font(.body)
                .accessibilityIdentifier(isNew ? "newItemQuantity" : "inlineQuantity")
            Button { quantity = min(9999, quantity + 1) } label: {
                Image(systemName: "plus.circle").font(.title3)
            }
            .disabled(quantity >= 9999)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(isNew ? "הגדלת כמות למוצר חדש" : "הגדלת כמות")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var unitPicker: some View {
        Menu {
            Button("ללא יחידה") { unit = nil }
            ForEach(Self.units, id: \.self) { value in
                Button(value) { unit = value }
            }
            Button("יחידה אחרת…", systemImage: "pencil") {
                customUnit = unit ?? ""
                editingCustomUnit = true
                customUnitFocused = true
            }
        } label: {
            Label(unit ?? "יחידת מידה", systemImage: "chevron.down")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("בחירת יחידת מידה")
        .accessibilityValue(unit ?? "ללא יחידה")
    }

    private func saveCustomUnit() {
        let value = customUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        unit = value.isEmpty ? nil : value
        editingCustomUnit = false
        customUnitFocused = false
    }
}


/// One visual treatment for optional tools in both the draft and saved-row editor.
struct ShoppingToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
