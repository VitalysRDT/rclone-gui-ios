//
//  QRScannerView.swift
//  Rclone GUI — Views/Settings/Handoff
//
//  AVCaptureSession-based QR code scanner wrapped for SwiftUI.
//  Used by HandoffReceiveView in fullScreenCover. iOS only — macOS
//  has no usable built-in camera path, so the receive flow routes the
//  user to file/pasteboard on Mac instead.
//
//  iOS Info.plist requires `NSCameraUsageDescription` to be present;
//  the entitlement is in `Rclone GUI/Info.plist`.
//

#if canImport(UIKit)
import SwiftUI
import AVFoundation

struct QRScannerSheet: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    @State private var permissionDenied = false
    @State private var permissionChecked = false

    var body: some View {
        NavigationStack {
            ZStack {
                if permissionDenied {
                    permissionDeniedView
                } else {
                    QRCodeScannerView(
                        onScan: { value in
                            if HandoffEnvelope.isPayload(value) {
                                onScan(value)
                            }
                        },
                        onPermissionDenied: {
                            permissionDenied = true
                        }
                    )
                    .ignoresSafeArea()
                }
            }
            .navigationTitle("Scanner un QR")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { onCancel() }
                }
            }
        }
        .task {
            await checkPermission()
        }
    }

    @ViewBuilder
    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Accès à la caméra refusé")
                .font(.title3.weight(.semibold))
            Text("Pour scanner un QR Handoff, autorise l'accès à la caméra dans Réglages → Rclone GUI → Caméra. Tu peux aussi coller le payload manuellement.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("OK") { onCancel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(40)
    }

    private func checkPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionChecked = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionDenied = !granted
            permissionChecked = true
        case .denied, .restricted:
            permissionDenied = true
            permissionChecked = true
        @unknown default:
            permissionDenied = true
            permissionChecked = true
        }
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: QRScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, QRScannerViewControllerDelegate {
        let parent: QRCodeScannerView
        init(_ parent: QRCodeScannerView) {
            self.parent = parent
        }
        func qrScanner(_ controller: QRScannerViewController, didScan code: String) {
            parent.onScan(code)
        }
        func qrScannerPermissionDenied(_ controller: QRScannerViewController) {
            parent.onPermissionDenied()
        }
    }
}

protocol QRScannerViewControllerDelegate: AnyObject {
    func qrScanner(_ controller: QRScannerViewController, didScan code: String)
    func qrScannerPermissionDenied(_ controller: QRScannerViewController)
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerViewControllerDelegate?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.rougetet.rclone-gui.qr-scan")
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            sessionQueue.async { [weak self] in self?.startSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.sessionQueue.async { self.startSession() }
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.qrScannerPermissionDenied(self)
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.delegate?.qrScannerPermissionDenied(self) }
        @unknown default:
            DispatchQueue.main.async { self.delegate?.qrScannerPermissionDenied(self) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.qrScannerPermissionDenied(self)
            }
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.qrScannerPermissionDenied(self)
            }
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let desired: [AVMetadataObject.ObjectType] = [.qr]
        output.metadataObjectTypes = desired.filter { output.availableMetadataObjectTypes.contains($0) }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layer.addSublayer(preview)
            self.previewLayer = preview
        }
        session.startRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasReported else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        hasReported = true
        delegate?.qrScanner(self, didScan: value)
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }
}
#endif
