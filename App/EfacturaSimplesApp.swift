import SwiftUI

@main
struct EfacturaSimplesApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.light)
                #endif
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.current != nil {
                #if os(macOS)
                MacRootView()
                #else
                TabView {
                    SummaryView()
                        .tabItem { Label("Resumo", systemImage: "chart.pie.fill") }
                    InvoicesView()
                        .tabItem { Label("Faturas", systemImage: "doc.text.fill") }
                    PendingView()
                        .tabItem { Label("Pendentes", systemImage: "exclamationmark.circle.fill") }
                        .badge(model.pending.count)
                    ExpensesView()
                        .tabItem { Label("Despesas", systemImage: "chart.bar.fill") }
                    ProfileView()
                        .tabItem { Label("Perfil", systemImage: "person.crop.circle.fill") }
                }
                #endif
            } else if model.restoring {
                ProgressView()
            } else {
                LoginView()
            }
        }
        .alert("Erro", isPresented: Binding(get: { model.errorMessage != nil },
                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Year menu shared by the tabs.
struct YearPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Menu {
            Picker("Ano", selection: Binding(get: { model.year }, set: { year in
                model.year = year
                Task { await model.refresh() }
            })) {
                ForEach(model.years.sorted(by: >), id: \.self) { Text(String($0)).tag($0) }
            }
        } label: {
            Label(String(model.year), systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        }
    }
}
