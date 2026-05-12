import Vision
import UIKit

/// Runs Apple Vision text recognition on a local image file.
class OcrService {
    static func performOcr(imagePath: String, completion: @escaping (String?) -> Void) {
        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            completion(text.isEmpty ? nil : text)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
