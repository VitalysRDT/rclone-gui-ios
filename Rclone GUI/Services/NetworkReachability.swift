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
            self.lock.lock()
            self._isExpensive = path.isExpensive          // cellulaire, partage de connexion…
            self._isConstrained = path.isConstrained      // mode données réduites
            self._isSatisfied = (path.status == .satisfied)
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    /// Démarre le monitoring tôt (appelé au lancement) pour que l'état soit
    /// frais avant la première vignette. L'accès à `.shared` suffit (init).
    func activate() {}

    var isExpensive: Bool {
        lock.lock(); defer { lock.unlock() }; return _isExpensive
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
}
