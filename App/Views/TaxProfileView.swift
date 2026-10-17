import SwiftUI

/// Profile > Situação fiscal: the facts the deduction limits depend on.
struct TaxProfileView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Group {
                Section {
                    Picker("Agregado", selection: $model.taxProfile.household) {
                        ForEach(TaxProfile.Household.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Dependentes: \(model.taxProfile.dependents)",
                            value: $model.taxProfile.dependents, in: 0...20)
                } header: {
                    Text("Agregado familiar")
                } footer: {
                    Text("Com três ou mais dependentes, o limite global das deduções aumenta 5% por dependente.")
                }

                Section {
                    TextField("Rendimento coletável anual (€)", value: $model.taxProfile.taxableIncome,
                              format: .number.precision(.fractionLength(0...2)))
                        .numberPadKeyboard()
                } header: {
                    Text("Rendimento")
                } footer: {
                    Text(model.taxProfile.household == .jointCouple
                         ? "Rendimento coletável do casal (soma dos dois). Define o limite global e o limite de habitação."
                         : "Define o limite global das deduções e o limite de habitação.")
                }

                Section("Habitação") {
                    Picker("Encargos", selection: $model.taxProfile.housing) {
                        ForEach(TaxProfile.Housing.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Toggle("Estudante deslocado com renda", isOn: $model.taxProfile.displacedStudent)
                } header: {
                    Text("Educação")
                } footer: {
                    Text("Membro do agregado com até 25 anos, a estudar a mais de 50 km da residência, com renda paga. Aumenta o limite de educação para 1 100 €.")
                }

                if let limits = TaxRules.limits(for: model.taxProfile, year: 2026) {
                    Section {
                        LabeledContent("Despesas gerais familiares", value: limits.generalFamily.euros)
                        LabeledContent("Saúde", value: limits.health.euros)
                        LabeledContent("Educação", value: limits.education.euros)
                        LabeledContent("Habitação", value: limits.housing.euros)
                        LabeledContent("Lares", value: limits.careHomes.euros)
                        LabeledContent("Exigência de fatura (IVA)", value: limits.invoiceVAT.euros)
                        LabeledContent("Limite global", value: limits.global.map(\.euros) ?? "Sem limite")
                        LabeledContent("Máximo total") { Text(limits.maximum.euros).bold() }
                    } header: {
                        Text(limits.isDefault ? "Limites padrão para 2026 (indique o rendimento para valores exatos)" : "Limites para 2026")
                    } footer: {
                        Text("Calculados segundo o Código do IRS (art.º 78.º a 78.º-F e 84.º). O limite global não abrange as despesas gerais familiares.")
                    }
                }
            }
            // No dividing lines between rows.
            .listRowSeparator(.hidden)
        }
        .formStyle(.grouped)
        .navigationTitle("Situação fiscal")
    }
}
