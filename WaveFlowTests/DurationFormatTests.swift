import Foundation
import Testing
@testable import WaveFlow

/// Portage de `DurationFormatTest` (Android).
struct DurationFormatTests {

    @Test func formateEnMinutesSecondes() {
        #expect(formatDuration(0) == "0:00")
        #expect(formatDuration(9) == "0:09")
        #expect(formatDuration(75) == "1:15")
        #expect(formatDuration(599) == "9:59")
    }

    /// Le format bascule à partir d'une heure pleine, et les minutes passent
    /// alors sur deux chiffres — « 1:1:15 » se lirait mal.
    @Test func passeAuFormatHeureAuDelaDe3600() {
        #expect(formatDuration(3599) == "59:59")
        #expect(formatDuration(3600) == "1:00:00")
        #expect(formatDuration(3675) == "1:01:15")
        #expect(formatDuration(45296) == "12:34:56")
    }

    /// Les secondes viennent d'un tag ou d'un `CMTime` : elles peuvent être
    /// fractionnaires. La troncature, jamais l'arrondi — un morceau de 59,9 s
    /// n'affiche pas « 1:00 ».
    @Test func tronqueLesFractions() {
        #expect(formatDuration(59.9) == "0:59")
        #expect(formatDuration(0.4) == "0:00")
    }

    /// `AVPlayerItem.duration` vaut `indefinite` tant que l'item n'est pas
    /// chargé, et une durée négative n'a pas de sens : dans les deux cas
    /// l'affichage doit rester lisible plutôt que d'exploser.
    @Test func supporteLesDureesInvalides() {
        #expect(formatDuration(.infinity) == "0:00")
        #expect(formatDuration(.nan) == "0:00")
        #expect(formatDuration(-42) == "0:00")
    }

    /// Format volontairement POSIX : ni séparateur de milliers, ni chiffres
    /// localisés, quelle que soit la locale de l'appareil.
    @Test func resteEnChiffresArabes() {
        #expect(formatDuration(3675).allSatisfy { $0.isASCII })
    }

    @Test func formateLaDureeCumuleeEnMinutes() {
        #expect(formatTotalDuration(0) == "0 min")
        #expect(formatTotalDuration(59) == "0 min")
        #expect(formatTotalDuration(754) == "12 min")
        #expect(formatTotalDuration(3540) == "59 min")
    }

    @Test func formateLaDureeCumuleeEnHeures() {
        #expect(formatTotalDuration(3600) == "1 h 00")
        #expect(formatTotalDuration(3660) == "1 h 01")
        #expect(formatTotalDuration(8640) == "2 h 24")
    }
}
