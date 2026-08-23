import AuthenticationServices
import SwiftUI

/// La source distante : s'y connecter, et voir à quoi on est connecté.
///
/// Le catalogue viendra prendre sa place ; pour l'instant l'écran ne fait que
/// la connexion, et le dit plutôt que de laisser croire à une page vide.
struct ServerScreen: View {

    @Environment(ServerConnection.self) private var connection
    @Environment(\.webAuthenticationSession) private var webAuthentication

    @State private var typedAddress = ""
    @State private var isConnecting = false
    @State private var addressIsInvalid = false

    var body: some View {
        @Bindable var connection = connection

        NavigationStack {
            Group {
                if let current = connection.connection {
                    connected(to: current)
                } else {
                    signIn
                }
            }
            .navigationTitle("Serveur")
            .sourcePicker()
        }
        .alert("Connexion", isPresented: Binding(
            get: { connection.failure != nil },
            set: { if !$0 { connection.dismissFailure() } },
        )) {
            Button("OK") { connection.dismissFailure() }
        } message: {
            Text(connection.failure ?? "")
        }
        .task { connection.restore() }
    }

    // MARK: - Pas encore connecté

    private var signIn: some View {
        Form {
            Section {
                TextField("music.exemple.com", text: $typedAddress)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await connect() } }
            } header: {
                Text("Adresse du serveur")
            } footer: {
                // Dit ici plutôt qu'en message d'erreur : l'adresse copiée
                // depuis le navigateur porte souvent le chemin d'une page, et
                // l'application n'en garde que l'origine.
                Text("L'adresse du serveur, sans rien après — l'application s'occupe du reste.")
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        // Le navigateur système est ouvert par-dessus ; ce
                        // témoin sert au retour, le temps de l'échange.
                        HStack {
                            ProgressView()
                            Text("Connexion…")
                        }
                    } else {
                        Text("Se connecter")
                    }
                }
                .disabled(isConnecting || ServerAddress(typedAddress) == nil)
            } footer: {
                Text("La connexion s'ouvre dans le navigateur : l'application ne voit jamais ton mot de passe.")
            }
        }
        .alert("Adresse", isPresented: $addressIsInvalid) {
            Button("OK") {}
        } message: {
            Text("Cette adresse n'est pas celle d'un serveur.")
        }
    }

    // MARK: - Connecté

    private func connected(to current: StoredConnection) -> some View {
        Form {
            Section("Compte") {
                LabeledContent("Serveur", value: current.address.origin.host() ?? "")
                LabeledContent("Utilisateur", value: current.session.username)
            }

            Section {
                Button("Se déconnecter", role: .destructive) {
                    Task { await connection.signOut() }
                }
            } footer: {
                Text("Parcourir la musique du serveur arrive dans une prochaine version.")
            }
        }
    }

    // MARK: - Actions

    /// Ouvre le navigateur système, puis échange ce qu'il rapporte.
    private func connect() async {
        guard let server = ServerAddress(typedAddress) else {
            addressIsInvalid = true
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        let authorization = connection.beginSignIn(to: server, deviceName: deviceName)

        do {
            let callback = try await webAuthentication.authenticate(
                using: authorization,
                callbackURLScheme: AuthClient.callbackScheme,
            )
            await connection.completeSignIn(callback: callback)
        } catch {
            // Navigateur refermé, le plus souvent. Rien à signaler : l'écran
            // revient au formulaire, ce qui dit déjà que rien n'a eu lieu. La
            // tentative est abandonnée pour qu'une redirection tardive ne
            // puisse plus rien installer.
            connection.cancelSignIn()
        }
    }

    /// Le nom que le serveur retiendra pour cet appareil, visible dans sa liste
    /// des sessions.
    private var deviceName: String {
        UIDevice.current.name
    }
}
