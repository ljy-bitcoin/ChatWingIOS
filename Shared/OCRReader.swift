import Foundation
import Vision
import CoreImage
import ImageIO

struct OCRSnapshot { var title: String; var messages: [ChatMessage] }
final class OCRReader {
    private let context = CIContext(options: [.cacheIntermediates:false])
    func read(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, crop: CropRegion, titleCrop: TitleRegion = TitleRegion()) throws -> OCRSnapshot {
        try read(image: CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation), crop: crop, titleCrop: titleCrop)
    }
    func read(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up, crop: CropRegion, titleCrop: TitleRegion = TitleRegion()) throws -> OCRSnapshot {
        try read(image: CIImage(cgImage: cgImage).oriented(orientation), crop: crop, titleCrop: titleCrop)
    }
    private func read(image: CIImage, crop: CropRegion, titleCrop: TitleRegion) throws -> OCRSnapshot {
        guard crop.isValid, titleCrop.isValid else { throw ChatWingError.message("识别区域无效") }
        let size = image.extent.size
        let scale = min(1, min(960 / size.width, 1700 / size.height))
        let reduced = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(reduced, from: reduced.extent) else { throw ChatWingError.message("无法读取画面") }
        func request() -> VNRecognizeTextRequest {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.008
            return request
        }
        let body = request(), title = request()
        body.regionOfInterest = CGRect(x:crop.left, y:1-crop.bottom, width:crop.right-crop.left, height:crop.bottom-crop.top)
        title.regionOfInterest = CGRect(x:titleCrop.left, y:1-titleCrop.bottom,
            width:titleCrop.right-titleCrop.left, height:titleCrop.bottom-titleCrop.top)
        try VNImageRequestHandler(cgImage:cg, options:[:]).perform([title, body])
        let titleText = (title.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        var lines: [OCRLine] = (body.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first, text.confidence >= 0.3 else { return nil }
            let r = observation.boundingBox
            return OCRLine(text:text.string, x:r.minX, y:1-r.maxY, width:r.width, height:r.height)
        }
        // If our PiP/keyboard enters the OCR region, exclude it and everything below its marker.
        if let cutoff = lines.filter({ $0.text.contains("CW") }).map(\.y).min() { lines.removeAll { $0.y >= cutoff - 0.01 } }
        return OCRSnapshot(title:titleText, messages:TextLogic.messages(from:lines))
    }
}
