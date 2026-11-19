# IOScanner — quét tài liệu + OCR offline trên iPhone

Ứng dụng iOS (SwiftUI) quét tài liệu đa trang và tạo **PDF searchable** (bôi đen / copy /
tìm kiếm được), chạy **100% on-device**: VisionKit + Vision + PDFKit, không API đám mây,
không SDK bên thứ ba.

## Kiến trúc (MVVM)

```
ios-scanner/
├── project.yml                     # XcodeGen → sinh IOScanner.xcodeproj
├── .github/workflows/build.yml     # CI macOS build IPA unsigned
└── IOScanner/
    ├── IOScannerApp.swift          # @main
    ├── ContentView.swift           # Màn hình chính: danh sách PDF + FAB quét
    ├── DocumentScannerView.swift   # UIViewControllerRepresentable bọc VNDocumentCameraViewController
    ├── OCRPDFGenerator.swift       # Vision OCR + render PDF searchable (chuẩn toạ độ)
    ├── PDFDocumentItem.swift       # Model 1 tài liệu
    ├── DocumentManagerViewModel.swift  # Lưu trữ Documents: tạo/đổi tên/xoá/thumbnail/text
    ├── PDFViewerView.swift         # PDFView + tìm kiếm + chia sẻ
    ├── ExtractedTextSheet.swift    # Xem text thô đã OCR
    └── Assets.xcassets             # AppIcon + AccentColor
```

## Điểm kỹ thuật quan trọng

**Chuyển hệ toạ độ Vision → CoreGraphics/UIKit** (phần dễ sai nhất):

| | Vision | UIKit/CoreGraphics |
|---|---|---|
| Gốc toạ độ | góc dưới – trái | góc trên – trái |
| Trục Y | hướng lên | hướng xuống |
| Đơn vị | chuẩn hoá 0…1 | point |

```
x' = minX * pageWidth
y' = (1 - maxY) * pageHeight        // lật trục Y
w' = width  * pageWidth
h' = height * pageHeight
fontSize ≈ h' * 0.82                // tỉ lệ với chiều cao boundingBox
```

Mỗi dòng chữ được vẽ lại bằng `UIColor.clear` (trong suốt nhưng **vẫn là text thật** trong
file PDF), nới khung 4% mỗi bên để tránh wrap làm sai thứ tự khi copy.

## Build (máy Linux, không có Xcode)

```bash
git push            # CI macOS runner: xcodegen + xcodebuild → artifact IOScanner-unsigned.ipa
```

Tải artifact (thay `<ID>`):

```bash
curl -sL -H "Authorization: token $(cat ~/gh_token.txt)" \
  "https://api.github.com/repos/sontm810/ios-scanner/actions/artifacts/<ID>/zip" -o ipa.zip
unzip -o ipa.zip
```

## Sideload lên iPhone

```bash
/home/miso/Sideloader/bin/sideloader install IOScanner-unsigned.ipa -i --udid <UDID>
```

- Apple ID free → app hết hạn sau 7 ngày (ký lại).
- **Phải chạy trên iPhone thật**: `VNDocumentCameraViewController` không hoạt động trên Simulator.
- Lần đầu mở: cấp quyền Camera.

## Quyền trong Info.plist

- `NSCameraUsageDescription` — bắt buộc để mở camera quét.
- `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` — để thấy/chép PDF trong app Files.

## Giới hạn đã biết

- iOS 16.0+ (cần cho OCR tiếng Việt gốc của Vision).
- OCR tiếng Việt chất lượng phụ thuộc ảnh: chụp đủ sáng, thẳng góc, độ phân giải cao.
- PDF page được thu về tối đa 2000pt cạnh dài để file nhẹ; chữ vẫn vector-search tốt.
