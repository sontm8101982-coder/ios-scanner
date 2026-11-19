//
//  ContentView.swift
//  IOScanner
//
//  Màn hình chính: danh sách PDF đã quét (thumbnail, tên, ngày, dung lượng),
//  nút FAB mở camera quét, đổi tên / xoá / chia sẻ tài liệu.
//

import SwiftUI
import UIKit
import PDFKit

struct ContentView: View {

    @StateObject private var viewModel = DocumentManagerViewModel()

    @State private var showScanner = false
    @State private var showScannerUnsupported = false
    @State private var renameTarget: PDFDocumentItem?
    @State private var renameText = ""
    @State private var deleteTarget: PDFDocumentItem?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                listContent
                floatingScanButton
            }
            .navigationTitle("Tài liệu quét")
            .searchable(text: $viewModel.searchText, prompt: "Tìm theo tên file")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startScan()
                    } label: {
                        Image(systemName: "doc.viewfinder")
                    }
                }
            }
            .overlay { processingOverlay }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { images in
                    showScanner = false
                    viewModel.importScans(images)
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $viewModel.selectedDocument) { item in
                PDFViewerView(item: item, viewModel: viewModel)
            }
            .alert("Đổi tên tài liệu", isPresented: renameAlertBinding) {
                TextField("Tên mới", text: $renameText)
                Button("Huỷ", role: .cancel) { renameTarget = nil }
                Button("Lưu") {
                    if let target = renameTarget {
                        viewModel.rename(target, to: renameText)
                    }
                    renameTarget = nil
                }
            } message: {
                Text("Không cần gõ phần .pdf")
            }
            .alert("Không quét được trên thiết bị này", isPresented: $showScannerUnsupported) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("VisionKit cần camera thật. Hãy chạy app trên iPhone, không phải Simulator.")
            }
            .confirmationDialog("Xoá tài liệu này?",
                                isPresented: deleteDialogBinding,
                                titleVisibility: .visible) {
                Button("Xoá", role: .destructive) {
                    if let target = deleteTarget {
                        viewModel.delete(target)
                    }
                    deleteTarget = nil
                }
                Button("Huỷ", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(deleteTarget?.name ?? "")
            }
            .alert("Lỗi", isPresented: errorBinding) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var listContent: some View {
        if viewModel.filteredDocuments.isEmpty {
            emptyState
        } else {
            List {
                ForEach(viewModel.filteredDocuments) { item in
                    documentRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.selectedDocument = item }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTarget = item
                            } label: {
                                Label("Xoá", systemImage: "trash")
                            }

                            Button {
                                startRename(item)
                            } label: {
                                Label("Đổi tên", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                viewModel.selectedDocument = item
                            } label: {
                                Label("Mở", systemImage: "doc.text.magnifyingglass")
                            }

                            Button {
                                startRename(item)
                            } label: {
                                Label("Đổi tên", systemImage: "pencil")
                            }

                            ShareLink(item: item.url) {
                                Label("Chia sẻ PDF", systemImage: "square.and.arrow.up")
                            }

                            Button(role: .destructive) {
                                deleteTarget = item
                            } label: {
                                Label("Xoá", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .refreshable { viewModel.loadDocuments() }
        }
    }

    private func documentRow(_ item: PDFDocumentItem) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func thumbnail(for item: PDFDocumentItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image = item.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 52, height: 68)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            Text(viewModel.documents.isEmpty ? "Chưa có tài liệu nào" : "Không tìm thấy tài liệu")
                .font(.title3.weight(.semibold))

            Text(viewModel.documents.isEmpty
                 ? "Nhấn nút camera để quét tài liệu. Chữ sẽ được nhận diện ngay trên máy (offline) và file PDF có thể bôi đen, copy, tìm kiếm."
                 : "Thử từ khoá khác hoặc xoá ô tìm kiếm.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.documents.isEmpty {
                Button {
                    startScan()
                } label: {
                    Label("Quét tài liệu", systemImage: "camera.viewfinder")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - FAB

    private var floatingScanButton: some View {
        Button {
            startScan()
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 26)
        .accessibilityLabel("Quét tài liệu mới")
    }

    // MARK: - Overlay xử lý

    @ViewBuilder
    private var processingOverlay: some View {
        if viewModel.isProcessing {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text(viewModel.progressText)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .transition(.opacity)
        }
    }

    // MARK: - Hành động

    private func startScan() {
        guard DocumentScannerView.isSupported else {
            showScannerUnsupported = true
            return
        }
        showScanner = true
    }

    private func startRename(_ item: PDFDocumentItem) {
        renameText = item.name
        renameTarget = item
    }

    // MARK: - Binding phụ

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })
    }
}

#Preview {
    ContentView()
}
