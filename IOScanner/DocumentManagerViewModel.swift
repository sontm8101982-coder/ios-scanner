//
//  DocumentManagerViewModel.swift
//  IOScanner
//
//  Quản lý lưu trữ cục bộ: liệt kê PDF trong Documents, tạo PDF từ trang quét,
//  đổi tên, xoá, nạp thumbnail & text đã OCR.
//

import Foundation
import UIKit
import PDFKit
import Combine

final class DocumentManagerViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var documents: [PDFDocumentItem] = []
    @Published var isScanning: Bool = false
    @Published var isProcessing: Bool = false
    @Published var progressText: String = ""
    @Published var errorMessage: String?
    @Published var searchText: String = ""

    /// Tài liệu đang mở để xem PDF.
    @Published var selectedDocument: PDFDocumentItem?

    // MARK: - Thuộc tính

    /// Thư mục Documents của app (UIFileSharingEnabled → thấy được trong app Files).
    let documentsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    private let thumbnailCache = NSCache<NSURL, UIImage>()

    var filteredDocuments: [PDFDocumentItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return documents }
        return documents.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    init() {
        thumbnailCache.countLimit = 120
        loadDocuments()
    }

    // MARK: - Nạp danh sách

    func loadDocuments() {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey]

        let urls = (try? fileManager.contentsOfDirectory(at: documentsDirectory,
                                                        includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles])) ?? []

        let items: [PDFDocumentItem] = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "pdf" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let pdf = PDFDocument(url: url)
            let createdAt = values?.creationDate ?? values?.contentModificationDate ?? Date()
            let size = Int64(values?.fileSize ?? 0)
            return PDFDocumentItem(id: UUID(),
                                   url: url,
                                   name: url.deletingPathExtension().lastPathComponent,
                                   createdAt: createdAt,
                                   fileSize: size,
                                   pageCount: pdf?.pageCount ?? 0,
                                   thumbnail: thumbnailCache.object(forKey: url as NSURL),
                                   extractedText: nil)
        }
        .sorted { $0.createdAt > $1.createdAt }

        documents = items
        loadThumbnails(for: items)
    }

    private func loadThumbnails(for items: [PDFDocumentItem]) {
        for item in items where item.thumbnail == nil {
            loadThumbnail(for: item.url)
        }
    }

    private func loadThumbnail(for url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if let cached = self.thumbnailCache.object(forKey: url as NSURL) {
                DispatchQueue.main.async { self.applyThumbnail(cached, for: url) }
                return
            }
            guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { return }
            let size = CGSize(width: 240, height: 320)
            let image = page.thumbnail(of: size, for: .cropBox)
            self.thumbnailCache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async { self.applyThumbnail(image, for: url) }
        }
    }

    private func applyThumbnail(_ image: UIImage, for url: URL) {
        guard let index = documents.firstIndex(where: { $0.url == url }) else { return }
        documents[index].thumbnail = image
    }

    // MARK: - Tạo tài liệu từ ảnh quét

    /// Nhận ảnh từ VisionKit, OCR + render PDF searchable, lưu vào Documents.
    func importScans(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        isProcessing = true
        progressText = "Đang nhận diện chữ (0/\(images.count))…"

        let baseName = Self.makeBaseName()
        let directory = documentsDirectory

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try OCRPDFGenerator.process(images: images,
                                                         baseName: baseName,
                                                         inDirectory: directory) { done, total in
                    DispatchQueue.main.async { [weak self] in
                        self?.progressText = "Đang nhận diện chữ (\(done)/\(total))…"
                    }
                }

                DispatchQueue.main.async {
                    self.progressText = "Đã lưu \(result.pageCount) trang"
                    self.isProcessing = false
                    self.loadDocuments()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Text thô

    /// Đọc text đã OCR. Nếu file .txt chưa có (PDF cũ) thì trích lại từ lớp text của PDF.
    func loadExtractedText(for item: PDFDocumentItem, completion: @escaping (String) -> Void) {
        if let cached = documents.first(where: { $0.url == item.url })?.extractedText, !cached.isEmpty {
            completion(cached)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var text = ""
            if let sidecar = try? String(contentsOf: item.textURL, encoding: .utf8), !sidecar.isEmpty {
                text = sidecar
            } else if let pdf = PDFDocument(url: item.url) {
                var pages: [String] = []
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index), let content = page.string {
                        pages.append(content)
                    }
                }
                text = pages.joined(separator: "\n\n")
                try? text.write(to: item.textURL, atomically: true, encoding: .utf8)
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                if let index = self.documents.firstIndex(where: { $0.url == item.url }) {
                    self.documents[index].extractedText = text
                }
                completion(text)
            }
        }
    }

    // MARK: - Thao tác file

    func rename(_ item: PDFDocumentItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sanitized = Self.sanitize(trimmed)
        let fileManager = FileManager.default
        let newPDF = documentsDirectory.appendingPathComponent(sanitized).appendingPathExtension("pdf")
        let oldText = item.textURL
        let newText = documentsDirectory.appendingPathComponent(sanitized).appendingPathExtension("txt")

        guard !fileManager.fileExists(atPath: newPDF.path) else {
            errorMessage = "Đã có file tên \"\(sanitized)\". Hãy chọn tên khác."
            return
        }

        do {
            try fileManager.moveItem(at: item.url, to: newPDF)
            if fileManager.fileExists(atPath: oldText.path) {
                try? fileManager.moveItem(at: oldText, to: newText)
            }
            thumbnailCache.removeObject(forKey: item.url as NSURL)
            loadDocuments()
        } catch {
            errorMessage = "Không đổi tên được: \(error.localizedDescription)"
        }
    }

    func delete(_ item: PDFDocumentItem) {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: item.url)
            if fileManager.fileExists(atPath: item.textURL.path) {
                try? fileManager.removeItem(at: item.textURL)
            }
            thumbnailCache.removeObject(forKey: item.url as NSURL)
            documents.removeAll { $0.url == item.url }
        } catch {
            errorMessage = "Không xoá được: \(error.localizedDescription)"
        }
    }

    func delete(at offsets: IndexSet) {
        let items = filteredDocuments
        for index in offsets {
            guard items.indices.contains(index) else { continue }
            delete(items[index])
        }
    }

    // MARK: - Helper

    private static func makeBaseName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Scan_" + formatter.string(from: Date())
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? makeBaseName() : cleaned
    }
}
