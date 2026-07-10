//
//  HandoffPassphrase.swift
//  Rclone GUI — Core/Handoff
//
//  Diceware-style passphrase generator for Handoff P2P. Produces a
//  6-word passphrase drawn from one of two curated wordlists (256 FR or
//  256 EN words). Six draws from 256 give 2^48 ≈ 281 trillion
//  combinations, well above "offline brute force" resistance for the
//  short-lived (1 hour) Handoff session.
//
//  Words are 4-8 chars, all lowercase, all ASCII for EN / accented for FR
//  but kept typable on a French AZERTY keyboard without dead keys.
//
//  The passphrase is the only secret that protects the QR / AirDrop blob
//  if it leaks (e.g. someone photographs the screen from across a café).
//  It is NEVER stored, NEVER logged, NEVER sent over the network.
//

import Foundation

public enum HandoffPassphraseLanguage: String, CaseIterable, Sendable {
    case french
    case english
}

public enum HandoffPassphraseError: Error, LocalizedError, Sendable {
    case wordCountOutOfRange(Int)
    case wordNotInWordlist(String, HandoffPassphraseLanguage)

    public var errorDescription: String? {
        switch self {
        case .wordCountOutOfRange(let n):
            return String(localized: "La passphrase doit comporter entre 3 et 8 mots (reçu : \(n)).")
        case .wordNotInWordlist(let word, let lang):
            return String(localized: "« \(word) » n'appartient pas à la liste \(lang == .french ? "française" : "anglaise").")
        }
    }
}

public enum HandoffPassphrase {

    public nonisolated static let minWords = 3
    public nonisolated static let maxWords = 8
    public nonisolated static let defaultWords = 6

    public nonisolated static let wordCount: Int = 256

    public nonisolated static let bitsPerWord: Double = 8.0

    public nonisolated static func entropyBits(for words: Int) -> Double {
        Double(words) * bitsPerWord
    }

    public nonisolated static func generate(
        language: HandoffPassphraseLanguage = .french,
        words count: Int = HandoffPassphrase.defaultWords
    ) -> [String] {
        let resolved = (minWords...maxWords).contains(count) ? count : defaultWords
        let list = wordlist(for: language)
        var rng = SystemRandomNumberGenerator()
        var out: [String] = []
        out.reserveCapacity(resolved)
        for _ in 0..<resolved {
            let idx = Int(rng.next(upperBound: UInt64(Self.wordCount)))
            out.append(list[idx])
        }
        return out
    }

    public nonisolated static func join(_ words: [String], separator: String = " ") -> String {
        words.joined(separator: separator)
    }

    public nonisolated static func split(_ passphrase: String) -> [String] {
        passphrase
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }
    }

    public nonisolated static func validate(
        words: [String],
        language: HandoffPassphraseLanguage
    ) throws {
        guard (minWords...maxWords).contains(words.count) else {
            throw HandoffPassphraseError.wordCountOutOfRange(words.count)
        }
        let set = Set(wordlist(for: language))
        for w in words {
            guard set.contains(w) else {
                throw HandoffPassphraseError.wordNotInWordlist(w, language)
            }
        }
    }

    public nonisolated static func wordlist(for language: HandoffPassphraseLanguage) -> [String] {
        switch language {
        case .french:
            return Self.frenchWordlist
        case .english:
            return Self.englishWordlist
        }
    }
}

nonisolated private extension HandoffPassphrase {

    static let englishWordlist: [String] = [
        "able","acid","acre","afar","aged","airy","ajar","aloe",
        "amber","apple","aptly","arena","armor","arrow","ashes","atlas",
        "aurora","autumn","awoke","axiom","azure","bacon","badge","bagel",
        "baker","balmy","banjo","barge","basil","baton","bayou","beach",
        "beacon","beetle","berry","birch","blaze","bleak","bliss","bonus",
        "bouncy","bramble","breeze","bright","brook","brush","bubble","bucket",
        "cactus","canoe","canyon","carbon","castle","cedar","chalk","cherry",
        "cipher","citrus","clay","clerk","cliff","cloud","clover","cobalt",
        "cocoa","comet","copper","coral","cosmic","cotton","courage","crane",
        "crater","creek","crisp","crown","crystal","cube","curio","daisy",
        "dandy","dawn","decaf","delta","demon","depot","desert","diamond",
        "diesel","dilly","disco","ditto","diver","dizzy","donor","dough",
        "dragon","drift","drum","dunes","easily","ebony","echo","eden",
        "elder","elfin","ember","emerald","empire","envoy","ether","fable",
        "factor","faded","fairy","falcon","fancy","feast","feather","fern",
        "festive","fibula","fiddle","figment","finch","fjord","flake","flame",
        "flask","flick","flint","flora","fluff","flux","forest","fossil",
        "fountain","fresco","frost","fudge","fungus","fury","gable","galaxy",
        "garlic","gasoline","gauge","gavel","gemini","ginger","glacier","globe",
        "gnomon","golden","grace","granite","green","griffin","grove","guava",
        "guitar","gypsum","hammer","happi","harbor","harvest","hazel","helix",
        "herald","heron","hickory","hinge","hippo","hockey","honey","horizon",
        "hunter","husky","iguana","impala","inbox","indigo","island","ivory",
        "jade","jasper","jersey","jetty","jewel","jolly","joyful","junior",
        "kayak","keen","kelp","kettle","keyhole","kindle","kitten","kiwi",
        "knight","koala","lacquer","ladder","laguna","lakeside","lantern","lapis",
        "lavender","leafy","legend","lemon","lichen","lighthouse","lilac","lily",
        "linen","lobby","lodge","loki","lotus","lucky","lunar","magnet",
        "mango","maple","marble","marigold","marvel","meadow","melody","mellow",
        "mercury","merry","meteor","mica","midnight","mighty","mint","mirror",
        "mocha","mole","molten","monsoon","moon","mosaic","muffin","mural",
        "muse","musket","myrtle","nectar","neon","nestle","nickel","nimble",
    ]

    static let frenchWordlist: [String] = [
        "abeille","acier","adieu","agence","aigle","aimant","alarme","album",
        "algues","amande","amiral","ancre","ange","anis","arcade","argent",
        "argile","armure","astral","atlas","aurore","avion","azur","badge",
        "baie","balai","balise","bambou","banane","banjo","barque","bassin",
        "bavard","berger","bijou","bisou","blason","bleuet","bobine","bocal",
        "bolide","bonbon","botte","bouchon","boucle","bougie","bouleau","boussole",
        "brique","brume","buffle","bulle","cactus","cadran","caillou","calme",
        "camion","canard","canot","capot","carmin","cascade","casque","caverne",
        "cerise","cerne","chardon","chemin","chili","chocolat","cierge","citron",
        "civette","cloche","clown","cochon","coffre","colibri","colline","comete",
        "compas","coquelicot","corail","corbeau","cordage","cosmos","coton","couleur",
        "coupole","courgette","crampon","cratere","crepuscule","crevette","cristal","crocus",
        "croix","cuir","cypres","dahlia","dauphin","deesse","delta","detour",
        "diamant","disco","disque","dolmen","donjon","doyen","drapeau","eclair",
        "ecorce","ecume","emeraude","empire","encre","epice","epee","erable",
        "escale","etang","etoile","etuve","falaise","falcon","famine","faucon",
        "feerie","feuillage","fils","flamme","fleche","flocon","flore","flux",
        "foyer","framboise","frisson","fuchsia","fumee","fusain","gachis","galet",
        "galop","gare","gateau","gauche","geai","gelule","gemme","germe",
        "gingembre","girafe","givre","glacon","glycine","gondole","gorille","gourde",
        "grain","graminee","grenade","griffe","grillon","grotte","guepe","gui",
        "guitare","hache","haleine","hamac","haricot","harpe","helice","henne",
        "herisson","hibiscus","hirondelle","huile","hutte","indigo","ivoire","jade",
        "jais","jasmin","jaune","jersey","jetee","jeudi","jeunesse","jonquille",
        "jouet","joyau","kayak","kiwi","koala","lacet","lagune","laine",
        "lampe","lance","lapis","lavande","lezard","lierre","lilas","limon",
        "linon","liseron","litre","lobe","logis","luge","lumiere","lustre",
        "lyre","macaron","machoire","magie","mais","manche","mangouste","marbre",
        "marin","maree","matin","mauve","medaille","menhir","merou","meteore",
        "meute","miel","mirage","mistral","moka","moule","mousse","myrtille",
        "nacre","nappe","navet","nemeton","nielle","nimbe","noces","noeud",
        "nymphe","obel","octave","oeillet","oiseau","olive","ondine","opale",
    ]
}
