import SwiftUI
import Charts

struct ExpensesView: View {
    @EnvironmentObject var model: AppModel

    private var bySector: [CategorySummary] {
        (model.summary?.categories ?? []).filter { ($0.spent ?? 0) > 0 }
            .sorted { ($0.spent ?? 0) > ($1.spent ?? 0) }
    }

    private struct Merchant: Identifiable {
        let name: String
        let total: Int
        let count: Int
        var id: String { name }
    }

    private var topMerchants: [Merchant] {
        Dictionary(grouping: model.invoices, by: \.merchant)
            .map { Merchant(name: $0.key.capitalized, total: $0.value.reduce(0) { $0 + ($1.valorTotal ?? 0) }, count: $0.value.count) }
            .sorted { $0.total > $1.total }
            .prefix(10)
            .map { $0 }
    }

    private var total: Int { model.invoices.reduce(0) { $0 + ($1.valorTotal ?? 0) } }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total em faturas")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(total.euros)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("\(model.invoices.count) faturas")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if !bySector.isEmpty {
                        Section("Por setor") {
                            Chart(bySector) { item in
                                BarMark(x: .value("Gasto", Double(item.spent ?? 0) / 100),
                                        y: .value("Setor", item.title))
                                    .foregroundStyle(Color.accentColor.gradient)
                                    .annotation(position: .trailing) {
                                        Text((item.spent ?? 0).euros).font(.caption2).foregroundStyle(.secondary)
                                    }
                            }
                            .chartXAxis(.hidden)
                            .frame(height: CGFloat(bySector.count) * 36 + 20)
                            .padding(.vertical, 6)
                        }
                    }

                    if !topMerchants.isEmpty {
                        Section("Principais comerciantes") {
                            ForEach(topMerchants) { m in
                                LabeledContent {
                                    Text(m.total.euros).monospacedDigit()
                                } label: {
                                    Text(m.name).lineLimit(1)
                                    Text("\(m.count) faturas")
                                }
                            }
                        }
                    }
                }
                // No dividing lines between rows.
                .listRowSeparator(.hidden)
            }
            .overlay { if model.loading && model.invoices.isEmpty { ProgressView() } }
            .navigationTitle("Despesas")
            .toolbar { ToolbarItem(placement: .trailingBar) { YearPicker() } }
            .refreshable { await model.refresh(force: true) }
        }
    }
}
