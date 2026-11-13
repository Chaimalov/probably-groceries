import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

struct PredictionDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: PredictionDiagnostics
    @State private var export: PredictionDiagnosticFile?
    @State private var exportError: String?

    init(store: ShoppingStore) {
        _report = State(initialValue: store.predictionDiagnostics())
    }

    private var evaluation: PredictionDiagnostics.ListEvaluation? {
        report.evaluations.first { $0.listID == report.selectedListID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let export {
                        ShareLink(item: export, preview: SharePreview("נתוני אבחון להצעות")) {
                            Label("שיתוף נתוני אבחון להצעות", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("sharePredictionDiagnostics")
                    }
                    if let exportError {
                        Text(exportError).foregroundStyle(.red)
                        Button("ניסיון נוסף", action: prepareExport)
                    }
                    Text("הקובץ כולל שמות מוצרים, כמויות, תאריכי קנייה ומצב ההמלצות מכל הרשימות. ללא תמונות, הערות או פרטי חשבון.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("ברשימה הנוכחית") {
                    if let evaluation {
                        Text("\(evaluation.productsInHistory) מוצרים בהיסטוריה")
                        Text("\(evaluation.eligibleProducts) מוצרים זמינים להצעה")
                        if let count = evaluation.cachedRecommendationCount {
                            Text("\(count) המלצות בתוצאה השמורה")
                        } else {
                            Text("אין תוצאה שמורה")
                        }
                        if let outcome = evaluation.lastOutcome {
                            Text(outcome).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("פרטי ההצעות")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
            .onAppear(perform: prepareExport)
        }
    }

    private func prepareExport() {
        do {
            export = PredictionDiagnosticFile(data: try report.encoded())
            exportError = nil
        } catch { exportError = error.localizedDescription }
    }
}

private struct PredictionDiagnosticFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Groceries-Prediction-Diagnostics.json")
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
