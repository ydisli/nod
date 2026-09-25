import AppKit
import CoreGraphics
import NodCore

/// Display geometry in Quartz global coordinates (origin top left of the main
/// display, y down), which is what mouse events use.
@MainActor
enum Displays {
    struct Info: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
        let bounds: CGRect
        let isMain: Bool
    }

    static func all() -> [Info] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let names = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { s -> (CGDirectDisplayID, String)? in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (CGDirectDisplayID(n.uint32Value), s.localizedName)
        })
        return ids.map { id in
            Info(id: id, name: names[id] ?? "Display \(id)", bounds: CGDisplayBounds(id), isMain: CGDisplayIsMain(id) != 0)
        }
    }

    /// The display used for calibration and direct mapping.
    static func mappingDisplay(preferred: UInt32?) -> Info? {
        let list = all()
        if let p = preferred, let d = list.first(where: { $0.id == p }) { return d }
        return list.first(where: \.isMain) ?? list.first
    }

    static func environment(preferred: UInt32?, paletteFrame: CGRect?) -> EngineEnvironment {
        let list = all()
        guard let mapping = mappingDisplay(preferred: preferred) else { return .placeholder }
        return EngineEnvironment(
            displays: list.map { rect($0.bounds) },
            mappingDisplay: rect(mapping.bounds),
            paletteFrame: paletteFrame.map(rect)
        )
    }

    nonisolated static func rect(_ r: CGRect) -> Rect2 {
        Rect2(x: Double(r.minX), y: Double(r.minY), width: Double(r.width), height: Double(r.height))
    }

    /// Converts an AppKit window frame (origin bottom left of the primary
    /// screen, y up) into Quartz global coordinates.
    static func quartzRect(fromCocoa r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Converts a Quartz global point into AppKit screen coordinates.
    static func cocoaPoint(fromQuartz p: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}
