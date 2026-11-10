import SwiftUI
import VisionKit
import AVFoundation

struct QRScanner: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    let unavailable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(scanned: scanned, unavailable: unavailable) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() } catch { DispatchQueue.main.async { unavailable() } }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let scanned: (String) -> Void
        let unavailable: () -> Void
        private var delivered = false
        init(scanned: @escaping (String) -> Void, unavailable: @escaping () -> Void) { self.scanned = scanned; self.unavailable = unavailable }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    delivered = true
                    dataScanner.stopScanning()
                    scanned(value)
                    return
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            dataScanner.stopScanning()
            unavailable()
        }
    }
}
