import SwiftUI

/// A pending account enters the one-time code an admin created for it
/// (App-Konten → Aktivierungscode). The server checks the code belongs to
/// this account; if the admin linked a roster entry, the account is approved
/// and a token refresh unlocks the full app.
struct RedeemActivationCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthContext.self) private var authContext
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Aktivierungscode", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                } footer: {
                    Text("Den Code bekommst du von einem Admin. Er gilt 14 Tage und nur für dein Konto.")
                }
            }
            .navigationTitle("Aktivierungscode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Einlösen") { Task { await redeem() } }
                        .disabled(isWorking || ActivationCode.normalized(code).count != 8)
                }
            }
        }
    }

    private func redeem() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            if try await SupabaseApprovalService.redeemActivationCode(code) {
                await authContext.refresh()
                dismiss()
            } else {
                errorMessage = String(localized: "Der Code ist ungültig, abgelaufen oder schon verwendet.")
            }
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
