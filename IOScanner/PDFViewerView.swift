//
//  PDFViewerView.swift
//  IOScanner
//
//  Màn hình xem PDF: phóng to/thu nhỏ, bôi đen & copy text (nhờ lớp text trong suốt
//  đã nhúng trong file), tìm kiếm từ khoá, chia sẻ / xuất file, xem text thô.
//

import SwiftUI
import UIKit
import PDFKit

// MARK: - Controller giữ PDFView

final class PDFViewController: ObservableObject {

    let pdfView = PDFView()

    @Published private(set) var isLoaded = false
    @Published private(set) var matchCount = 0
    @Published private(set) var currentMatchIndex = 0
    @Published private(set) var loadError: String?

    private var matches: [PDFSelection] = []

    init() {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = true
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.displaysPageBreaks = true
        // Cho phép chọn/copy text trực tiếp trên trang.
        pdfView.isUserInteractionEnabled = true
    }

    func load(url: URL) {
        guard !isLoaded else { return }
        guard let document = PDFDocument(url: url) else {
            loadError = "Không mở được file PDF này."
            return
        }
        pdfView.document = document
        pdfView.autoScales = true
        isLoaded = true
    }

    /// Tìm kiếm, tô sáng toàn bộ kết quả và nhảy tới kết quả đầu tiên.
    @discardableResult
    func search(_ query: String) -> Int {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let document = pdfView.document, !keyword.isEmpty else {
            clearSearch()
            return 0
        }

        let selections = document.findString(keyword,
                                            withOptions: [.caseInsensitive, .diacriticInsensitive])
        matches = selections
        matchCount = selections.count
        currentMatchIndex = selections.isEmpty ? 0 : 1

        if let first = selections.first {
            pdfView.highlightedSelections = selections
            pdfView.go(to: first)
        } else {
            pdfView.highlightedSelections = nil
        }
        return selections.count
    }

    func clearSearch() {
        matches = []
        matchCount = 0
        currentMatchIndex = 0
        pdfView.highlightedSelections = nil
    }

    func goToNextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = currentMatchIndex % matches.count + 1
        pdfView.go(to: matches[currentMatchIndex - 1])
    }

    func goToPreviousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = currentMatchIndex - 1
        if currentMatchIndex < 1 { currentMatchIndex = matches.count }
        pdfView.go(to: matches[currentMatchIndex - 1])
    }
}

// MARK: - UIViewRepresentable

struct PDFKitView: UIViewRepresentable {

    @ObservedObject var controller: PDFViewController

    func makeUIView(context: Context) -> PDFView {
        return controller.pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // PDFView do controller sở hữu; việc nạp document do PDFViewerView.onAppear đảm nhận
        // (tránh mutate state trong lúc SwiftUI đang update view).
    }
}

// MARK: - Màn hình xem

struct PDFViewerView: View {

    let item: PDFDocumentItem
    let viewModel: DocumentManagerViewModel

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = PDFViewController()

    @State private var isSearching = false
    @State private var query = ""
    @State private var extractedText = ""
    @State private var isLoadingText = false
    @State private var showTextSheet = false
    @State private var currentItem: PDFDocumentItem

    init(item: PDFDocumentItem, viewModel: DocumentManagerViewModel) {
        self.item = item
        self.viewModel = viewModel
        _currentItem = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PDFKitView(controller: controller)
                    .ignoresSafeArea(edges: .bottom)
                    .onAppear { controller.load(url: currentItem.url) }

                if isSearching {
                    searchBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !controller.isLoaded, controller.loadError == nil {
                    ProgressView("Đang mở PDF…")
                }

                if let error = controller.loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text(error)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle(currentItem.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        withAnimation { isSearching.toggle() }
                        if !isSearching { controller.clearSearch() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }

                    Button {
                        openTextSheet()
                    } label: {
                        Image(systemName: "text.alignleft")
                    }

                    ShareLink(item: currentItem.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showTextSheet) {
                ExtractedTextSheet(title: currentItem.name,
                                   text: extractedText,
                                   isLoading: isLoadingText,
                                   fileURL: currentItem.textURL)
            }
        }
    }

    // MARK: Thanh tìm kiếm

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Tìm trong tài liệu…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .onChange(of: query) { newValue in
                    if newValue.isEmpty { controller.clearSearch() }
                }

            if controller.matchCount > 0 {
                Text("\(controller.currentMatchIndex)/\(controller.matchCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if !query.isEmpty {
                Text("0")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                controller.goToPreviousMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(controller.matchCount == 0)

            Button {
                controller.goToNextMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(controller.matchCount == 0)

            Button {
                query = ""
                controller.clearSearch()
                withAnimation { isSearching = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func runSearch() {
        controller.search(query)
    }

    private func openTextSheet() {
        showTextSheet = true
        extractedText = ""
        isLoadingText = true
        viewModel.loadExtractedText(for: currentItem) { text in
            extractedText = text
            isLoadingText = false
        }
    }
}
