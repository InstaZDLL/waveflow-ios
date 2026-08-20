import Foundation
import Testing
@testable import WaveFlow

/// L'adresse du serveur, ramenée à son origine.
struct ServerAddressTests {

    @Test func assumesHTTPSWhenNoSchemeIsTyped() throws {
        let address = try #require(ServerAddress("music.example.com"))

        #expect(address.origin.absoluteString == "https://music.example.com")
    }

    /// Le repli est HTTPS et non HTTP : un jeton de session part sur ce lien.
    @Test func keepsAnExplicitPlainHTTPServer() throws {
        let address = try #require(ServerAddress("http://192.168.1.10:4533"))

        #expect(address.origin.absoluteString == "http://192.168.1.10:4533")
    }

    /// L'erreur que le guide d'intégration prend la peine de nommer.
    @Test func dropsTheAPIPrefixTheUserPasted() throws {
        let address = try #require(ServerAddress("https://music.example.com/api/v2"))

        #expect(address.origin.absoluteString == "https://music.example.com")
        #expect(address.api("auth/refresh").absoluteString
            == "https://music.example.com/api/v2/auth/refresh")
    }

    /// Une URL copiée depuis l'interface web porte le chemin d'une page, et
    /// parfois une requête ou une ancre. L'origine reste la bonne réponse.
    @Test func dropsPathQueryAndFragment() throws {
        let address = try #require(ServerAddress("https://music.example.com/albums?sort=newest#top"))

        #expect(address.origin.absoluteString == "https://music.example.com")
    }

    @Test func dropsATrailingSlashRatherThanDoublingIt() throws {
        let address = try #require(ServerAddress("https://music.example.com/"))

        #expect(address.api("libraries").absoluteString
            == "https://music.example.com/api/v2/libraries")
    }

    /// L'écran d'autorisation n'est pas sous `/api/v2` : c'est une page de
    /// l'interface embarquée.
    @Test func buildsRootPathsWithoutTheAPIPrefix() throws {
        let address = try #require(ServerAddress("https://music.example.com"))

        #expect(address.root("authorize").absoluteString == "https://music.example.com/authorize")
        #expect(address.root("health").absoluteString == "https://music.example.com/health")
    }

    @Test func keepsAPortAndLowercasesTheHost() throws {
        let address = try #require(ServerAddress("HTTPS://Music.Example.COM:8443"))

        #expect(address.origin.absoluteString == "https://music.example.com:8443")
    }

    /// Une adresse peut arriver avec des identifiants — un gestionnaire de mots
    /// de passe en fabrique, un vieux marque-page en garde. Les retenir, c'est
    /// écrire un mot de passe en clair dans les préférences ; les refuser,
    /// c'est arrêter quelqu'un dont l'adresse est bonne. L'origine est gardée,
    /// les identifiants tombent.
    @Test func stripsCredentialsFromTheAddress() throws {
        let address = try #require(ServerAddress("https://listener:motdepasse@music.example.com"))

        #expect(address.origin.absoluteString == "https://music.example.com")
        #expect(address.origin.user == nil)
        #expect(address.origin.password == nil)
    }

    @Test func trimsSurroundingWhitespace() throws {
        let address = try #require(ServerAddress("  https://music.example.com \n"))

        #expect(address.origin.absoluteString == "https://music.example.com")
    }

    @Test(arguments: [
        "",
        "   ",
        "https://",
        "ftp://music.example.com",
        // Un schéma qu'on ne sait pas parler ne doit pas devenir un hôte.
        "waveflow://music.example.com",
    ])
    func refusesWhatIsNotAnHTTPOrigin(_ typed: String) {
        #expect(ServerAddress(typed) == nil, "« \(typed) » aurait dû être refusé")
    }
}
