//
//  NetworkReachability.swift
//  Rclone GUI — Services
//
//  Observe le type de connexion via NWPathMonitor pour alimenter la politique
//  de génération des vignettes (« Wi-Fi seulement » évite de consommer des
//  données cellulaires en téléchargeant des images depuis les remotes).
//

import Foundation
import Network

extension Notification.Name {
    /// Postée (sur la main queue) quand l'état réseau pertinent change
    /// (en ligne/hors-ligne, cellulaire/bridé). La TransferQueue s'y abonne
    /// pour appliquer sa politique réseau (limite cellulaire, pause/reprise auto).
    static let networkPathDidChange = Notification.Name("rclone.networkPathDidChange")
}

final class NetworkReachability: @unchecked Sendable {
    static let shared = NetworkReachability()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rougetet.rclone-gui.reachability")
    private let lock = NSLock()
    private var _isExpensive = false
    private var _isConstrained = false
    private var _isSatisfied = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newExpensive = path.isExpensive       // cellulaire, partage de connexion…
            let newConstrained = path.isConstrained   // mode données réduites
            let newSatisfied = (path.status == .satisfied)
            self.lock.lock()
            let changed = newExpensive != self._isExpensive
                || newConstrained != self._isConstrained
                || newSatisfied != self._isSatisfied
            self._isExpensive = newExpensive
            self._isConstrained = newConstrained
            self._isSatisfied = newSatisfied
            self.lock.unlock()
            // Notifie les observateurs (politique de transfert) uniquement
            // quand un champ pertinent bascule, pour ne pas spammer.
            if changed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .networkPathDidChange, object: nil)
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Démarre le monitoring tôt (appelé au lancement) pour que l'état soit
    /// frais avant la première vignette. L'accès à `.shared` suffit (init).
    func activate() {}

    var isExpensive: Bool {
        lock.lock(); defer { lock.unlock() }; return _isExpensive
    }

    /// Instantané COHÉRENT des trois signaux (une seule prise de lock).
    /// À préférer quand une décision combine plusieurs champs (mode Auto) :
    /// trois lectures séparées peuvent chevaucher une bascule de path et
    /// produire un état déchiré (ex. hors-ligne + cellulaire simultanés).
    var snapshot: (online: Bool, expensive: Bool, constrained: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (_isSatisfied, _isExpensive, _isConstrained)
    }

    var isConstrained: Bool {
        lock.lock(); defer { lock.unlock() }; return _isConstrained
    }

    var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }; return _isSatisfied
    }

    /// Connexion « non facturée » : en ligne, ni coûteuse (cellulaire) ni bridée.
    var isUnmetered: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isSatisfied && !_isExpensive && !_isConstrained
    }

    /// À traiter comme du « cellulaire » pour la politique de bande passante :
    /// soit cellulaire (`isExpensive`), soit Wi-Fi bridé / données réduites
    /// (`isConstrained`). Un hotspot ou un Wi-Fi metered ne doit pas laisser
    /// filer un gros transfert comme un Wi-Fi domestique.
    var isCellularLike: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isExpensive || _isConstrained
    }
}
