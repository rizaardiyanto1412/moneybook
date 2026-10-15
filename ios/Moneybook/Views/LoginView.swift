import SwiftUI

/// Email + password sign-in (a device session), or the API token as a fallback. Same screen as the web app.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var apiToken = ""
    @State private var useToken = false
    @State private var showServer = false
    @State private var busy = false
    @State private var error = ""
    @State private var hasPassword = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image("Logo")
                    .resizable()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: MM.dyn(0xf0544f, 0xf0544f).opacity(0.3), radius: 11, y: 8)
                    .padding(.bottom, 16)
                Text("Moneybook").font(.system(size: 28, weight: .bold)).padding(.bottom, 6)
                Text(hint).font(.system(size: 15)).foregroundStyle(MM.fg2).multilineTextAlignment(.center).lineSpacing(3).padding(.bottom, 28)
                if useToken {
                    InputField(placeholder: "API token", text: $apiToken, secure: true).submitLabel(.go).onSubmit(submit)
                } else {
                    InputField(placeholder: "Email", text: $email, keyboard: .emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    InputField(placeholder: "Password", text: $password, secure: true)
                        .textContentType(.password).submitLabel(.go).onSubmit(submit).padding(.top, 10)
                }
                if showServer {
                    InputField(placeholder: "Server, e.g. https://moneybook.example.com", text: $server, keyboard: .URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().padding(.top, 10)
                }
                Group {
                    if busy { ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 48).background(MM.accent, in: RoundedRectangle(cornerRadius: 10)) }
                    else { MMButton(title: "Sign in", action: submit) }
                }
                .padding(.top, 14)
                Text(error).font(.system(size: 14)).foregroundStyle(MM.exp).multilineTextAlignment(.center).frame(minHeight: 20).padding(.top, 10)
                Button(useToken ? "Use email and password instead" : "Use API token instead") {
                    useToken.toggle()
                    error = ""
                }
                .font(.system(size: 14.5)).foregroundStyle(MM.accent).padding(.vertical, 8).padding(.horizontal, 12).padding(.top, 6)
                if !showServer {
                    Button("Change server") { showServer = true }
                        .font(.system(size: 14.5)).foregroundStyle(MM.fg3).padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { h, _ in h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(MM.bg)
        .onAppear {
            if server.isEmpty { server = model.serverURL }
            if email.isEmpty { email = model.email }
            if let m = model.errorMessage { error = m; model.errorMessage = nil }
        }
        .task {
            // No password yet: the API token is the only way in.
            if let st = try? await model.authStatus(server: model.serverURL), !st.hasPassword {
                hasPassword = false
                useToken = true
            }
        }
    }

    private var hint: String {
        if useToken { return hasPassword ? "Sign in with your API token." : "No password is set yet. Sign in with the API token, then set one in Settings → Password." }
        return "Sign in with your email and password."
    }

    private func submit() {
        guard !busy else { return }
        if useToken ? apiToken.isEmpty : email.isEmpty || password.isEmpty { error = "Fill in every field."; return }
        busy = true
        error = ""
        Task {
            defer { busy = false }
            do {
                if useToken { try await model.signIn(server: server, apiToken: apiToken) }
                else { try await model.signIn(server: server, email: email, password: password) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
