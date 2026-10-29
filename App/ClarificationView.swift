import SwiftUI

// One focused question and answer beside the existing item photo/note.
// Uses the same offline persistence and CloudKit item record as the request.
struct ClarificationView: View {
    @ObservedObject var store: ShoppingStore
    let item: ShoppingItem
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var conflict = false
    @State private var baseline: ItemClarification?
    @State private var sending = false

    private var current: ShoppingItem? { store.data.items.first { $0.id == item.id && $0.listID == item.listID } }

    var body: some View {
        NavigationStack {
            Form {
                if let current {
                    Section {
                        Text(store.product(for: current.productID)?.name ?? "מוצר").font(.headline)
                        if let note = current.note, !note.isEmpty { Text(note).foregroundStyle(.secondary) }
                        if current.photoData != nil || current.photoFilename != nil {
                            ItemPhotoThumbnail(bytes: current.photoData, fileURL: store.legacyPhotoURL(for: current),
                                               name: "", fullImage: true).frame(maxHeight: 200)
                        }
                    }
                    Section("השאלה") {
                        if let clarification = current.clarification { Text(clarification.question) }
                        else { TextField("למשל: ספריי או אבקה?", text: $question, axis: .vertical).lineLimit(2...5) }
                    }
                    if let clarification = current.clarification {
                        Section("התשובה") {
                            if let reply = clarification.answer { Text(reply) }
                            else {
                                TextField("תשובה קצרה…", text: $answer, axis: .vertical).lineLimit(2...5)
                                Button("שמירת תשובה") {
                                    save(ItemClarification(question: clarification.question, answer: answer.trimmingCharacters(in: .whitespacesAndNewlines)))
                                }.disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                            }
                        }
                        Section {
                            Button(clarification.resolved ? "פתיחת הבירור מחדש" : "הכול ברור") {
                                var updated = clarification; updated.resolved.toggle(); save(updated)
                            }.disabled(sending)
                        }
                    } else {
                        Button("שמירת שאלה ברשימה") {
                            save(ItemClarification(question: question.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }.disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    }
                    Section {
                        Text("השאלה והתשובה נשמרות ליד המוצר ומסתנכרנות עם הרשימה. לצילום או לצירוף תמונה, פתחו את פרטי המוצר.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if store.storageError != nil {
                            Text("עדיין לא נשמר במכשיר").foregroundStyle(.red)
                            Button("ניסיון נוסף") { store.retryLocalSave() }
                        } else if store.syncStatus != .current {
                            Text("נשמר במכשיר; הסנכרון ימשיך כשיהיה חיבור.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("המוצר כבר אינו ברשימה")
                }
            }
            .navigationTitle("צריך בירור").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } } }
            .onAppear { baseline = current?.clarification }
            .alert("הבירור התעדכן", isPresented: $conflict) {
                Button("סיום", role: .cancel) { baseline = current?.clarification }
            } message: { Text("המידע השתנה במכשיר אחר. הטקסט שהקלדת נשמר כאן; בדקו את העדכון לפני שמירה נוספת.") }
        }
    }

    private func save(_ value: ItemClarification) {
        guard let current else { return }
        guard current.clarification == baseline else { conflict = true; return }
        store.setClarification(value, for: current)
        baseline = value
        sending = true
        Task {
            await store.cloudSync.synchronize()
            sending = false
        }
    }
}
