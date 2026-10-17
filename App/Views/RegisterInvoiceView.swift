import SwiftUI
#if os(iOS)
import VisionKit
#endif

/// Registar fatura: same fields as the portal's Registar Faturas page.
struct RegisterInvoiceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var invoice = NewInvoice()
    @State private var form: RegisterForm?
    @State private var loadError: String?
    @State private var saving = false
    @State private var error: String?
    @State private var success: String?
    @State private var scanning = false

    private static let types: [(String, String)] = [
        ("FT", "Fatura"), ("FS", "Fatura simplificada"), ("FR", "Fatura-recibo"),
        ("NC", "Nota de crédito"), ("ND", "Nota de débito"),
    ]
    private static let regions: [(String, String)] = [
        ("PT", "Continente"), ("PT-MA", "Madeira"), ("PT-AC", "Açores"),
    ]

    private var canSave: Bool {
        form != nil && !saving && invoice.nifEmitente.count == 9 && !invoice.numeroDocumento.isEmpty
            && invoice.lines.allSatisfy { $0.rate != nil && $0.total != 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    #if os(iOS)
                    if DataScannerViewController.isSupported {
                        Section {
                            Button { scanning = true } label: {
                                Label("Ler código QR da fatura", systemImage: "qrcode.viewfinder")
                            }
                            .disabled(form == nil)
                        }
                    }
                    #endif

                    Section("Fatura") {
                        TextField("NIF do comerciante", text: $invoice.nifEmitente)
                            .numberPadKeyboard()
                        Picker("Tipo", selection: $invoice.tipoDocumento) {
                            ForEach(Self.types, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        TextField("Número da fatura", text: $invoice.numeroDocumento)
                            .autocorrectionDisabled()
                        DatePicker("Data de emissão", selection: $invoice.dataEmissao, displayedComponents: .date)
                        TextField("ATCUD (opcional)", text: $invoice.atcud)
                            .autocorrectionDisabled()
                        TextField("Código de controlo (opcional)", text: $invoice.hash)
                            .autocorrectionDisabled()
                    }

                    Section {
                        ForEach($invoice.lines) { $line in
                            LineEditor(line: $line, rates: form?.rates ?? [:], regions: Self.regions)
                        }
                        .onDelete { invoice.lines.remove(atOffsets: $0) }
                        if invoice.lines.count < 12 {
                            Button { invoice.lines.append(NewInvoiceLine()) } label: {
                                Label("Adicionar linha de IVA", systemImage: "plus")
                            }
                        }
                    } header: {
                        Text("Linhas de IVA")
                    } footer: {
                        Text("Indique o total de cada linha com IVA; a base e o IVA são calculados pela taxa.")
                    }

                    Section("Totais") {
                        LabeledContent("Impostos", value: invoice.totalVAT.euros)
                        LabeledContent("Total") { Text(invoice.total.euros).bold() }
                    }

                    if let message = error ?? loadError {
                        Section { Text(message).foregroundStyle(.red) }
                    }
                    if let success {
                        Section { Label(success, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
                .listRowSeparator(.hidden)
            }
            .formStyle(.grouped)
            .navigationTitle("Registar fatura")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Registar") { Task { await save() } }.disabled(!canSave)
                    }
                }
            }
            .task { await loadForm() }
            #if os(iOS)
            .sheet(isPresented: $scanning) {
                QRScannerView { text in
                    scanning = false
                    if let rates = form?.rates, let parsed = InvoiceQR.parse(text, rates: rates) {
                        invoice = parsed
                        error = nil
                    } else {
                        error = "Código QR não reconhecido."
                    }
                }
                .ignoresSafeArea()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    private func loadForm() async {
        do {
            form = try await model.registerForm()
            if let first = form?.rates["PT"]?.first {
                for i in invoice.lines.indices where invoice.lines[i].rate == nil { invoice.lines[i].rate = first }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        guard let form else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            success = try await model.register(invoice, form: form)
            // The token is single-use; get a fresh one for another registration.
            self.form = try? await model.registerForm()
            invoice = NewInvoice()
            if let first = self.form?.rates["PT"]?.first { invoice.lines[0].rate = first }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Region, rate and total of one VAT line; base and VAT follow from the rate.
private struct LineEditor: View {
    @Binding var line: NewInvoiceLine
    let rates: [String: [VatRate]]
    let regions: [(String, String)]
    @State private var totalText = ""

    private var regionRates: [VatRate] { rates[line.region] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Região", selection: $line.region) {
                    ForEach(regions, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Taxa", selection: $line.rate) {
                    ForEach(regionRates) { Text($0.tipoTaxa.contains("Isento") ? "Isento" : "\(Int($0.percent))%").tag(Optional($0)) }
                }
            }
            HStack {
                TextField("Total com IVA (€)", text: $totalText)
                    .numberPadKeyboard()
                    .onChange(of: totalText) { _, _ in recompute() }
                Spacer()
                Text("Base \(line.base.euros) · IVA \(line.vat.euros)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: line.region) { _, _ in
            if let r = line.rate, !regionRates.contains(r) { line.rate = regionRates.first }
            recompute()
        }
        .onChange(of: line.rate) { _, _ in recompute() }
        .onAppear {
            if line.total != 0 { totalText = PortalClient.portalMoney(line.total) }
        }
    }

    private func recompute() {
        let cleaned = totalText.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        guard let total = Double(cleaned) else { return }
        let totalCents = Int((total * 100).rounded())
        let rate = (line.rate?.percent ?? 0) / 100
        let base = Int((Double(totalCents) / (1 + rate)).rounded())
        line.base = base
        line.vat = totalCents - base
    }
}

#if os(iOS)
/// Camera QR reader (VisionKit), returns the first code's text.
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onFound(text)
                    return
                }
            }
        }
    }
}
#endif
