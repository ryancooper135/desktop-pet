// Снимки виджетов и острова без телефона: ImageRenderer рисует вью из app/Shared/Views в PNG.
// Список вью — SnapshotCatalog.swift. PNG кладутся в $SNAPSHOT_DIR (в CI его передаёт
// TEST_RUNNER_SNAPSHOT_DIR) или в NSTemporaryDirectory()/snapshots, плюс вложением в xcresult.

import SwiftUI
import UIKit
import XCTest
@testable import Pet

final class WidgetSnapshotTests: XCTestCase {
    static func outputDir() throws -> URL {
        let env = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? ""
        let dir = env.isEmpty
            ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapshots")
            : URL(fileURLWithPath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    func testRenderCatalog() throws {
        let cases = SnapshotCatalog.all()
        XCTAssertFalse(cases.isEmpty, "SnapshotCatalog.all() пуст")
        let dir = try Self.outputDir()
        var failed: [String] = []
        var blank: [String] = []

        for c in cases {
            guard let image = Self.render(c) else {
                failed.append(c.name)
                continue
            }
            if Self.isUniform(image) { blank.append(c.name) }
            guard let png = image.pngData() else {
                failed.append(c.name)
                continue
            }
            try png.write(to: dir.appendingPathComponent(c.name + ".png"))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = c.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        print("Снимков: \(cases.count - failed.count) → \(dir.path)")
        XCTAssertTrue(failed.isEmpty, "Не отрисовались: \(failed.joined(separator: ", "))")
        // Пустой снимок — обычно вью, которую ImageRenderer не умеет (RealityView, UIViewRepresentable).
        XCTAssertTrue(blank.isEmpty, "Пустые снимки: \(blank.joined(separator: ", "))")
    }

    /// Иконка приложения 1024×1024 из той же мордочки, что в виджете: CI кладёт app-icon.png
    /// рядом со снимками, файл переносится в Resources/Assets.xcassets/AppIcon.appiconset.
    @MainActor
    func testRenderAppIcon() throws {
        let side: CGFloat = 1024
        let content = ZStack {
            LinearGradient(colors: [Color(hex: 0xfff4e6), Color(hex: 0xf6d9b8)],
                           startPoint: .top, endPoint: .bottom)
            PetFaceView(pose: .happy)
                .frame(width: side * 0.74, height: side * 0.74)
                .offset(y: side * 0.035)
        }
        .frame(width: side, height: side)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: side, height: side)
        let image = try XCTUnwrap(renderer.uiImage, "иконка не отрисовалась")
        XCTAssertFalse(Self.isUniform(image))
        let png = try XCTUnwrap(image.pngData())
        try png.write(to: Self.outputDir().appendingPathComponent("app-icon.png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "app-icon"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    static func render(_ c: SnapshotCase) -> UIImage? {
        let content = c.view
            .frame(width: c.size.width, height: c.size.height)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: c.cornerRadius, style: .continuous))
            .environment(\.colorScheme, c.colorScheme)
            .environment(\.locale, Locale(identifier: "ru_RU"))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(c.size)
        return renderer.uiImage
    }

    /// Всё одного цвета: картинка ужимается до 48×48 с усреднением, так что и мелкий текст
    /// сдвигает цвет хотя бы одной клетки.
    static func isUniform(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return true }
        let w = 48, h = 48
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return false }
        // Края — это скругление рамки, смотрим центральную часть.
        var first: [UInt8]?
        for y in 6..<(h - 6) {
            for x in 6..<(w - 6) {
                let i = (y * w + x) * 4
                let px = Array(pixels[i..<(i + 4)])
                if let f = first {
                    if zip(f, px).contains(where: { abs(Int($0) - Int($1)) > 2 }) { return false }
                } else {
                    first = px
                }
            }
        }
        return true
    }
}
