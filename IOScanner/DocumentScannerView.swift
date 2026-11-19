//
//  DocumentScannerView.swift
//  IOScanner
//
//  Bọc VNDocumentCameraViewController của VisionKit để quét tài liệu đa trang
//  (tự bắt góc giấy, làm phẳng, lọc màu) và trả về [UIImage].
//

import SwiftUI
import VisionKit
import UIKit

struct DocumentScannerView: UIViewControllerRepresentable {

    /// Gọi khi người dùng bấm "Save" — trả về toàn bộ trang đã quét.
    var onFinish: ([UIImage]) -> Void

    /// Gọi khi người dùng bấm "Cancel" hoặc camera lỗi.
    var onCancel: () -> Void

    /// VisionKit chỉ hỗ trợ quét trên thiết bị thật có camera.
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // Không cần cập nhật gì: VisionKit tự quản lý vòng đời camera.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {

        private let onFinish: ([UIImage]) -> Void
        private let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            pages.reserveCapacity(scan.pageCount)
            for index in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: index))
            }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
        }
    }
}
