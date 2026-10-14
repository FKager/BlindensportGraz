import Foundation
import Supabase

// German, user-facing text for Supabase Auth / RPC errors.
nonisolated enum AuthErrorMessage {
    static func text(for error: Error) -> String {
        if let auth = error as? AuthError {
            switch auth.errorCode {
            case .invalidCredentials:
                return String(localized: "E-Mail-Adresse oder Passwort ist falsch.")
            case .emailNotConfirmed:
                return String(localized: "Bitte bestätige zuerst deine E-Mail-Adresse über den Link, den wir dir geschickt haben.")
            case .userAlreadyExists, .emailExists:
                return String(localized: "Für diese E-Mail-Adresse gibt es bereits ein Konto. Bitte melde dich an.")
            case .weakPassword:
                return String(localized: "Das Passwort ist zu schwach: mindestens 10 Zeichen mit Buchstaben und Ziffern.")
            case .overEmailSendRateLimit:
                return String(localized: "Zu viele E-Mails in kurzer Zeit. Bitte versuche es später noch einmal.")
            case .samePassword:
                return String(localized: "Das neue Passwort muss sich vom bisherigen unterscheiden.")
            case .reauthenticationNeeded, .reauthenticationNotValid:
                return String(localized: "Bitte melde dich erneut an und ändere dann das Passwort.")
            case .userBanned:
                return String(localized: "Dieses Konto ist gesperrt. Bitte wende dich an den Verein.")
            case .sessionNotFound, .sessionExpired:
                return String(localized: "Die Sitzung ist abgelaufen. Bitte fordere einen neuen Link an.")
            default:
                // Unmapped: keep the server's code visible, so a report can be traced.
                return String(localized: "Etwas ist schiefgelaufen (\(auth.errorCode.rawValue)). Bitte versuche es später noch einmal.")
            }
        }
        if let postgrest = error as? PostgrestError, postgrest.hint == "target_root" {
            return String(localized: "Root-Konten können nicht gesperrt oder gelöscht werden. Ändere zuerst die Rolle.")
        }
        if let postgrest = error as? PostgrestError, postgrest.code == "42501" {
            return String(localized: "Dafür fehlt dir die Berechtigung.")
        }
        if let postgrest = error as? PostgrestError, postgrest.message.contains("last root") {
            return String(localized: "Das letzte Root-Konto kann nicht entfernt werden.")
        }
        if (error as? URLError) != nil {
            return String(localized: "Keine Verbindung zum Server. Bitte versuche es später noch einmal.")
        }
        return String(localized: "Etwas ist schiefgelaufen. Bitte versuche es später noch einmal.")
    }
}
