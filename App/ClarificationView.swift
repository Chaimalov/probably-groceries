import SwiftUI
import PhotosUI
import AVFoundation

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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraDenied = false

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
                    Section {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("צירוף תמונה", systemImage: "photo.badge.plus")
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("צילום", systemImage: "camera") {
                                Task {
                                    if await AVCaptureDevice.requestAccess(for: .video) { showingCamera = true }
                                    else { cameraDenied = true }
                                }
                            }
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
                        Text("השאלה, התשובה והתמונה נשמרות ליד המוצר ומסתנכרנות עם הרשימה.")
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
            .sheet(isPresented: $showingCamera) { ItemCamera { if let current { store.setPhoto($0, for: current) } } }
            .onChange(of: selectedPhoto) { _, selection in
                guard let selection else { return }
                Task {
                    if let bytes = try? await selection.loadTransferable(type: Data.self),
                       selectedPhoto == selection, let current { store.setPhoto(bytes, for: current) }
                }
            }
            .alert("אין גישה למצלמה", isPresented: $cameraDenied) {
                Button("הגדרות") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("ביטול", role: .cancel) {}
            } message: { Text("אפשר לאפשר גישה בהגדרות או לבחור תמונה מהספרייה.") }
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
