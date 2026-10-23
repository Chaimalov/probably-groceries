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

    private var evaluations: [PredictionDiagnostics.Evaluation] {
        report.evaluations.first { $0.listID == report.selectedListID }?.products ?? []
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
                    Text("הקובץ כולל שמות מוצרים, כמויות, תאריכי קנייה וחישובי הצעות מכל הרשימות. ללא תמונות, הערות או פרטי חשבון.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("ברשימה הנוכחית") {
                    if evaluations.isEmpty {
                        Text("אין עדיין היסטוריית קניות").foregroundStyle(.secondary)
                    }
                    ForEach(evaluations, id: \.productID) { evaluation in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(report.shoppingData.products.first { $0.id == evaluation.productID }?.name ?? "")
                                .font(.headline)
                            Text(evaluation.reason).foregroundStyle(.secondary)
                            Text("\(evaluation.purchaseCount) רכישות ב־\(evaluation.distinctTripCount) קניות · כמות \(evaluation.suggestedQuantity)")
                            if let interval = evaluation.intervalDays,
                               let elapsed = evaluation.daysSincePurchase,
                               let progress = evaluation.progress {
                                Text(String(format: "חציון %.1f ימים · עברו %.1f ימים · ציון %.2f · %@",
                                            interval, elapsed, progress,
                                            evaluation.tier == "likely" ? "כנראה" : evaluation.tier == "maybe" ? "אולי" : "מוסתר"))
                            }
                            Text("מקור: היסטוריית הקניות במכשיר")
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
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
