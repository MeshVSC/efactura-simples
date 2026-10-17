import SwiftUI

extension Color {
    /// Blue of the official e-Fatura app (sampled from its App Store screenshots).
    static let efaturaBlue = Color(red: 0x00 / 255, green: 0x9A / 255, blue: 0xDA / 255)
}

struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var nif = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    var onDone: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Image("AppMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    Text("e-Fatura Simples")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(spacing: 0) {
                        TextField("NIF", text: $nif)
                            .numberPadKeyboard()
                            .textContentType(.username)
                            .textFieldStyle(.plain)
                            .padding(12)
                        Divider().padding(.leading, 12)
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Senha do Portal das Finanças", text: $password)
                                } else {
                                    SecureField("Senha do Portal das Finanças", text: $password)
                                }
                            }
                            .textContentType(.password)
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showPassword ? "Ocultar senha" : "Mostrar senha")
                        }
                        .padding(12)
                    }
                    .foregroundStyle(.black)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .environment(\.colorScheme, .light)
                    .onSubmit { if canSubmit { Task { await signIn() } } }
                    .submitLabel(.go)
                }

                if let error {
                    Text(error)
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    Group {
                        if busy { ProgressView().tint(Color.efaturaBlue) } else { Text("Entrar").bold() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .foregroundStyle(Color.efaturaBlue)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.6)
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        // Notes and credit, centred at the bottom of the screen.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Text("As credenciais ficam guardadas apenas neste dispositivo e são enviadas só para o Portal das Finanças.")
                Text("Aplicação independente. Não é afiliada nem endossada pela Autoridade Tributária e Aduaneira.")
                Text("Mesh Studios 2026")
                    .fontWeight(.semibold)
                    .padding(.top, 4)
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            // One line per sentence; shrinks slightly on narrow screens instead of wrapping.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.efaturaBlue.ignoresSafeArea())
        .onAppear {
            // Main login screen: prefill the last account; adding an account starts empty.
            guard onDone == nil, nif.isEmpty, let saved = model.savedLogin else { return }
            nif = saved.nif
            password = saved.password
        }
    }

    private var canSubmit: Bool { !busy && nif.count == 9 && !password.isEmpty }

    private func signIn() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.signIn(nif: nif, password: password)
            onDone?()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
