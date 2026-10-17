import Foundation

/// Household facts the deduction limits depend on (Profile > Situação fiscal).
struct TaxProfile: Codable, Equatable {
    enum Household: String, Codable, CaseIterable, Identifiable {
        case single, jointCouple, separateCouple, singleParent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .single: return "Sozinho(a)"
            case .jointCouple: return "Casados / unidos de facto, tributação conjunta"
            case .separateCouple: return "Casados / unidos de facto, tributação separada"
            case .singleParent: return "Família monoparental"
            }
        }
    }

    enum Housing: String, Codable, CaseIterable, Identifiable {
        case none, rent, loanBefore2012
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "Sem encargos dedutíveis"
            case .rent: return "Arrendamento (renda)"
            case .loanBefore2012: return "Crédito habitação até 31/12/2011"
            }
        }
    }

    var household: Household = .single
    var dependents: Int = 0
    /// Annual taxable income (rendimento coletável) of the household, in euros.
    var taxableIncome: Double?
    var housing: Housing = .none
    var displacedStudent = false
}

/// Yearly maximums, in cents. `global` is nil when the law sets no overall limit.
struct DeductionLimits {
    let generalFamily: Int
    let health: Int
    let education: Int
    let housing: Int
    let careHomes: Int
    let invoiceVAT: Int
    let global: Int?
    /// True when the Profile's tax situation isn't filled in and the standard limits are used.
    var isDefault = false

    /// Yearly maximum for one sector code; `shared` is true for the invoice-VAT sectors,
    /// which all draw from the same limit.
    func maximum(for code: String) -> (amount: Int, shared: Bool)? {
        switch code {
        case "DGF": return (generalFamily, false)
        case "C05": return (health, false)
        case "C06": return (education, false)
        case "C07": return (housing, false)
        case "C08": return (careHomes, false)
        case "C01", "C02", "C03", "C04", "C09", "C10", "C11", "C12", "C13", "C14", "C15":
            return (invoiceVAT, true)
        default: return nil
        }
    }

    /// Most the household can reach: general family expenses (outside the overall limit)
    /// plus the other categories, capped by the overall limit (CIRS art. 78.º n.º 7).
    var maximum: Int {
        let others = health + education + housing + careHomes + invoiceVAT
        return generalFamily + min(others, global ?? others)
    }
}

/// Deduction limits from the Código do IRS as in force for 2026
/// (art. 68.º, 78.º, 78.º-B, 78.º-C, 78.º-D, 78.º-E, 78.º-F, 84.º; Lei 36/2024 phasing; DL 97/2026).
enum TaxRules {
    static let supportedYears: Set<Int> = [2026]

    private static func cents(_ e: Double) -> Int { Int((e * 100).rounded()) }

    /// Standard limits when the taxable income isn't known: no overall limit applied,
    /// rent at the 2026 base of 900 € (loan interest 296 €).
    private static func defaults(for p: TaxProfile) -> DeductionLimits {
        let generalFamily: Double
        switch p.household {
        case .single, .separateCouple: generalFamily = 250
        case .jointCouple: generalFamily = 500
        case .singleParent: generalFamily = 335
        }
        var health = 1_000.0, careHomes = 403.75, invoiceVAT = 250.0
        var education = p.displacedStudent ? 1_100.0 : 800.0
        var housing = p.housing == .loanBefore2012 ? 296.0 : 900.0
        if p.household == .separateCouple {
            health /= 2; careHomes /= 2; invoiceVAT /= 2; education /= 2; housing /= 2
        }
        return DeductionLimits(generalFamily: cents(generalFamily), health: cents(health),
                               education: cents(education), housing: cents(housing),
                               careHomes: cents(careHomes), invoiceVAT: cents(invoiceVAT),
                               global: nil, isDefault: true)
    }

    /// Art. 68.º n.º 1 (Lei 73-A/2025): upper value of the first bracket.
    private static let firstBracket = 8_342.0
    /// Art. 68.º-A n.º 1: minimum of the first solidarity bracket.
    private static let solidarityMin = 80_000.0

    static func limits(for p: TaxProfile, year: Int) -> DeductionLimits? {
        guard supportedYears.contains(year) else { return nil }
        guard let income = p.taxableIncome else { return defaults(for: p) }

        // Joint taxation: income after the divisor of art. 69.º (2 taxpayers).
        let rc = p.household == .jointCouple ? income / 2 : income

        // Art. 78.º-B: 35% up to 250 € per taxpayer; single-parent 45% up to 335 €.
        let generalFamily: Double
        switch p.household {
        case .single, .separateCouple: generalFamily = 250
        case .jointCouple: generalFamily = 500
        case .singleParent: generalFamily = 335
        }

        // Art. 78.º-C, 84.º, 78.º-F.
        var health = 1_000.0
        var careHomes = 403.75
        var invoiceVAT = 250.0

        // Art. 78.º-D: 800 €, plus 300 € when the difference is rent for a student
        // under 25 studying more than 50 km from home (n.º 11).
        var education = p.displacedStudent ? 1_100.0 : 800.0

        // Art. 78.º-E.
        var housing: Double
        switch p.housing {
        case .none:
            housing = 0
        case .rent:
            // n.º 4 with the Lei 36/2024 increase at 75% in 2026 (600→800 and 900→1100):
            // 750 € base and 1050 € top, with the 2026 floor of 900 € (DL 97/2026, n.º 10).
            let raised: Double
            if rc <= firstBracket {
                raised = 1_050
            } else if rc <= 30_000 {
                raised = 750 + (1_050 - 750) * ((30_000 - rc) / (30_000 - firstBracket))
            } else {
                raised = 0
            }
            housing = max(900, raised)
        case .loanBefore2012:
            if rc <= firstBracket {
                housing = 450
            } else if rc <= 30_000 {
                housing = 296 + (450 - 296) * ((30_000 - rc) / (30_000 - firstBracket))
            } else {
                housing = 296
            }
        }

        // Art. 78.º n.º 7: overall limit on health, education, housing, care homes and invoice VAT.
        var global: Double?
        if rc <= firstBracket {
            global = nil
        } else if rc <= solidarityMin {
            global = 1_000 + (2_500 - 1_000) * ((solidarityMin - rc) / (solidarityMin - firstBracket))
        } else {
            global = 1_000
        }
        // n.º 8: +5% per dependent with three or more dependents.
        if p.dependents >= 3, let g = global {
            global = g * (1 + 0.05 * Double(p.dependents))
        }

        // n.º 14: separate taxation halves the household limits.
        if p.household == .separateCouple {
            health /= 2; careHomes /= 2; invoiceVAT /= 2; education /= 2; housing /= 2
            global = global.map { $0 / 2 }
        }

        return DeductionLimits(generalFamily: cents(generalFamily), health: cents(health),
                               education: cents(education), housing: cents(housing),
                               careHomes: cents(careHomes), invoiceVAT: cents(invoiceVAT),
                               global: global.map(cents))
    }
}
