//
//  ExtractedTextSheet.swift
//  IOScanner
//
//  Xem text thô đã OCR, copy hoặc chia sẻ dưới dạng file .txt.
//

import SwiftUI
import UIKit

struct ExtractedTextSheet: View {

    let title: String
    let text: String
    let isLoading: Bool
    let fileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Đang trích xuất text…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasText {
                    ScrollView {
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.badge.xmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Không nhận diện được chữ nào trong tài liệu này.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = text
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            didCopy = false
                        }
                    } label: {
                        Label(didCopy ? "Đã copy" : "Copy",
                              systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(!hasText)

                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        ShareLink(item: fileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}
