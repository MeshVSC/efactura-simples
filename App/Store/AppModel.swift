import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var current: Account?
    @Published var year: Int = Calendar.current.component(.year, from: Date())
    @Published var years: [Int] = []
    @Published var summary: YearSummary?
    @Published var invoices: [Invoice] = []
    @Published var loading = false
    @Published var restoring = false
    @Published var errorMessage: String?
    /// Goes up after every successful refresh, so per-sector lists reload too
    /// (a reclassified invoice must leave its old sector's list).
    @Published var dataVersion = 0
    @Published var taxProfile = TaxProfile() {
        didSet { saveTaxProfile() }
    }

    private(set) var client: PortalClient?
    private let accountsKey = "accounts"
    private let lastKey = "lastAccount"

    var pending: [Invoice] { invoices.filter(\.isPending) }

    /// Limits for the selected year, once the Profile's tax situation is filled in.
    var limits: DeductionLimits? { TaxRules.limits(for: taxProfile, year: year) }

    private func taxProfileKey(_ nif: String) -> String { "taxProfile-\(nif)" }

    private func loadTaxProfile(_ nif: String) {
        if let data = UserDefaults.standard.data(forKey: taxProfileKey(nif)),
           let saved = try? JSONDecoder().decode(TaxProfile.self, from: data) {
            taxProfile = saved
        } else {
            taxProfile = TaxProfile()
        }
    }

    private func saveTaxProfile() {
        guard let nif = current?.nif, let data = try? JSONEncoder().encode(taxProfile) else { return }
        UserDefaults.standard.set(data, forKey: taxProfileKey(nif))
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: accountsKey),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    /// Last used account's NIF and password, used to prefill the login screen.
    /// The user still presses Entrar (they may want another account).
    var savedLogin: (nif: String, password: String)? {
        guard let nif = UserDefaults.standard.string(forKey: lastKey),
              let password = Keychain.password(nif: nif) else { return nil }
        return (nif, password)
    }

    func signIn(nif: String, password: String) async throws {
        let client = PortalClient(nif: nif, password: password)
        try await client.login()
        Keychain.save(nif: nif, password: password)
        let account = Account(nif: nif, name: client.userName.capitalized)
        if let i = accounts.firstIndex(where: { $0.nif == nif }) {
            accounts[i] = account
        } else {
            accounts.append(account)
        }
        persistAccounts()
        UserDefaults.standard.set(nif, forKey: lastKey)
        self.client = client
        current = account
        loadTaxProfile(nif)
        summary = nil
        invoices = []
        years = (try? await client.years()) ?? []
        if let latest = years.max() { year = latest }
        await refresh()
    }

    func switchTo(_ account: Account) async {
        guard let password = Keychain.password(nif: account.nif) else { return }
        do {
            try await signIn(nif: account.nif, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ account: Account) {
        Keychain.delete(nif: account.nif)
        accounts.removeAll { $0.nif == account.nif }
        persistAccounts()
        if current?.nif == account.nif { signOut() }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: lastKey)
        client = nil
        current = nil
        summary = nil
        invoices = []
        years = []
    }

    func refresh(force: Bool = false) async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            async let s = client.summary(year: year, refresh: force)
            async let i = client.invoices(year: year)
            let (newSummary, newInvoices) = try await (s, i)
            summary = newSummary
            invoices = newInvoices.sorted { $0.dataEmissaoDocumento > $1.dataEmissaoDocumento }
            dataVersion += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invoices(category: String) async -> [Invoice] {
        guard let client else { return [] }
        do {
            return try await client.invoices(year: year, category: category)
                .filter { Self.belongs($0, to: category) }
                .sorted { $0.dataEmissaoDocumento > $1.dataEmissaoDocumento }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// The portal's sector filters overlap (e.g. Despesas Gerais also returns Educação invoices).
    /// Each invoice shows only under the sector it is classified in; Despesas Gerais keeps
    /// the ones classified as Outros or not classified yet.
    static func belongs(_ invoice: Invoice, to category: String) -> Bool {
        let sector = invoice.actividadeEmitente
        if category == "DGF" {
            return sector == nil || sector == "C99" || Sector.named(sector) == nil
        }
        return sector == category
    }

    func registerForm() async throws -> RegisterForm {
        guard let client else { throw PortalError.unexpected("Sem sessão.") }
        return try await client.registerForm()
    }

    func register(_ invoice: NewInvoice, form: RegisterForm) async throws -> String {
        guard let client else { throw PortalError.unexpected("Sem sessão.") }
        let message = try await client.register(invoice, form: form)
        await refresh(force: true)
        return message
    }

    func detail(_ invoice: Invoice) async throws -> InvoiceDetail {
        guard let client else { throw PortalError.unexpected("Sem sessão.") }
        return try await client.detail(invoice)
    }

    func classify(_ invoice: Invoice, detail: InvoiceDetail, sector: String) async throws -> InvoiceDetail {
        guard let client else { throw PortalError.unexpected("Sem sessão.") }
        return try await client.classify(invoice, detail: detail, sector: sector)
    }

    /// Classifies several invoices with the same sector; returns the ones that failed.
    func classify(_ list: [Invoice], sector: String) async -> [(Invoice, String)] {
        var failures: [(Invoice, String)] = []
        for invoice in list {
            do {
                let d = try await detail(invoice)
                _ = try await classify(invoice, detail: d, sector: sector)
            } catch {
                failures.append((invoice, error.localizedDescription))
            }
        }
        await refresh(force: true)
        return failures
    }

    /// The year's invoices as a CSV file (opens in Numbers or Excel).
    func exportCSV() -> URL? {
        var rows = ["Data;Comerciante;NIF;Tipo;Número;Setor;Estado;IVA;Total;Dedução"]
        func money(_ c: Int?) -> String { String(format: "%.2f", Double(c ?? 0) / 100).replacingOccurrences(of: ".", with: ",") }
        func clean(_ s: String?) -> String { (s ?? "").replacingOccurrences(of: ";", with: ",") }
        for i in invoices {
            rows.append([i.dataEmissaoDocumento, clean(i.merchant), i.nifEmitente.map(String.init) ?? "",
                         clean(i.tipoDocumentoDesc), clean(i.numerodocumento), clean(i.actividadeEmitenteDesc),
                         clean(i.estadoBeneficioDesc), money(i.valorTotalIva), money(i.valorTotal),
                         money(i.valorTotalBeneficioProv)].joined(separator: ";"))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("faturas-\(year).csv")
        do {
            try ("\u{FEFF}" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
