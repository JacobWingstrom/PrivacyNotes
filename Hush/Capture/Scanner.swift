import SwiftUI
import VisionKit
import Vision
import PDFKit

/// Apple's document camera: finds page edges, flattens and cleans up scans.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.dismiss()
            parent.onFinish(pages)
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}

enum ScanProcessor {
    /// One PDF page per scanned image, letter width.
    static func pdf(from images: [UIImage]) -> Data {
        let width: CGFloat = 612
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: width, height: 792))
        return renderer.pdfData { ctx in
            for img in images {
                let h = width * img.size.height / max(img.size.width, 1)
                let rect = CGRect(x: 0, y: 0, width: width, height: h)
                ctx.beginPage(withBounds: rect, pageInfo: [:])
                img.draw(in: rect)
            }
        }
    }

    /// On-device text recognition, so scans are searchable. Nothing is uploaded.
    static func recognizeText(_ images: [UIImage]) async -> String {
        await Task.detached(priority: .userInitiated) {
            var pages: [String] = []
            for img in images {
                guard let cg = img.cgImage else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                pages.append(lines.joined(separator: "\n"))
            }
            return pages.joined(separator: "\n\n")
        }.value
    }
}
