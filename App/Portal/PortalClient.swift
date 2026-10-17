import Foundation

enum PortalError: LocalizedError {
    case login(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .login(let m): return m
        case .unexpected(let m): return m
        }
    }
}

/// Talks to the e-Fatura website the same way the browser does (see Capture/capture.jsonl).
/// One instance per account; each has its own in-memory cookie store.
final class PortalClient: @unchecked Sendable {
    static let faturas = "https://faturas.portaldasfinancas.gov.pt/"
    static let loginForm = "https://www.acesso.gov.pt/jsp/loginRedirectForm.jsp?path=painelAdquirente.action&partID=EFPF"

    let nif: String
    private let password: String
    private let session: URLSession
    private(set) var userName: String = ""
    private var panelHTML: String?

    init(nif: String, password: String) {
        self.nif = nif
        self.password = password
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": "pt-PT,pt;q=0.9",
        ]
        session = URLSession(configuration: config)
    }

    // MARK: Requests

    private func get(_ url: String, headers: [String: String] = [:]) async throws -> (String, URL?) {
        var request = URLRequest(url: URL(string: url)!)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        return (HTML.decode(data), response.url)
    }

    private func post(_ url: String, fields: [(name: String, value: String)],
                      encoding: String.Encoding = .utf8, headers: [String: String] = [:]) async throws -> (String, URL?) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        let charset = encoding == .isoLatin1 ? "ISO-8859-1" : "UTF-8"
        request.setValue("application/x-www-form-urlencoded; charset=\(charset)", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = Self.formBody(fields, encoding: encoding).data(using: .ascii)
        let (data, response) = try await session.data(for: request)
        return (HTML.decode(data), response.url)
    }

    static func formBody(_ fields: [(name: String, value: String)], encoding: String.Encoding) -> String {
        func escape(_ s: String) -> String {
            guard let bytes = s.data(using: encoding, allowLossyConversion: true) else { return "" }
            return bytes.map { b -> String in
                let c = Character(Unicode.Scalar(b))
                if c.isASCII && (c.isLetter || c.isNumber || "-._*".contains(c)) { return String(c) }
                if c == " " { return "+" }
                return String(format: "%%%02X", b)
            }.joined()
        }
        return fields.map { "\(escape($0.name))=\(escape($0.value))" }.joined(separator: "&")
    }

    private func isLoginPage(_ url: URL?) -> Bool {
        url?.host?.contains("acesso.gov.pt") == true
    }

    /// Runs a request, logging in again once if the session has expired.
    private func authed(_ request: () async throws -> (String, URL?)) async throws -> String {
        let (html, url) = try await request()
        if !isLoginPage(url) { return html }
        try await login()
        let (retry, retryURL) = try await request()
        if isLoginPage(retryURL) { throw PortalError.unexpected("A sessão expirou.") }
        return retry
    }

    func authedHTML(_ url: String) async throws -> String {
        try await authed { try await get(url) }
    }

    func authedPost(_ url: String, fields: [(name: String, value: String)]) async throws -> String {
        try await authed { try await post(url, fields: fields) }
    }

    // MARK: Login

    func login() async throws {
        // The login form is built by the page's JavaScript; the token sits in its config object:
        // _csrf: { parameterName: `_csrf`, token: `...` }
        let (formPage, _) = try await get(Self.loginForm)
        guard let csrf = HTML.first(#"parameterName:\s*`_csrf`,\s*token:\s*`([^`]+)`"#, in: formPage) else {
            throw PortalError.login("Não foi possível abrir a página de autenticação.")
        }
        // Same fields, same order as the recorded browser login.
        let fields: [(name: String, value: String)] = [
            ("username", nif),
            ("password", password),
            ("path", "painelAdquirente.action"),
            ("partID", "EFPF"),
            ("selectedAuthMethod", "N"),
            ("_csrf", csrf),
            ("authVersion", "1"),
        ]
        let (response, _) = try await post("https://www.acesso.gov.pt/jsp/submissaoFormularioLogin", fields: fields,
                                           headers: ["Referer": Self.loginForm, "Origin": "https://www.acesso.gov.pt"])

        guard let handOff = HTML.form(containing: "forwardParticipantForm", in: response) else {
            let message = HTML.first(#"class="[^"]*(?:error|alert)[^"]*"[^>]*>(.*?)</"#, in: response).map(HTML.text)
            throw PortalError.login(message?.isEmpty == false ? message! : "NIF ou senha incorretos.")
        }
        userName = handOff.fields.first { $0.name == "userName" }?.value ?? ""
        let (panel, panelURL) = try await post(handOff.action, fields: handOff.fields, encoding: .isoLatin1)
        if isLoginPage(panelURL) { throw PortalError.login("A autenticação falhou.") }
        panelHTML = panel
    }

    // MARK: Summary

    func years() async throws -> [Int] {
        let html = try await panel()
        return HTML.matches(#"<p class="pyear">\s*(\d{4})\s*</p>"#, in: html).compactMap { Int($0[1]) }
    }

    private func panel(refresh: Bool = false) async throws -> String {
        if let panelHTML, !refresh { return panelHTML }
        let html = try await authed { try await get(Self.faturas + "painelAdquirente.action") }
        panelHTML = html
        return html
    }

    func summary(year: Int, refresh: Bool = false) async throws -> YearSummary {
        let html = try await panel(refresh: refresh)
        if let parsed = Self.parseSummary(year: year, html: html) { return parsed }

        // Other years load through the panel's slider (painelAdquirente.js -> json/sliderAdquirente.action).
        let json = try await authed {
            try await post(Self.faturas + "json/sliderAdquirente.action", fields: [("ano", String(year))],
                           headers: ["X-Requested-With": "XMLHttpRequest", "Accept": "application/json, text/javascript, */*; q=0.01"])
        }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PortalError.unexpected("Resumo de \(year) indisponível.")
        }
        let fragment = "<li id=\"y\(year)\"><p class=\"pyear\">\(year)</p>" + (obj["consumerYearSlideHTML"] as? String ?? "") + "</li>"
            + (obj["consumerBeneficiosSlideHTML"] as? String ?? "")
        guard let parsed = Self.parseSummary(year: year, html: fragment) else {
            throw PortalError.unexpected("Resumo de \(year) indisponível.")
        }
        return parsed
    }

    static func parseSummary(year: Int, html: String) -> YearSummary? {
        var categories: [CategorySummary] = []
        let boxes = HTML.matches(#"(<div[^>]*painelAdquirenteSectorBox[^>]*>)(.*?)</p>"#, in: html)
        for box in boxes {
            let attrs = HTML.attributes(of: box[1])
            guard attrs["data-ano"] == String(year), let code = attrs["data-sector"] else { continue }
            let title = HTML.first(#"<h2>(.*?)</h2>"#, in: box[2]).map(HTML.text) ?? Sector.named(code)?.name ?? code
            let deduction = HTML.first(#"class="euro-value">(.*?)</span>"#, in: box[2]).map(HTML.cents) ?? 0
            let amounts = HTML.matches(#"class="nowrap_text">(.*?)</span>"#, in: box[2]).map { HTML.cents($0[1]) }
            categories.append(CategorySummary(code: code, title: title, deduction: deduction,
                                              spent: amounts.first, vat: amounts.count > 1 ? amounts[1] : nil))
        }
        guard !categories.isEmpty else { return nil }
        let slide = HTML.first(#"<li id="y\#(year)"[^>]*>(.*?)</li>"#, in: html) ?? ""
        let total = HTML.first(#"class="pmoney">(.*?)</p>"#, in: slide).map(HTML.cents)
            ?? categories.reduce(0) { $0 + $1.deduction }
        return YearSummary(year: year, total: total, categories: categories)
    }

    // MARK: Invoices

    func invoices(year: Int, category: String = "TODOS") async throws -> [Invoice] {
        // Same query the portal builds (note the leading space in dataFimFilter, copied as-is).
        var components = URLComponents(string: Self.faturas + "json/obterDocumentosIRSAdquirente.action")!
        components.queryItems = [
            URLQueryItem(name: "dataInicioFilter", value: "\(year)-01-01"),
            URLQueryItem(name: "dataFimFilter", value: " \(year)-12-31"),
            URLQueryItem(name: "ambitoAquisicaoFilter", value: category),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000))),
        ]
        let url = components.url!.absoluteString
        let json = try await authed {
            try await get(url, headers: ["X-Requested-With": "XMLHttpRequest",
                                         "Accept": "application/json, text/javascript, */*; q=0.01"])
        }
        struct Response: Decodable { let success: Bool?; let linhas: [Invoice]? }
        guard let data = json.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode(Response.self, from: data).linhas ?? []
        } catch {
            throw PortalError.unexpected("Resposta inesperada ao obter faturas.")
        }
    }

    // MARK: Detail and classification

    private func detailURL(_ invoice: Invoice) -> String {
        Self.faturas + "detalheDocumentoAdquirente.action?idDocumento=\(invoice.idDocumento)&dataEmissaoDocumento=\(invoice.dataEmissaoDocumento)"
    }

    func detail(_ invoice: Invoice) async throws -> InvoiceDetail {
        let html = try await authed { try await get(detailURL(invoice)) }
        return Self.parseDetail(html)
    }

    static func parseDetail(_ html: String) -> InvoiceDetail {
        let linesJSON = HTML.first(#"dadosLinhasDocumento\s*=\s*(\[\]|\[.*?\}\])\s*;"#, in: html) ?? "[]"
        let lines = (try? JSONDecoder().decode([VatLine].self, from: Data(linesJSON.utf8))) ?? []
        var options: [Sector] = []
        var current: String?
        if let select = HTML.first(#"<select[^>]*id="ambitoAquisicao"[^>]*>(.*?)</select>"#, in: html) {
            for opt in HTML.matches(#"(<option[^>]*>)([^<]*)"#, in: select) {
                let a = HTML.attributes(of: opt[1])
                guard let code = a["value"], !code.isEmpty else { continue }
                if a["selected"] != nil { current = code }
                options.append(Sector.named(code) ?? Sector(code: code, name: HTML.text(opt[2]), symbol: "tag.fill"))
            }
        }
        return InvoiceDetail(
            status: HTML.value(ofId: "estadoDocumento", in: html),
            nifEmitente: HTML.value(ofId: "nifEmitente", in: html),
            atcud: HTML.value(ofId: "ATCUD", in: html),
            hash: HTML.value(ofId: "hashAdquirenteDesc", in: html) ?? "",
            linesJSON: linesJSON,
            lines: lines,
            currentSector: current,
            sectorOptions: options)
    }

    /// Same fields the portal's resolverPendencia form submits.
    func classify(_ invoice: Invoice, detail: InvoiceDetail, sector: String) async throws -> InvoiceDetail {
        let date = invoice.dataEmissaoDocumento
        let fields: [(name: String, value: String)] = [
            ("idDocumento", String(invoice.idDocumento)),
            ("dataEmissaoDocumento", date),
            ("dataEmissaoDocumentoOriginal", date),
            ("hashDocumento", detail.hash),
            ("linhasDocumento", detail.linesJSON),
            ("ambitoAquisicaoPend", sector),
            ("ambitoActividadeProfPend", ""),
            ("cancelarAction", "detalheDocumentoAdquirente.action?idDocumento=\(invoice.idDocumento)&dataEmissaoDocumento=\(date)"),
            ("mostraRemoverBtn", "false"),
            ("showAdquirenteEdit", "true"),
        ]
        let html = try await authed {
            try await post(Self.faturas + "resolverPendenciaAdquirente.action", fields: fields)
        }
        let updated = Self.parseDetail(html)
        guard updated.currentSector == sector else {
            let message = HTML.first(#"class="[^"]*alert-error[^"]*"[^>]*>(.*?)</div>"#, in: html).map(HTML.text)
            throw PortalError.unexpected(message?.isEmpty == false ? message! : "O portal não aceitou a alteração.")
        }
        panelHTML = nil
        return updated
    }
}
