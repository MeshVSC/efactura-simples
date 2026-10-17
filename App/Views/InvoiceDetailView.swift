import SwiftUI

struct InvoiceDetailView: View {
    @EnvironmentObject var model: AppModel
    let invoice: Invoice
    @State private var detail: InvoiceDetail?
    @State private var selected: String = ""
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false
    @State private var siblings: [Invoice] = []
    @State private var askSiblings = false
    @State private var siblingsResult: String?

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .center, spacing: 4) {
                        Text(invoice.merchant.capitalized)
                            .font(.title3.bold())
                        Text((invoice.valorTotal ?? 0).euros)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                Section {
                    if let detail {
                        Picker("Setor", selection: $selected) {
                            Text("Por classificar").tag("")
                            ForEach(detail.sectorOptions) { c in
                                Label(c.name, systemImage: c.symbol).tag(c.code)
                            }
                        }
                        .navigationLinkPicker()
                        #if os(macOS)
                        // Mac: a compact button on the right, just wide enough for its label.
                        HStack(spacing: 8) {
                            Spacer()
                            if saving {
                                ProgressView().controlSize(.small)
                            } else if saved {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Button(saved ? "Guardado" : "Guardar") {
                                Task { await save() }
                            }
                            .fixedSize()
                            .disabled(saving || selected.isEmpty || selected == detail.currentSector)
                        }
                        #else
                        Button {
                            Task { await save() }
                        } label: {
                            HStack {
                                Text(saved ? "Guardado" : "Guardar")
                                Spacer()
                                if saving { ProgressView() } else if saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                        }
                        .disabled(saving || selected.isEmpty || selected == detail.currentSector)
                        #endif
                    } else {
                        HStack { Text("A carregar…").foregroundStyle(.secondary); Spacer(); ProgressView() }
                    }
                } header: {
                    Text("Classificação")
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }

                Section("Fatura") {
                    LabeledContent("NIF do comerciante", value: invoice.nifEmitente.map(String.init) ?? "—")
                    LabeledContent("Número", value: invoice.numerodocumento ?? "—")
                    if let atcud = detail?.atcud ?? invoice.atcud, !atcud.isEmpty, atcud != "0" {
                        LabeledContent("ATCUD", value: atcud)
                    }
                    if let date = invoice.date {
                        LabeledContent("Data") { Text(date, format: .dateTime.day().month(.wide).year()) }
                    }
                    LabeledContent("Tipo", value: invoice.tipoDocumentoDesc ?? "—")
                    if let status = detail?.status {
                        LabeledContent("Estado", value: status)
                    }
                    LabeledContent("Benefício", value: invoice.estadoBeneficioDesc ?? "—")
                }

                Section("Valores") {
                    if let lines = detail?.lines, !lines.isEmpty {
                        ForEach(lines) { line in
                            LabeledContent("IVA \(rate(line))") {
                                VStack(alignment: .trailing) {
                                    Text((line.valorTotal ?? 0).euros)
                                    Text("Base \((line.valorBaseTributavel ?? 0).euros) · IVA \((line.valorIva ?? 0).euros)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    LabeledContent("IVA total", value: (invoice.valorTotalIva ?? 0).euros)
                    LabeledContent("Total", value: (invoice.valorTotal ?? 0).euros)
                    if let benefit = invoice.valorTotalBeneficioProv {
                        LabeledContent("Dedução provisória", value: benefit.euros)
                    }
                }
            }
            // No dividing lines between rows.
            .listRowSeparator(.hidden)
        }
        .navigationTitle(invoice.numerodocumento ?? "Fatura")
        .inlineTitle()
        .task { await load() }
        .alert(siblingsQuestion, isPresented: $askSiblings) {
            Button("Classificar todas") { Task { await classifySiblings() } }
            Button("Só esta", role: .cancel) { Task { await model.refresh(force: true) } }
        }
        .alert("Reclassificação", isPresented: Binding(get: { siblingsResult != nil },
                                                        set: { if !$0 { siblingsResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(siblingsResult ?? "")
        }
    }

    private var siblingsQuestion: String {
        let name = Sector.named(selected)?.name ?? selected
        let count = siblings.count
        return count == 1
            ? "Há mais 1 fatura de \(invoice.merchant.capitalized). Classificar também como \(name)?"
            : "Há mais \(count) faturas de \(invoice.merchant.capitalized). Classificar todas como \(name)?"
    }

    private func classifySiblings() async {
        saving = true
        let failures = await model.classify(siblings, sector: selected)
        saving = false
        let done = siblings.count - failures.count
        if failures.isEmpty {
            siblingsResult = "\(done) faturas reclassificadas."
        } else {
            let list = failures.map { "\($0.0.numerodocumento ?? String($0.0.idDocumento)): \($0.1)" }.joined(separator: "\n")
            siblingsResult = "\(done) reclassificadas, \(failures.count) não foram alteradas:\n\(list)"
        }
    }

    private func rate(_ line: VatLine) -> String {
        guard let t = line.taxaIva else { return line.taxa ?? "" }
        return "\(t / 100)%"
    }

    private func load() async {
        do {
            let d = try await model.detail(invoice)
            detail = d
            selected = d.currentSector ?? invoice.actividadeEmitente ?? ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let detail else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            self.detail = try await model.classify(invoice, detail: detail, sector: selected)
            saved = true
            // Other invoices from the same seller (same NIF) this year with a different sector.
            siblings = model.invoices.filter {
                $0.id != invoice.id && $0.nifEmitente != nil
                    && $0.nifEmitente == invoice.nifEmitente && $0.actividadeEmitente != selected
            }
            if siblings.isEmpty {
                await model.refresh(force: true)
            } else {
                askSiblings = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
