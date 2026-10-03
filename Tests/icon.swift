// Draws the app icon ("Neon night") at every size macOS needs. Run: sh screenshots.sh
import AppKit
import SwiftUI

func rgb(_ hex: Int) -> Color { Color(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }

// 1024-point canvas, 824-point rounded tile: Apple's macOS icon grid.
let icon = ZStack {
    RoundedRectangle(cornerRadius: 184, style: .continuous)
        .fill(LinearGradient(colors: [rgb(0x141A33), rgb(0x05060D)], startPoint: .top, endPoint: .bottom))
    Image(systemName: "wifi").font(.system(size: 430, weight: .black)).offset(y: -8)
        .foregroundStyle(LinearGradient(colors: [rgb(0x00F0FF), rgb(0xFF2BD6)], startPoint: .topLeading, endPoint: .bottomTrailing))
    Text("8").font(.system(size: 184, weight: .black)).foregroundStyle(.white)
        .frame(width: 268, height: 268)
        .background(Circle().fill(LinearGradient(colors: [rgb(0xFF2BD6), rgb(0xB000FF)], startPoint: .top, endPoint: .bottom)))
        .overlay(Circle().stroke(rgb(0x05060D), lineWidth: 18)).offset(x: 252, y: -252)
}
.frame(width: 824, height: 824).shadow(color: .black.opacity(0.3), radius: 20, y: 12).frame(width: 1024, height: 1024)

@MainActor func png(_ pixels: Int, _ path: String) throws {
    let renderer = ImageRenderer(content: icon)
    renderer.scale = CGFloat(pixels) / 1024
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

MainActor.assumeIsolated {
    do {
        let set = "build/shots/AppIcon.iconset"
        try? FileManager.default.removeItem(atPath: set)
        try FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            try png(size, "\(set)/icon_\(size)x\(size).png")
            try png(size * 2, "\(set)/icon_\(size)x\(size)@2x.png")
        }
        try png(256, "docs/icon.png")
    } catch { fatalError("\(error)") }
}
