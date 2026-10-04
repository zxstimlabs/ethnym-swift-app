import CoreImage.CIFilterBuiltins
import EthnymKit
import SwiftUI
import VisionKit

/// A QR code, rendered dark-on-white in both appearances so any scanner can read it.
struct QRCodeImage: View {
    let value: String

    var body: some View {
        Group {
            if let image = Self.render(value) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .padding(14)
        .background(.white, in: .rect(cornerRadius: 16))
        .accessibilityLabel("QR code")
    }

    private static func render(_ value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

/// Opens the camera and fills in the first address it reads. Accepts plain addresses,
/// `eth:`, `eip155:` and `ethereum:` URIs.
struct QRScanButton: View {
    let onScan: (String) -> Void
    @State private var isScanning = false

    var body: some View {
        Button("Scan QR code", systemImage: "qrcode.viewfinder") {
            isScanning = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .sheet(isPresented: $isScanning) {
            QRScannerSheet { address in
                onScan(address)
                isScanning = false
            }
        }
    }
}

struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var unreadable: String?

    var body: some View {
        NavigationStack {
            Group {
                if !DataScannerViewController.isSupported {
                    EmptyState("Scanning unavailable", systemImage: "camera", message: "This device can't scan QR codes.")
                } else if !DataScannerViewController.isAvailable {
                    EmptyState("Camera access is off", systemImage: "camera.badge.ellipsis", message: "Allow camera access for ETHnym in Settings to scan QR codes.") {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.secondary)
                        .frame(maxWidth: 240)
                    }
                } else {
                    DataScanner { payload in
                        if let address = QRCodeParser.address(from: payload) {
                            onScan(address)
                        } else {
                            unreadable = payload
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        if let unreadable {
                            Text("Not an Ethereum address: \(unreadable.prefix(40))")
                                .font(.mono(.caption))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: .capsule)
                                .padding(.bottom, 32)
                                .transition(.blurReplace)
                        }
                    }
                    .animation(.house, value: unreadable)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .sensoryFeedback(.error, trigger: unreadable)
    }
}

/// VisionKit's live scanner, limited to QR codes.
private struct DataScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        Task { try? controller.startScanning() }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void
        private var lastPayload: String?

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(barcode) in addedItems {
                guard let payload = barcode.payloadStringValue, payload != lastPayload else { continue }
                lastPayload = payload
                onPayload(payload)
                return
            }
        }
    }
}
