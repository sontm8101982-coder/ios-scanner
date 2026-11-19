//
//  PDFDocumentItem.swift
//  IOScanner
//
//  Model một tài liệu PDF đã lưu trong thư mục Documents của app.
//

import Foundation
import UIKit

struct PDFDocumentItem: Identifiable, Hashable {

    let id: UUID
    /// Đường dẫn file PDF (nguồn sự thật duy nhất — mọi thứ khác đọc từ đây).
    let url: URL
    var name: String
    var createdAt: Date
    var fileSize: Int64
    var pageCount: Int
    var thumbnail: UIImage?
    /// Text thô đã OCR (nạp lười từ file .txt sidecar).
    var extractedText: String?

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var createdAtText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm, dd/MM/yyyy"
        return formatter.string(from: createdAt)
    }

    var subtitle: String {
        "\(pageCount) trang • \(fileSizeText) • \(createdAtText)"
    }

    /// File .txt chứa text thô (cùng tên với PDF, để cạnh nhau trong Documents).
    var textURL: URL {
        url.deletingPathExtension().appendingPathExtension("txt")
    }

    static func == (lhs: PDFDocumentItem, rhs: PDFDocumentItem) -> Bool {
        lhs.url == rhs.url && lhs.name == rhs.name && lhs.fileSize == rhs.fileSize
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(name)
        hasher.combine(fileSize)
    }
}
