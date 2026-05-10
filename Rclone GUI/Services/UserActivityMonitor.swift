//
//  UserActivityMonitor.swift
//  Rclone GUI — Services
//
//  Détecte l'interaction utilisateur (taps, scrolls, gestures) sur toutes les
//  windows actives. Quand l'utilisateur navigue activement (= a interagi
//  dans les 5 dernières secondes), `isUserActive` passe à true et notifie
//  via `userActivityDidChange`. TransferQueue s'y abonne pour throttler la
//  bandwidth rclone et libérer du CPU/network pour le UI.
//
//  Implémentation : un PassthroughGestureRecognizer attaché à chaque UIWindow
//  qui passe en .failed à chaque touchesBegan sans consommer l'event — donc
//  toutes les autres gesture recognizers de SwiftUI continuent à fonctionner
//  normalement. Un Task background décide quand on bascule vers inactive.
//

#if os(iOS)
import Foundation
import UIKit

extension Notification.Name {
    public static let userActivityDidChange = Notification.Name("rcloneGUI.userActivityDidChange")
}

@MainActor
public final class UserActivityMonitor {
    public static let shared = UserActivityMonitor()
    private init() {}

    /// Seuil d'inactivité au-delà duquel on considère l'utilisateur comme
    /// inactif. 5s : assez court pour libérer rapidement le CPU dès que la
    /// nav s'arrête, assez long pour ne pas flapper pendant une session
    /// d'interactions rapprochées.
    private static let inactivityThreshold: TimeInterval = 5

    private var lastActivity: Date = .distantPast
    private var observerTask: Task<Void, Never>?
    private var gestureRecognizers: [ObjectIdentifier: PassthroughGestureRecognizer] = [:]
    private var sceneObserver: NSObjectProtocol?
    private var didStart = false

    /// True si l'utilisateur a interagi dans les `inactivityThreshold` dernières
    /// secondes. Surveille via `Notification.Name.userActivityDidChange`.
    public private(set) var isUserActive: Bool = false {
        didSet {
            guard oldValue != isUserActive else { return }
            NotificationCenter.default.post(
                name: .userActivityDidChange,
                object: nil,
                userInfo: ["isActive": isUserActive]
            )
        }
    }

    /// Démarre la détection. Idempotent — appel multiple OK. À appeler au
    /// boot de l'app après que les premières windows soient instanciées.
    public func start() {
        guard !didStart else { return }
        didStart = true
        attachToCurrentWindows()
        observeNewScenes()
        startInactivityObserver()
    }

    private func attachToCurrentWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                attach(to: window)
            }
        }
    }

    private func attach(to window: UIWindow) {
        let key = ObjectIdentifier(window)
        guard gestureRecognizers[key] == nil else { return }
        let recognizer = PassthroughGestureRecognizer { [weak self] in
            self?.userDidInteract()
        }
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        window.addGestureRecognizer(recognizer)
        gestureRecognizers[key] = recognizer
    }

    private func observeNewScenes() {
        // Capte les nouvelles windowScene (split-view iPad, multitâche) pour
        // attacher le recognizer aussi sur leurs windows.
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.attachToCurrentWindows()
            }
        }
    }

    private func userDidInteract() {
        lastActivity = .now
        if !isUserActive {
            isUserActive = true
        }
    }

    private func startInactivityObserver() {
        observerTask?.cancel()
        observerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.isUserActive,
                   Date().timeIntervalSince(self.lastActivity) > Self.inactivityThreshold {
                    self.isUserActive = false
                }
            }
        }
    }
}

/// GestureRecognizer transparent qui notifie chaque touchesBegan et
/// passe immédiatement en .failed pour ne pas consommer l'event. Les
/// gestures SwiftUI (tap, scroll, drag) continuent de fonctionner.
private final class PassthroughGestureRecognizer: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
#else
import Foundation

@MainActor
public final class UserActivityMonitor {
    public static let shared = UserActivityMonitor()
    private init() {}
    public var isUserActive: Bool { false }
    public func start() {}
}

extension Notification.Name {
    public static let userActivityDidChange = Notification.Name("rcloneGUI.userActivityDidChange")
}
#endif
