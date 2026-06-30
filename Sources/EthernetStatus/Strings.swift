import Foundation

enum Language: String, CaseIterable {
    case en, de, fr

    static var current: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: "app.language") ?? "en") ?? .en }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "app.language") }
    }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        }
    }
}

struct Strings {
    private static func p(_ en: String, _ de: String, _ fr: String) -> String {
        switch Language.current {
        case .en: return en
        case .de: return de
        case .fr: return fr
        }
    }

    static var noAdapters:      String { p("No network adapters found",     "Keine Netzwerkadapter gefunden",   "Aucun adaptateur réseau trouvé") }
    static var networkOrder:    String { p("Network Priority",               "Netzwerk-Reihenfolge",             "Priorité réseau") }
    static var connected:       String { p("● Connected",                    "● Verbunden",                      "● Connecté") }
    static var disconnected:    String { p("◌ Disconnected",                 "◌ Getrennt",                       "◌ Déconnecté") }
    static var disabledStatus:  String { p("○ Disabled",                     "○ Deaktiviert",                    "○ Désactivé") }
    static var subnet:          String { p("Subnet",                         "Subnetz",                          "Sous-réseau") }
    static var linkSpeedLabel:  String { p("Speed",                          "Geschwindigkeit",                  "Vitesse") }
    static var signalLabel:     String { p("Signal",                         "Signal",                           "Signal") }
    static var sigWeak:         String { p("Weak",                           "Schwach",                          "Faible") }
    static var sigFair:         String { p("Fair",                           "Mäßig",                            "Moyen") }
    static var sigGood:         String { p("Good",                           "Gut",                              "Bon") }
    static var sigExcellent:    String { p("Excellent",                      "Sehr gut",                         "Excellent") }
    static var startTest:       String { p("⚡ Start Speedtest",             "⚡ Speedtest starten",             "⚡ Démarrer le test") }
    static var testRunning:     String { p("⏳ Speedtest running (~30 s)…",  "⏳ Speedtest läuft (~30 s)…",      "⏳ Test en cours (~30 s)…") }
    static var testRetry:       String { p("↺ Test again",                   "↺ Nochmal testen",                 "↺ Tester à nouveau") }
    static var testFailed:      String { p("Test failed",                    "Test fehlgeschlagen",              "Test échoué") }
    static var testUnavailable: String { p("networkQuality not available",   "networkQuality nicht verfügbar",   "networkQuality non disponible") }
    static var moveUp:          String { p("     ↑ Move up",                 "     ↑ Höher",                     "     ↑ Monter") }
    static var moveDown:        String { p("     ↓ Move down",               "     ↓ Niedriger",                 "     ↓ Descendre") }
    static var refresh:         String { p("Refresh",                        "Aktualisieren",                    "Actualiser") }
    static var netSettings:     String { p("Network Settings…",              "Netzwerkeinstellungen…",           "Réglages réseau…") }
    static var quit:            String { p("Quit",                           "Beenden",                          "Quitter") }
    static var languageMenu:    String { p("Language",                       "Sprache",                          "Langue") }
    static var copied:          String { p("✓ Copied!",                      "✓ Kopiert!",                       "✓ Copié !") }

    static func toggle(enabled: Bool, isWifi: Bool, isIphone: Bool) -> String {
        switch (enabled, isWifi, isIphone) {
        case (true,  true,  _):     return p("Disable Wi-Fi",      "WLAN deaktivieren",        "Désactiver le Wi-Fi")
        case (false, true,  _):     return p("Enable Wi-Fi",       "WLAN aktivieren",          "Activer le Wi-Fi")
        case (true,  false, true):  return p("Disable iPhone USB", "iPhone USB deaktivieren",  "Désactiver iPhone USB")
        case (false, false, true):  return p("Enable iPhone USB",  "iPhone USB aktivieren",    "Activer iPhone USB")
        case (true,  false, false): return p("Disable Ethernet",   "Ethernet deaktivieren",    "Désactiver l'Ethernet")
        case (false, false, false): return p("Enable Ethernet",    "Ethernet aktivieren",      "Activer l'Ethernet")
        }
    }
}
