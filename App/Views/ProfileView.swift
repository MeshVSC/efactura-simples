import SwiftUI
import CoreImage.CIFilterBuiltins

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var addingAccount = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if let account = model.current {
                        Section {
                            TaxpayerCard(account: account)
                                .frame(maxWidth: 440)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        NavigationLink {
                            TaxProfileView()
                        } label: {
                            // Button look: padded grey-glass pill with a chevron.
                            HStack(spacing: 10) {
                                Image(systemName: "person.2.badge.gearshape")
                                    .foregroundStyle(Color.efaturaBlue)
                                Text("Situação fiscal")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(model.limits.map { "Máximo \($0.maximum.euros)" } ?? "Por preencher")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: 440)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Usada para calcular os limites exatos das deduções e quanto ainda pode deduzir.")
                    }

                    Section("Contas") {
                        ForEach(model.accounts) { account in
                            Button {
                                Task { await model.switchTo(account) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(account.name.isEmpty ? account.nif : account.name)
                                            .foregroundStyle(.primary)
                                        Text(account.nif).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if account.nif == model.current?.nif {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .frame(maxWidth: 440)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { model.accounts[$0] }.forEach(model.remove)
                        }
                        Button { addingAccount = true } label: { Label("Adicionar conta", systemImage: "plus") }
                    }

                    Section("Exportar") {
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Exportar faturas de \(String(model.year))", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                    Section {
                        Button("Terminar sessão", role: .destructive) { model.signOut() }
                    } footer: {
                        Text("Aplicação independente. Não é afiliada nem endossada pela Autoridade Tributária e Aduaneira.")
                    }
                }
                // No dividing lines between rows.
                .listRowSeparator(.hidden)
            }
            .navigationTitle("Perfil")
            .sheet(isPresented: $addingAccount) {
                LoginView(onDone: { addingAccount = false })
            }
            .task(id: "\(model.year)-\(model.invoices.count)") { exportURL = model.exportCSV() }
        }
    }
}

struct TaxpayerCard: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.headline)
                Text("NIF \(account.nif)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 16) {
                code(Self.qr(account.nif))
                    .frame(width: 110, height: 110)
                code(Self.barcode(account.nif))
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func code(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
        }
    }

    private static let context = CIContext()

    private static func render(_ output: CIImage?) -> CGImage? {
        guard let output = output?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    static func qr(_ text: String) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        return render(f.outputImage)
    }

    static func barcode(_ text: String) -> CGImage? {
        let f = CIFilter.code128BarcodeGenerator()
        f.message = Data(text.utf8)
        f.quietSpace = 0
        return render(f.outputImage)
    }
}
