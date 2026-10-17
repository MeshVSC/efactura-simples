import SwiftUI

struct PendingView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<Int64>()
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    private var selecting: Bool { editMode.isEditing }
    #else
    private var selecting: Bool { true }
    #endif
    @State private var working = false
    @State private var failures: [(Invoice, String)] = []
    @State private var showFailures = false

    var body: some View {
        NavigationStack {
            List(model.pending, selection: $selection) { invoice in
                NavigationLink(value: invoice) { InvoiceRow(invoice: invoice) }
            }
            .overlay {
                if model.pending.isEmpty && !model.loading {
                    ContentUnavailableView("Sem faturas pendentes", systemImage: "checkmark.circle",
                                           description: Text("Todas as faturas de \(String(model.year)) estão classificadas."))
                }
                if working { ProgressView().controlSize(.large) }
            }
            .navigationTitle("Pendentes")
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .leadingBar) {
                    if !model.pending.isEmpty {
                        Button(editMode.isEditing ? "OK" : "Selecionar") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            if !editMode.isEditing { selection.removeAll() }
                        }
                    }
                }
                #endif
                ToolbarItem(placement: .trailingBar) { YearPicker() }
                ToolbarItem(placement: classifyPlacement) {
                    if selecting {
                        Menu {
                            ForEach(Sector.all.filter { $0.code != "DGF" }) { c in
                                Button { Task { await assign(c.code) } } label: { Label(c.name, systemImage: c.symbol) }
                            }
                        } label: {
                            Text(selection.isEmpty ? "Escolha faturas" : "Classificar \(selection.count)")
                        }
                        .disabled(selection.isEmpty || working)
                    }
                }
            }
            .refreshable { await model.refresh(force: true) }
            .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoice: $0) }
            .alert("Algumas faturas não foram classificadas", isPresented: $showFailures) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failures.map { "\($0.0.merchant): \($0.1)" }.joined(separator: "\n"))
            }
        }
    }

    private var classifyPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }

    private func assign(_ sector: String) async {
        let chosen = model.pending.filter { selection.contains($0.id) }
        working = true
        failures = await model.classify(chosen, sector: sector)
        working = false
        selection.removeAll()
        #if os(iOS)
        editMode = .inactive
        #endif
        showFailures = !failures.isEmpty
    }
}
