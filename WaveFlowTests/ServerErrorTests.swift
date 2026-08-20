import Foundation
import Testing
@testable import WaveFlow

/// La lecture des réponses d'erreur.
///
/// Ce qui se joue ici est la règle que le contrat répète : **le statut 409 ne
/// suffit pas**. Il porte deux codes aux reprises opposées, et les confondre
/// perd une écriture ou efface une projection saine.
struct ServerErrorTests {

    @Test func readsNoErrorFromASuccess() {
        #expect(ServerError.from(status: 200, body: Data()) == nil)
        #expect(ServerError.from(status: 204, body: Data()) == nil)
    }

    @Test func distinguishesTheTwoMeaningsOf409() {
        #expect(ServerError.from(status: 409, body: body(code: "conflict")) == .operationConflict)
        #expect(ServerError.from(status: 409, body: body(code: "cursor_expired")) == .cursorExpired)
    }

    /// Un 409 dont le code est inconnu — ou absent — n'est ni l'un ni l'autre.
    /// Le deviner reviendrait à choisir au hasard entre deux reprises qui
    /// s'excluent.
    @Test func refusesToGuessAnUnknown409() {
        #expect(ServerError.from(status: 409, body: body(code: "something_new"))
            == .unexpected(status: 409, code: "something_new"))
        #expect(ServerError.from(status: 409, body: Data())
            == .unexpected(status: 409, code: nil))
    }

    @Test func mapsTheDocumentedStatuses() {
        #expect(ServerError.from(status: 401, body: Data()) == .unauthorized)
        #expect(ServerError.from(status: 403, body: Data()) == .forbidden)
        #expect(ServerError.from(status: 404, body: Data()) == .notFound)
        #expect(ServerError.from(status: 429, body: Data()) == .rateLimited)
        #expect(ServerError.from(status: 503, body: Data()) == .unavailable)
    }

    @Test func keepsTheValidationMessage() {
        let error = ServerError.from(status: 422, body: body(code: "validation_error", message: "nope"))

        #expect(error == .validation(message: "nope"))
    }

    /// Le débit, l'indisponibilité — et les pannes d'intermédiaire. Une requête
    /// fautive, elle, le restera, et un conflit d'opération réclame un
    /// identifiant neuf, donc une autre requête et pas la même.
    @Test func retriesBackpressureOutagesAndGatewayFailures() {
        #expect(ServerError.rateLimited.isRetriable)
        #expect(ServerError.unavailable.isRetriable)

        // 502 et 504 ne peuvent venir que d'un intermédiaire : le type d'erreur
        // de l'API native ne sait produire que les sept statuts documentés.
        #expect(ServerError.from(status: 502, body: Data())?.isRetriable == true)
        #expect(ServerError.from(status: 504, body: Data())?.isRetriable == true)

        // 500 non : c'est une panne que le serveur n'a pas su nommer, et la
        // rejouer telle quelle la reproduit.
        #expect(ServerError.from(status: 500, body: Data())?.isRetriable == false)

        #expect(ServerError.unauthorized.isRetriable == false)
        #expect(ServerError.notFound.isRetriable == false)
        #expect(ServerError.operationConflict.isRetriable == false)
        #expect(ServerError.cursorExpired.isRetriable == false)
        #expect(ServerError.validation(message: nil).isRetriable == false)
    }

    private func body(code: String, message: String = "peu importe") -> Data {
        Data(#"{"code":"\#(code)","message":"\#(message)"}"#.utf8)
    }
}
