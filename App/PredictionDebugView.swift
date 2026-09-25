import SwiftUI

struct PredictionDebugView: View {
    @ObservedObject var store: ShoppingStore

    var body: some View {
        NavigationStack {
            List(store.predictionEvaluations) { evaluation in
                VStack(alignment: .leading, spacing: 6) {
                    Text(evaluation.product.name).font(.headline)
                    Text(evaluation.reason).foregroundStyle(.secondary)
                    Text("\(evaluation.purchaseCount) purchases across \(evaluation.distinctTripCount) trips · quantity \(evaluation.quantity)")
                    if let interval = evaluation.intervalDays,
                       let elapsed = evaluation.daysSincePurchase,
                       let progress = evaluation.progress {
                        Text(String(format: "Median %.1f days · elapsed %.1f days · score %.2f · %@",
                                    interval, elapsed, progress,
                                    evaluation.tier == .likely ? "Likely" : evaluation.tier == .maybe ? "Maybe" : "Hidden"))
                    }
                    Text("Source: local purchase history")
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
            .overlay {
                if store.predictionEvaluations.isEmpty {
                    ContentUnavailableView("No purchase history yet", systemImage: "chart.bar")
                }
            }
            .navigationTitle("Prediction details")
        }
    }
}
