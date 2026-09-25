import SwiftUI

struct PredictionDebugView: View {
    @ObservedObject var store: ShoppingStore

    var body: some View {
        NavigationStack {
            List(store.predictionEvaluations) { evaluation in
                VStack(alignment: .leading, spacing: 6) {
                    Text(evaluation.product.name).font(.headline)
                    Text(evaluation.reason).foregroundStyle(.secondary)
                    Text("\(evaluation.purchaseCount) רכישות ב־\(evaluation.distinctTripCount) קניות · כמות \(evaluation.quantity)")
                    if let interval = evaluation.intervalDays,
                       let elapsed = evaluation.daysSincePurchase,
                       let progress = evaluation.progress {
                        Text(String(format: "חציון %.1f ימים · עברו %.1f ימים · ציון %.2f · %@",
                                    interval, elapsed, progress,
                                    evaluation.tier == .likely ? "כנראה" : evaluation.tier == .maybe ? "אולי" : "מוסתר"))
                    }
                    Text("מקור: היסטוריית הקניות במכשיר")
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
            .overlay {
                if store.predictionEvaluations.isEmpty {
                    ContentUnavailableView("אין עדיין היסטוריית קניות", systemImage: "chart.bar")
                }
            }
            .navigationTitle("פרטי ההצעות")
        }
    }
}
