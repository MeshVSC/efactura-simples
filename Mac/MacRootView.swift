import SwiftUI

/// Mac layout: sidebar on the left, the selected section on the right.
struct MacRootView: View {
    @EnvironmentObject var model: AppModel

    enum Section: String, CaseIterable, Identifiable {
        case summary, invoices, pending, expenses, profile
        var id: String { rawValue }

        var title: String {
            switch self {
            case .summary: return "Resumo"
            case .invoices: return "Faturas"
            case .pending: return "Pendentes"
            case .expenses: return "Despesas"
            case .profile: return "Perfil"
            }
        }

        var symbol: String {
            switch self {
            case .summary: return "chart.pie.fill"
            case .invoices: return "doc.text.fill"
            case .pending: return "exclamationmark.circle.fill"
            case .expenses: return "chart.bar.fill"
            case .profile: return "person.crop.circle.fill"
            }
        }
    }

    @State private var section: Section? = .summary
    @State private var selectedInvoice: Invoice?

    var body: some View {
        if section == .invoices {
            // Faturas: Apple's three-column layout (sidebar | table | details);
            // every divider can be dragged and macOS remembers the widths.
            NavigationSplitView {
                sidebar
            } content: {
                MacInvoicesView(selected: $selectedInvoice)
                    .navigationSplitViewColumnWidth(min: 360, ideal: 460)
            } detail: {
                if let invoice = selectedInvoice {
                    NavigationStack {
                        InvoiceDetailView(invoice: invoice)
                            .id(invoice.id)
                    }
                    .navigationSplitViewColumnWidth(min: 340, ideal: 420)
                } else {
                    ContentUnavailableView("Selecione uma fatura", systemImage: "doc.text")
                }
            }
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                switch section ?? .summary {
                case .summary: MacSummaryView()
                case .invoices: EmptyView()
                case .pending: PendingView()
                case .expenses: ExpensesView()
                case .profile: ProfileView()
                }
            }
        }
    }

    private var sidebar: some View {
        List(Section.allCases, selection: $section) { item in
            Label(item.title, systemImage: item.symbol)
                .badge(item == .pending ? model.pending.count : 0)
                .tag(item)
        }
        .environment(\.sidebarRowSize, .large)
        // Fixed width: the sidebar can't be dragged wider or narrower.
        .navigationSplitViewColumnWidth(230)
    }
}
