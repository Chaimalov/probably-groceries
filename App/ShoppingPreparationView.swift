import SwiftUI
import PhotosUI
import AVFoundation

struct ShoppingPreparationView: View {
    @ObservedObject var store: ShoppingStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ShoppingDraft
    @State private var filter = "הכול"
    @State private var manualName = ""
    @State private var details: ShoppingItem?
    @State private var draftDetails: DraftEntry?

    init(store: ShoppingStore) {
        self.store = store
        let saved = store.shoppingDraft()
        _draft = State(initialValue: saved)
        _manualName = State(initialValue: saved.unfinishedName ?? "")
    }
    private var places: [String] {
        Array(Set(store.items.compactMap(\.shoppingPlace) + draft.entries.compactMap(\.place))).filter { !$0.isEmpty }.sorted()
    }
    private func visible(_ place: String?) -> Bool {
        filter == "הכול" || (filter == "ללא מקום" ? place == nil || place == "" : place == filter)
    }
    var body: some View {
        NavigationStack {
            List {
                if !places.isEmpty {
                    Picker("מקום קנייה", selection: $filter) {
                        Text("הכול").tag("הכול")
                        Text("ללא מקום").tag("ללא מקום")
                        ForEach(places, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("נשארו ברשימה") {
                    ForEach(store.items.filter { visible($0.shoppingPlace) }) { item in
                        Button { details = item } label: {
                            HStack {
                                Text(store.product(for: item.productID)?.name ?? "מוצר")
                                Spacer()
                                Text("×\(item.quantity) \(item.unit ?? "")").foregroundStyle(.secondary)
                                Image(systemName: "info.circle")
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if store.items.isEmpty { Text("אין מוצרים שנותרו").foregroundStyle(.secondary) }
                }
                Section("השלמות מוצעות") {
                    ForEach($draft.entries) { $entry in
                        if visible(entry.place) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("שם המוצר", text: $entry.name)
                                    Button {
                                        entry.included.toggle()
                                    } label: {
                                        Image(systemName: entry.included ? "minus.circle" : "arrow.uturn.backward")
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(entry.included ? "החרגת \(entry.name)" : "החזרת \(entry.name)")
                                }
                                if entry.included {
                                    HStack {
                                        Text("×\(entry.quantity) \(entry.unit ?? "")").foregroundStyle(.secondary)
                                        Spacer()
                                        Button("פרטי מוצר", systemImage: "info.circle") { draftDetails = entry }
                                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    if let reason = entry.reason { Text(LocalizedStringKey(reason)).font(.caption).foregroundStyle(.secondary) }
                                }

                            }
                            .foregroundStyle(entry.included ? .primary : .secondary)
                        }
                    }
                    if draft.entries.isEmpty {
                        Text("אפשר להוסיף מוצרים. הצעות יופיעו לאחר כמה קניות חוזרות.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("מוצר נוסף", text: $manualName).submitLabel(.next).onSubmit(addManual)
                    Button("הוספת מוצר", systemImage: "plus", action: addManual)
                        .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = store.storageError { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
                if filter != "הכול" {
                    Text("האישור כולל את כל הרשימה").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("קנייה חדשה")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("אישור") {
                        addManual()
                        if store.confirmDraft(draft) { dismiss() }
                    }
                }
            }
            .onChange(of: manualName) { _, value in
                draft.unfinishedName = value
                store.saveDraft(draft)
            }
            .onChange(of: draft) { _, value in store.saveDraft(value) }
            .sheet(item: $draftDetails) { selected in
                if let index = draft.entries.firstIndex(where: { $0.id == selected.id }) {
                    DraftEntryDetails(entry: $draft.entries[index], sections: store.currentList.sections)
                }
            }
            .sheet(item: $details) { ItemDetailsSheet(store: store, item: $0) }
        }
    }
    private func addManual() {
        let parsed = ShoppingInputParser.parse(manualName)
        guard !parsed.name.isEmpty else { return }
        draft.entries.append(DraftEntry(name: parsed.name, quantity: parsed.quantity, unit: parsed.unit))
        manualName = ""
        draft.unfinishedName = nil
        store.saveDraft(draft)
    }
}

struct ItemDetailsSheet: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @Environment(\.dismiss) private var dismiss
    @State private var place = ""
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    private func saveName() {
        guard store.items.contains(where: { $0.id == item.id }) else { return }
        store.rename(item, to: name)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let current = store.items.first(where: { $0.id == item.id }) {
                    TextField("שם המוצר", text: $name)
                        .focused($nameFocused).submitLabel(.done).onSubmit(saveName)
                        .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
                    ItemInlineDetails(store: store, item: current)
                    Section("מקום קנייה") {
                        TextField("אופציונלי", text: $place)
                            .onChange(of: place) { _, value in store.updatePlace(of: current, to: value) }
                    }
                    Section {
                        CategoryEditorLink(store: store, item: current)
                    }
                } else { Text("המוצר כבר אינו ברשימה") }
            }
            .navigationTitle(store.product(for: item.productID)?.name ?? "פרטי מוצר")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגירה", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .onAppear {
                place = item.shoppingPlace ?? ""
                name = store.product(for: item.productID)?.name ?? ""
            }
            .onDisappear(perform: saveName)
        }
    }
}

private struct CategoryEditorLink: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @State private var showing = false
    var body: some View {
        Button("מקטע: \(store.section(for: item))") { showing = true }
            .sheet(isPresented: $showing) { CategoryEditor(store: store, item: item) }
    }
}

private struct DraftEntryDetails: View {
    @Binding var entry: DraftEntry
    let sections: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var photoExpanded = false
    @State private var error: String?

    private func optionalText(_ keyPath: WritableKeyPath<DraftEntry, String?>) -> Binding<String> {
        Binding(get: { entry[keyPath: keyPath] ?? "" }, set: { entry[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("שם המוצר", text: $entry.name)
                Stepper("כמות: \(entry.quantity)", value: $entry.quantity, in: 1...9999)
                TextField("יחידת מידה", text: optionalText(\.unit))
                TextField("הערה", text: optionalText(\.note), axis: .vertical)
                TextField("מקום קנייה (אופציונלי)", text: optionalText(\.place))
                Picker("מקטע", selection: optionalText(\.section)) {
                    Text("ללא מקטע").tag("")
                    ForEach(Array(Set(sections + [entry.section].compactMap { $0 })).sorted(), id: \.self) { Text($0).tag($0) }
                }
                if let bytes = entry.photoData, let image = UIImage(data: bytes) {
                    Button { photoExpanded = true } label: {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    }.accessibilityLabel("הגדלת תמונת המוצר")
                    Button("הסרת תמונה", systemImage: "trash", role: .destructive) { entry.photoData = nil }
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("צירוף תמונה", systemImage: "photo.badge.plus")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("צילום", systemImage: "camera") {
                        Task {
                            if await AVCaptureDevice.requestAccess(for: .video) { camera = true }
                            else { error = "אין גישה למצלמה. אפשר לאפשר גישה בהגדרות או לבחור תמונה." }
                        }
                    }
                }
            }
            .navigationTitle("פרטי מוצר")
            .toolbar { Button("סגירה", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
            .onChange(of: photo) { _, selected in
                guard let selected else { return }
                Task {
                    if let bytes = try? await selected.loadTransferable(type: Data.self) { attach(bytes) }
                    else { error = "לא ניתן לטעון את התמונה. נסה שוב." }
                }
            }
            .sheet(isPresented: $camera) { ItemCamera(onPhoto: attach) }
            .sheet(isPresented: $photoExpanded) {
                if let bytes = entry.photoData, let image = UIImage(data: bytes) {
                    NavigationStack {
                        Image(uiImage: image).resizable().scaledToFit()
                            .toolbar { Button("סגירה", systemImage: "xmark") { photoExpanded = false }.labelStyle(.iconOnly) }
                    }
                }
            }
            .alert("לא ניתן לצרף תמונה", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("סגירה", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func attach(_ bytes: Data) {
        guard let image = UIImage(data: bytes), let encoded = ItemPhotoEncoder.encode(image) else {
            error = "התמונה אינה ניתנת לשמירה. נסה תמונה אחרת."
            return
        }
        entry.photoData = encoded
    }
}
