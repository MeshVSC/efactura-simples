import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeductionHeader()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }

                if let summary = model.summary {
                    Section("Setores") {
                        ForEach(summary.categories) { item in
                            NavigationLink {
                                CategoryInvoicesView(code: item.code, title: item.title)
                            } label: {
                                CategoryRow(item: item)
                            }
                        }
                    }
                } else if model.loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .navigationTitle("Resumo")
            .toolbar { ToolbarItem(placement: .trailingBar) { YearPicker() } }
            .refreshable { await model.refresh(force: true) }
        }
    }
}

struct CategoryRow: View {
    let item: CategorySummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Sector.named(item.code)?.symbol ?? "tag.fill")
                .font(.title3)
                .foregroundStyle(Sector.named(item.code)?.color ?? .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.deduction.euros)
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(item.deduction > 0 ? .primary : .secondary)
        }
    }

    private var detail: String {
        guard let spent = item.spent else { return "Sem despesas registadas" }
        if let vat = item.vat { return "Gasto \(spent.euros) · IVA \(vat.euros)" }
        return "Gasto \(spent.euros)"
    }
}

struct CategoryInvoicesView: View {
    @EnvironmentObject var model: AppModel
    let code: String
    let title: String

    @State private var list: [Invoice]?

    var body: some View {
        List(list ?? []) { invoice in
            NavigationLink {
                InvoiceDetailView(invoice: invoice)
            } label: {
                InvoiceRow(invoice: invoice)
            }
        }
        .overlay {
            if list == nil {
                ProgressView()
            } else if list?.isEmpty == true {
                ContentUnavailableView("Sem faturas", systemImage: "doc.text")
            }
        }
        .navigationTitle(title)
        .inlineTitle()
        // Same query the portal runs when a sector box is clicked.
        // Reloads after every refresh, e.g. when an invoice here is reclassified.
        .task(id: model.dataVersion) { list = await model.invoices(category: code) }
    }
}
