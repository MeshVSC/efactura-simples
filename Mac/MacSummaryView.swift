import SwiftUI

/// Mac Summary: total on top, one card per category in a grid.
struct MacSummaryView: View {
    @EnvironmentObject var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    DeductionHeader(totalSize: 44)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                    if let summary = model.summary {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(summary.categories) { item in
                                NavigationLink {
                                    CategoryInvoicesView(code: item.code, title: item.title)
                                } label: {
                                    SummaryCard(item: item, maximum: model.limits?.maximum(for: item.code))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if model.loading {
                        ProgressView().padding(.top, 40)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Resumo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { YearPicker() }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.refresh(force: true) } } label: {
                        Label("Atualizar", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct SummaryCard: View {
    let item: CategorySummary
    var maximum: (amount: Int, shared: Bool)?
    @State private var hovering = false

    private var sector: Sector? { Sector.named(item.code) }
    private var empty: Bool { item.spent == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: sector?.symbol ?? "tag.fill")
                    .font(.title2)
                    .foregroundStyle(sector?.color ?? .secondary)
                    .frame(width: 32)
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(item.deduction.euros)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(alignment: .firstTextBaseline) {
                Text(detail)
                Spacer(minLength: 8)
                if let maximum {
                    // Most that can be deducted in this category (VAT sectors share one limit).
                    Text("máx. \(maximum.amount.euros)" + (maximum.shared ? " comum" : ""))
                        .help(maximum.shared ? "Limite partilhado por todos os setores de exigência de fatura" : "")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.2 : 0.08))
        )
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 8 : 3, y: 2)
        .opacity(empty ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var detail: String {
        guard let spent = item.spent else { return "Sem despesas registadas" }
        if let vat = item.vat { return "Gasto \(spent.euros) · IVA \(vat.euros)" }
        return "Gasto \(spent.euros)"
    }
}
