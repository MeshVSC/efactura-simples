import Foundation
import SwiftUI

/// Sector codes and names, copied from the portal's own select lists.
struct Sector: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String
    /// Icon colour, copied from the portal's stylesheet (.benefbox1 .atf-*).
    var hex: UInt32 = 0x8E8E93
    var id: String { code }

    var color: Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static let all: [Sector] = [
        Sector(code: "DGF", name: "Despesas Gerais Familiares", symbol: "figure.2.and.child.holdinghands", hex: 0x48C1DA),
        Sector(code: "C05", name: "Saúde", symbol: "cross.case.fill", hex: 0xFF5A59),
        Sector(code: "C06", name: "Educação", symbol: "graduationcap.fill", hex: 0xFF893A),
        Sector(code: "C07", name: "Habitação", symbol: "house.fill", hex: 0x95D655),
        Sector(code: "C08", name: "Lares", symbol: "bed.double.fill", hex: 0x6CB664),
        Sector(code: "C01", name: "Reparação de Automóveis", symbol: "car.fill", hex: 0x357DB0),
        Sector(code: "C02", name: "Reparação de Motociclos", symbol: "scooter", hex: 0x55A3DB),
        Sector(code: "C03", name: "Restauração e Alojamento", symbol: "fork.knife", hex: 0xFEBC17),
        Sector(code: "C04", name: "Cabeleireiros", symbol: "scissors", hex: 0xA98DDF),
        Sector(code: "C09", name: "Atividades Veterinárias", symbol: "pawprint.fill", hex: 0xD07361),
        Sector(code: "C10", name: "Transportes Públicos Coletivos", symbol: "bus.fill", hex: 0x309FFA),
        Sector(code: "C11", name: "Ginásios", symbol: "dumbbell.fill", hex: 0x942192),
        Sector(code: "C12", name: "Jornais e Revistas", symbol: "newspaper.fill", hex: 0xC86C44),
        Sector(code: "C13", name: "Comércio a Retalho de Livros", symbol: "book.fill", hex: 0xF1743B),
        Sector(code: "C14", name: "Atividades Artísticas e Literárias", symbol: "theatermasks.fill", hex: 0x763FDF),
        Sector(code: "C15", name: "Atividades dos Museus e Monumentos Históricos", symbol: "building.columns.fill", hex: 0xB8CFA1),
        Sector(code: "C99", name: "Outros", symbol: "ellipsis.circle.fill", hex: 0x8E8E93),
    ]

    static func named(_ code: String?) -> Sector? {
        guard let code else { return nil }
        return all.first { $0.code == code }
    }

    /// Categories that can be used as a list filter (the portal's filter has no C99).
    static let filters: [Sector] = all.filter { $0.code != "C99" }
}

struct CategorySummary: Identifiable {
    let code: String
    let title: String
    let deduction: Int
    let spent: Int?
    let vat: Int?
    var id: String { code }
}

struct YearSummary {
    let year: Int
    let total: Int
    let categories: [CategorySummary]
}

/// One row of json/obterDocumentosIRSAdquirente.action (amounts in cents).
struct Invoice: Decodable, Identifiable, Hashable {
    let idDocumento: Int64
    let nifEmitente: Int64?
    let nomeEmitente: String?
    let tipoDocumento: String?
    let tipoDocumentoDesc: String?
    let numerodocumento: String?
    let dataEmissaoDocumento: String
    let valorTotal: Int?
    let valorTotalIva: Int?
    let valorTotalBeneficioProv: Int?
    let estadoBeneficio: String?
    let estadoBeneficioDesc: String?
    let actividadeEmitente: String?
    let actividadeEmitenteDesc: String?
    let atcud: String?
    let isDocumentoEstrangeiro: Bool?

    var id: Int64 { idDocumento }
    var merchant: String { nomeEmitente ?? nifEmitente.map(String.init) ?? "—" }
    var total: Int { valorTotal ?? 0 }
    var isPending: Bool { estadoBeneficio == "P" }
    var category: Sector? { Sector.named(actividadeEmitente) }

    var date: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: dataEmissaoDocumento)
    }
}

struct VatLine: Decodable, Identifiable {
    let idLinha: Int64?
    let valorBaseTributavel: Int?
    let valorIva: Int?
    let valorTotal: Int?
    let taxaIva: Int?
    let taxa: String?
    let regiaoTaxaDesc: String?
    var id: Int64 { idLinha ?? Int64(valorTotal ?? 0) }
}

struct InvoiceDetail {
    let status: String?
    let nifEmitente: String?
    let atcud: String?
    let hash: String
    let linesJSON: String
    let lines: [VatLine]
    let currentSector: String?
    let sectorOptions: [Sector]
}

struct Account: Identifiable, Hashable, Codable {
    let nif: String
    var name: String
    var id: String { nif }
}
