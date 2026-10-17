import Foundation

// MARK: Registering invoices (Faturação > Adquirente > Registar Faturas)

/// One VAT rate from the portal's own catalog (AT.Factemipf.Catalogs.TAXAS_IVA on the register page).
struct VatRate: Identifiable, Hashable, Decodable {
    let id: String
    let valor: Int           // 2300 = 23%
    let tipoTaxa: String     // label the portal sends back, e.g. "Normal - 23%"
    var percent: Double { Double(valor) / 100 }
}

/// What the register page provides before submitting: the form token and the VAT catalog per region.
struct RegisterForm {
    let token: String
    let rates: [String: [VatRate]]   // "PT", "PT-MA", "PT-AC"
}

/// One VAT line as typed by the user (amounts in cents).
struct NewInvoiceLine: Identifiable, Hashable {
    var id = UUID()
    var region = "PT"
    var rate: VatRate?
    var base = 0
    var vat = 0
    var total: Int { base + vat }
}

struct NewInvoice {
    var nifEmitente = ""
    var tipoDocumento = "FT"
    var numeroDocumento = ""
    var dataEmissao = Date()
    var atcud = ""
    var hash = ""
    var numeroCertificado = ""
    var lines: [NewInvoiceLine] = [NewInvoiceLine()]

    var totalVAT: Int { lines.reduce(0) { $0 + $1.vat } }
    var total: Int { lines.reduce(0) { $0 + $1.total } }
}

extension PortalClient {
    /// "1.234,56", the portal's money format (autoNumeric aSep "." aDec ",").
    static func portalMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "0,00"
    }

    func registerForm() async throws -> RegisterForm {
        let html = try await authedHTML(Self.faturas + "registarDocumentoAdquirenteForm.action")
        guard let token = HTML.first(#"name="synchronizerToken"\s+value="([^"]+)""#, in: html) else {
            throw PortalError.unexpected("Não foi possível abrir o formulário de registo.")
        }
        var rates: [String: [VatRate]] = [:]
        if let json = HTML.first(#"TAXAS_IVA\.taxasIvaCatalog\s*=\s*(\{.*?\});"#, in: html),
           let decoded = try? JSONDecoder().decode([String: [VatRate]].self, from: Data(json.utf8)) {
            rates = decoded.filter { ["PT", "PT-MA", "PT-AC"].contains($0.key) }
        }
        return RegisterForm(token: token, rates: rates)
    }

    /// Submits the same fields, in the same order, as the portal's #registarDocumento form.
    /// Returns the portal's success message.
    func register(_ invoice: NewInvoice, form: RegisterForm) async throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Same objects as LinhasDocumentoEditable.getDataTableElements(): amounts as digit strings.
        let lines: [[String: Any]] = invoice.lines.map { line in
            [
                "valorTotal": String(line.total),
                "regiaoFiscal": line.region,
                "valorIva": String(line.vat),
                "valorBaseTributavel": String(line.base),
                "taxaIva": line.rate?.valor ?? 0,
                "tipoTaxaIva": line.rate?.tipoTaxa ?? "",
                "motivoIsencao": "",
            ]
        }
        let linesData = (try? JSONSerialization.data(withJSONObject: lines)) ?? Data("[]".utf8)
        let linesJSON = String(data: linesData, encoding: .utf8) ?? "[]"

        let fields: [(name: String, value: String)] = [
            ("nifEmitente", invoice.nifEmitente.trimmingCharacters(in: .whitespaces)),
            ("ATCUD", invoice.atcud),
            ("tipoDocumento", invoice.tipoDocumento),
            ("numeroDocumento", invoice.numeroDocumento),
            ("dataEmissaoDocumento", dateFormatter.string(from: invoice.dataEmissao)),
            ("estadoDocumento", "N"),
            ("numeroCertificado", invoice.numeroCertificado),
            ("hashDocumento", invoice.hash),
            ("linhasDocumento", linesJSON),
            ("cancelarAction", "consultarDocumentosAdquirente.action"),
            ("continuarRegistar", ""),
            ("outrasSituacoes", ""),
            ("impostoSelo", ""),
            ("impostos", Self.portalMoney(invoice.totalVAT)),
            ("totalDocumento", Self.portalMoney(invoice.total)),
            ("synchronizerToken", form.token),
        ]
        let html = try await authedPost(Self.faturas + "registarDocumentoAdquirente.action", fields: fields)
        if let error = Self.alert("alert-error", in: html) { throw PortalError.unexpected(error) }
        if let fieldError = HTML.first(#"class="help-block\s*">([^<]{3,})</span>"#, in: html).map(HTML.text),
           !fieldError.isEmpty {
            throw PortalError.unexpected(fieldError)
        }
        return Self.alert("alert-success", in: html) ?? "Fatura registada."
    }

    /// Text of a visible portal alert box (the hidden template boxes carry the class "hide").
    private static func alert(_ cls: String, in html: String) -> String? {
        for m in HTML.matches(#"<div[^>]*class="alert \#(cls)([^"]*)"[^>]*>(.*?)</div>"#, in: html)
        where !m[1].contains("hide") {
            let text = HTML.text(m[2])
            if !text.isEmpty { return text }
        }
        return nil
    }
}

// MARK: Invoice QR code (Portaria n.º 195/2020, Especificações Técnicas Código QR v1.1)

enum InvoiceQR {
    /// Parses "A:123456789*B:999999990*...*O:0.80*Q:YhGV*R:9999" into a NewInvoice.
    /// Regions: I = PT, J = PT-AC, K = PT-MA. Per region: 2 exempt base, 3/4 reduced base/VAT,
    /// 5/6 intermediate base/VAT, 7/8 normal base/VAT.
    static func parse(_ text: String, rates: [String: [VatRate]]) -> NewInvoice? {
        var fields: [String: String] = [:]
        for part in text.split(separator: "*") {
            guard let colon = part.firstIndex(of: ":") else { continue }
            fields[String(part[..<colon])] = String(part[part.index(after: colon)...])
        }
        guard let nif = fields["A"], fields["F"] != nil else { return nil }

        var invoice = NewInvoice()
        invoice.nifEmitente = nif
        invoice.tipoDocumento = fields["D"] ?? "FT"
        invoice.numeroDocumento = fields["G"] ?? ""
        invoice.atcud = fields["H"] ?? ""
        invoice.hash = fields["Q"] ?? ""
        invoice.numeroCertificado = fields["R"] ?? ""

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd"
        if let f = fields["F"], let date = df.date(from: f) { invoice.dataEmissao = date }

        func cents(_ key: String) -> Int {
            guard let v = fields[key], let d = Double(v) else { return 0 }
            return Int((d * 100).rounded())
        }

        var lines: [NewInvoiceLine] = []
        for (prefix, defaultRegion) in [("I", "PT"), ("J", "PT-AC"), ("K", "PT-MA")] {
            guard let region = fields["\(prefix)1"], region != "0" else { continue }
            let catalog = rates[region] ?? rates[defaultRegion] ?? []
            // Catalog order per region: normal, intermediate, reduced, exempt.
            let normal = catalog.first { $0.tipoTaxa.hasPrefix("Normal") }
            let reduced = catalog.first { $0.tipoTaxa.hasPrefix("Reduzida") }
            let exempt = catalog.first { $0.valor == 0 }
            let intermediate = catalog.first { $0 != normal && $0 != reduced && $0 != exempt }

            let groups: [(base: String, vat: String?, rate: VatRate?)] = [
                ("\(prefix)2", nil, exempt),
                ("\(prefix)3", "\(prefix)4", reduced),
                ("\(prefix)5", "\(prefix)6", intermediate),
                ("\(prefix)7", "\(prefix)8", normal),
            ]
            for g in groups {
                let base = cents(g.base)
                let vat = g.vat.map(cents) ?? 0
                guard base != 0 || vat != 0 else { continue }
                lines.append(NewInvoiceLine(region: region, rate: g.rate, base: base, vat: vat))
            }
        }
        if !lines.isEmpty { invoice.lines = lines }
        return invoice
    }
}
