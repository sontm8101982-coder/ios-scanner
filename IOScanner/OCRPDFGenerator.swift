//
//  OCRPDFGenerator.swift
//  IOScanner
//
//  Nhận diện chữ bằng Vision (on-device, Apple Neural Engine) và render
//  PDF "searchable": ảnh trang làm nền + lớp văn bản trong suốt (UIColor.clear)
//  đúng vị trí từng dòng, để có thể bôi đen / copy / tìm kiếm trong Files,
//  Apple Books, Preview...
//

import Foundation
import UIKit
import Vision
import CoreGraphics

// MARK: - Model

/// Một dòng chữ Vision nhận diện được trên một trang.
struct OCRTextLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
    /// Toạ độ CHUẨN HOÁ của Vision: gốc (0,0) ở GÓC DƯỚI BÊN TRÁI, trục Y hướng LÊN.
    let boundingBox: CGRect

    static func == (lhs: OCRTextLine, rhs: OCRTextLine) -> Bool {
        lhs.text == rhs.text && lhs.boundingBox == rhs.boundingBox
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(boundingBox.origin.x)
        hasher.combine(boundingBox.origin.y)
        hasher.combine(boundingBox.size.width)
        hasher.combine(boundingBox.size.height)
    }
}

/// Kết quả OCR của một trang.
struct OCRPageResult {
    let image: UIImage
    let lines: [OCRTextLine]

    /// Text thô, ghép theo thứ tự đọc (Vision đã sắp xếp từ trên xuống, trái sang phải).
    var plainText: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

/// Kết quả sau khi tạo PDF.
struct ScanResult {
    let pdfURL: URL
    let textURL: URL
    let plainText: String
    let pageCount: Int
}

enum OCRError: LocalizedError {
    case invalidImage
    case noPages
    case renderFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Không đọc được dữ liệu ảnh của trang đã quét."
        case .noPages:
            return "Không có trang nào để xử lý."
        case .renderFailed:
            return "Không tạo được file PDF từ các trang đã quét."
        case .writeFailed(let detail):
            return "Không ghi được file: \(detail)"
        }
    }
}

// MARK: - Generator

enum OCRPDFGenerator {

    /// Ngôn ngữ nhận diện: tiếng Việt trước, tiếng Anh dự phòng (iOS 16+ hỗ trợ vi-VN gốc).
    static let recognitionLanguages = ["vi-VN", "en-US"]

    /// Cạnh dài nhất của trang PDF (point). Ảnh 3000px thu về 2000pt để PDF nhẹ, dễ đọc.
    private static let maxPageDimension: CGFloat = 2000

    /// Tỉ lệ chiều cao chữ so với chiều cao boundingBox của Vision.
    private static let fontSizeRatio: CGFloat = 0.82

    // MARK: API công khai

    /// Nhận diện chữ trên một ảnh (chạy Vision .accurate trên Neural Engine).
    static func recognizeText(in image: UIImage, languages: [String] = recognitionLanguages) throws -> [OCRTextLine] {
        let normalized = normalize(image)
        guard let cgImage = normalized.cgImage else {
            throw OCRError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        var lines: [OCRTextLine] = []
        lines.reserveCapacity(observations.count)
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            lines.append(OCRTextLine(text: text, boundingBox: observation.boundingBox))
        }
        return lines
    }

    /// Quét toàn bộ các trang: OCR từng trang, trả về kết quả kèm ảnh đã chuẩn hoá.
    /// `progress` được gọi trên main queue.
    static func recognizePages(_ images: [UIImage],
                               progress: ((Int, Int) -> Void)? = nil) throws -> [OCRPageResult] {
        guard !images.isEmpty else { throw OCRError.noPages }

        var results: [OCRPageResult] = []
        results.reserveCapacity(images.count)

        for (index, image) in images.enumerated() {
            try autoreleasepool {
                let normalized = normalize(image)
                let lines = try recognizeText(in: normalized)
                results.append(OCRPageResult(image: normalized, lines: lines))
                if let progress = progress {
                    let done = index + 1
                    let total = images.count
                    DispatchQueue.main.async { progress(done, total) }
                }
            }
        }
        return results
    }

    /// Tạo PDF searchable một file từ danh sách trang.
    ///
    /// - Ảnh gốc được vẽ phủ kín trang.
    /// - Mỗi dòng chữ được vẽ lại với màu trong suốt, đúng vị trí, để lớp text
    ///   phủ khớp lên ảnh (bôi đen / copy / search được).
    ///
    /// Chuyển hệ toạ độ: Vision gốc dưới-trái, Y hướng lên →
    /// UIKit/CoreGraphics gốc trên-trái, Y hướng xuống:
    ///   x' = minX * pageWidth
    ///   y' = (1 - maxY) * pageHeight
    static func makeSearchablePDF(pages: [OCRPageResult],
                                  title: String,
                                  metadataTitle: String? = nil,
                                  outputURL: URL) throws -> URL {
        guard !pages.isEmpty else { throw OCRError.noPages }

        // Kích thước trang lấy theo trang đầu, các trang khác vẽ vừa khung (aspect fit).
        let firstSize = pageSize(for: pages[0].image)
        let bounds = CGRect(origin: .zero, size: firstSize)

        let format = UIGraphicsPDFRendererFormat()
        var info: [CFString: Any] = [
            kCGPDFContextTitle: (metadataTitle ?? title),
            kCGPDFContextCreator: "IOScanner (on-device Vision OCR)"
        ]
        info[kCGPDFContextAuthor] = "IOScanner"
        format.documentInfo = info as [CFString: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        let data = renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                let pageRect = bounds
                let targetSize = pageSize(for: page.image)

                // 1) Vẽ ảnh nền, canh giữa trang, giữ tỉ lệ.
                let imageRect = aspectFitRect(contentSize: targetSize, in: pageRect)
                page.image.draw(in: imageRect)

                // 2) Vẽ lớp text trong suốt đè khớp lên ảnh.
                drawInvisibleText(lines: page.lines, imageRect: imageRect, in: context.cgContext)
            }
        }

        guard !data.isEmpty else { throw OCRError.renderFailed }

        do {
            try ensureParentDirectory(of: outputURL)
            try data.write(to: outputURL, options: .atomic)
        } catch {
            throw OCRError.writeFailed(error.localizedDescription)
        }
        return outputURL
    }

    /// Pipeline đầy đủ: ảnh quét → OCR → PDF searchable + file .txt sidecar.
    /// Gọi hàm này trên background queue (nó là synchronous, nặng CPU).
    static func process(images: [UIImage],
                        baseName: String,
                        inDirectory directory: URL,
                        progress: ((Int, Int) -> Void)? = nil) throws -> ScanResult {

        let pages = try recognizePages(images, progress: progress)
        let pdfURL = directory.appendingPathComponent(baseName).appendingPathExtension("pdf")
        let textURL = directory.appendingPathComponent(baseName).appendingPathExtension("txt")

        let plainText = pages.map(\.plainText).joined(separator: "\n\n----- Trang tiếp theo -----\n\n")

        _ = try makeSearchablePDF(pages: pages,
                                  title: baseName,
                                  metadataTitle: baseName,
                                  outputURL: pdfURL)

        do {
            try ensureParentDirectory(of: textURL)
            try plainText.write(to: textURL, atomically: true, encoding: .utf8)
        } catch {
            // File text chỉ là tiện ích — PDF đã xong thì vẫn coi là thành công.
            print("IOScanner: không ghi được text sidecar: \(error)")
        }

        return ScanResult(pdfURL: pdfURL, textURL: textURL, plainText: plainText, pageCount: pages.count)
    }

    // MARK: - Nội bộ

    private static func drawInvisibleText(lines: [OCRTextLine],
                                          imageRect: CGRect,
                                          in cgContext: CGContext) {
        // UIGraphicsPDFRenderer cung cấp graphics context theo hệ UIKit (gốc trên-trái),
        // nên có thể dùng NSString.draw / NSAttributedString.draw trực tiếp.
        UIGraphicsPushContext(cgContext)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.alignment = .left

        for line in lines {
            let box = line.boundingBox
            // Đổi hệ toạ độ Vision (gốc dưới-trái, Y hướng lên) → UIKit (gốc trên-trái, Y hướng xuống).
            let rect = CGRect(
                x: imageRect.origin.x + box.minX * imageRect.width,
                y: imageRect.origin.y + (1.0 - box.maxY) * imageRect.height,
                width: box.width * imageRect.width,
                height: box.height * imageRect.height
            )
            guard rect.width > 0.5, rect.height > 0.5 else { continue }

            let fontSize = fittedFontSize(for: line.text,
                                          boxSize: rect.size,
                                          initial: rect.height * fontSizeRatio)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: UIColor.clear,
                .paragraphStyle: paragraph
            ]

            // Nới rộng khung 4% mỗi bên để tránh wrap chữ làm sai thứ tự copy.
            let drawRect = rect.insetBy(dx: -rect.width * 0.04, dy: -rect.height * 0.10)
            NSAttributedString(string: line.text, attributes: attributes)
                .draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }

        UIGraphicsPopContext()
    }

    /// Thu nhỏ font cho tới khi chuỗi vừa 1 dòng trong boundingBox (tránh bị cắt mất chữ).
    private static func fittedFontSize(for text: String, boxSize: CGSize, initial: CGFloat) -> CGFloat {
        var size = max(initial, 1)
        let probe: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size)]
        var guardCount = 0
        while guardCount < 8 {
            let width = (text as NSString).size(withAttributes: probe).width
            if width <= boxSize.width * 1.08 || size <= 1 { break }
            size *= 0.88
            guardCount += 1
        }
        return size
    }

    private static func pageSize(for image: UIImage) -> CGSize {
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > maxPageDimension else { return pixelSize }
        let factor = maxPageDimension / longest
        return CGSize(width: (pixelSize.width * factor).rounded(),
                      height: (pixelSize.height * factor).rounded())
    }

    private static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return bounds }
        let widthRatio = bounds.width / contentSize.width
        let heightRatio = bounds.height / contentSize.height
        let scale = min(widthRatio, heightRatio)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2,
                      y: bounds.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    /// Đưa ảnh về orientation .up, scale 1 để toạ độ Vision ↔ CoreGraphics khớp tuyệt đối.
    static func normalize(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1 {
            return image
        }
        guard let cgImage = image.cgImage else { return image }

        let rotated: [UIImage.Orientation] = [.left, .leftMirrored, .right, .rightMirrored]
        let baseSize = CGSize(width: cgImage.width, height: cgImage.height)
        let targetSize = rotated.contains(image.imageOrientation)
            ? CGSize(width: baseSize.height, height: baseSize.width)
            : baseSize

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func ensureParentDirectory(of url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
