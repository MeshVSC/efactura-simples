import SwiftUI

/// Invoice table (middle column of the Mac layout). The selected invoice's details
/// show in the right column (MacRootView).
struct MacInvoicesView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var registering = false
    @State private var filter: String = "TODOS"
    @State private var filteredByPortal: [Invoice]?
    @Binding var selected: Invoice?
    @State private var sortOrder = [KeyPathComparator(\Invoice.dataEmissaoDocumento, order: .reverse)]

    private var selectedID: Binding<Invoice.ID?> {
        Binding(get: { selected?.id },
                set: { id in selected = filtered.first { $0.id == id } })
    }

    private var source: [Invoice] { filter == "TODOS" ? model.invoices : (filteredByPortal ?? []) }

    private var filtered: [Invoice] {
        source.filter { invoice in
            search.isEmpty
                || invoice.merchant.localizedCaseInsensitiveContains(search)
                || (invoice.numerodocumento ?? "").localizedCaseInsensitiveContains(search)
                || (invoice.nifEmitente.map(String.init) ?? "").contains(search)
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            // Click a column header to sort by it; click again to reverse.
            Table(filtered, selection: selectedID, sortOrder: $sortOrder) {
                TableColumn("Data", value: \.dataEmissaoDocumento) { invoice in
                    if let date = invoice.date {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                    }
                }
                .width(96)   // fits "17 out. 2026"
                TableColumn("Comerciante", value: \.merchant) { invoice in
                    HStack(spacing: 8) {
                        Image(systemName: invoice.category?.symbol ?? "doc.text.fill")
                            .foregroundStyle(invoice.isPending ? Color.orange : (invoice.category?.color ?? Color.accentColor))
                            .frame(width: 18)
                        Text(invoice.merchant.capitalized).lineLimit(1)
                    }
                }
                .width(min: 160)   // takes all remaining space
                TableColumn("Valor", value: \.total) { invoice in
                    Text(invoice.total.euros)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(88)   // fits "1 234,56 €"
            }
            .overlay {
                if (model.loading && model.invoices.isEmpty) || (filter != "TODOS" && filteredByPortal == nil) {
                    ProgressView()
                } else if filtered.isEmpty {
                    ContentUnavailableView.search
                }
            }

        }
        .navigationTitle("Faturas")
        .searchable(text: $search, prompt: "Comerciante, NIF ou número")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Setor", selection: $filter) {
                    Text("Todos os setores").tag("TODOS")
                    ForEach(Sector.filters) { c in
                        Label(c.name, systemImage: c.symbol).tag(c.code)
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .primaryAction) { YearPicker() }
            ToolbarItem(placement: .primaryAction) {
                Button { registering = true } label: { Label("Registar fatura", systemImage: "plus") }
            }
        }
        // Sector filtering uses the portal's own filter, like the website.
        .sheet(isPresented: $registering) { RegisterInvoiceView() }
        .task(id: "\(filter)-\(model.year)-\(model.dataVersion)") {
            guard filter != "TODOS" else { return }
            filteredByPortal = nil
            filteredByPortal = await model.invoices(category: filter)
        }
    }
}
