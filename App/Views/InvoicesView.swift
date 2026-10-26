import SwiftUI

struct InvoicesView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var registering = false
    @State private var filter: String = "TODOS"
    @State private var filteredByPortal: [Invoice]?

    private var source: [Invoice] { filter == "TODOS" ? model.invoices : (filteredByPortal ?? []) }

    private var filtered: [Invoice] {
        source.filter { invoice in
            search.isEmpty
                    || invoice.merchant.localizedCaseInsensitiveContains(search)
                    || (invoice.numerodocumento ?? "").localizedCaseInsensitiveContains(search)
                    || (invoice.nifEmitente.map(String.init) ?? "").contains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { invoice in
                NavigationLink(value: invoice) { InvoiceRow(invoice: invoice) }
            }
            .overlay {
                if (model.loading && model.invoices.isEmpty) || (filter != "TODOS" && filteredByPortal == nil) {
                    ProgressView()
                } else if filtered.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .navigationTitle("Faturas")
            .searchable(text: $search, prompt: "Comerciante, NIF ou número")
            .toolbar {
                ToolbarItem(placement: .leadingBar) {
                    Menu {
                        Picker("Setor", selection: $filter) {
                            Text("Todos os setores").tag("TODOS")
                            ForEach(Sector.filters) { c in
                                Label(c.name, systemImage: c.symbol).tag(c.code)
                            }
                        }
                    } label: {
                        Image(systemName: filter == "TODOS" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .trailingBar) { YearPicker() }
                ToolbarItem(placement: .primaryAction) {
                    Button { registering = true } label: { Label("Registar fatura", systemImage: "plus") }
                }
            }
            .refreshable { await model.refresh(force: true) }
            // Sector filtering uses the portal's own filter, like the website.
            .sheet(isPresented: $registering) { RegisterInvoiceView() }
            .task(id: "\(filter)-\(model.year)-\(model.dataVersion)") {
                guard filter != "TODOS" else { return }
                filteredByPortal = nil
                filteredByPortal = await model.invoices(category: filter)
            }
            .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoice: $0) }
        }
    }
}

struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: invoice.category?.symbol ?? "doc.text.fill")
                .font(.title3)
                .foregroundStyle(invoice.isPending ? Color.orange : (invoice.category?.color ?? Color.accentColor))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.merchant.capitalized)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let date = invoice.date {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                    }
                    if invoice.isPending {
                        Text("Pendente")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text((invoice.valorTotal ?? 0).euros)
                .monospacedDigit()
        }
    }
}
