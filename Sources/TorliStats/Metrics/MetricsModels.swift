import Foundation

struct ProcessRow: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memory: Double
}

struct BatterySnapshot {
    let percentage: Double
    let health: Double?
    let cycleCount: Int?
    let adapterWatts: Int?
    let isCharging: Bool
    let powerSource: String
}

enum BluetoothDeviceKind {
    case headphones
    case keyboard
    case trackpad
    case mouse
    case gameController
    case generic

    var icon: String {
        switch self {
        case .headphones: return "headphones"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .mouse: return "computermouse"
        case .gameController: return "gamecontroller"
        case .generic: return "bluetooth"
        }
    }

    static func detect(name: String, majorType: String, minorType: String) -> Self {
        let description = "\(majorType) \(minorType) \(name)".lowercased()
        if description.contains("keyboard") || description.contains("键盘") { return .keyboard }
        if description.contains("trackpad") || description.contains("触控板") { return .trackpad }
        if description.contains("mouse") || description.contains("鼠标") { return .mouse }
        if description.contains("gamepad") || description.contains("controller") { return .gameController }
        if description.contains("headphone") || description.contains("headset") || description.contains("airpod") || description.contains("earbud") || description.contains("耳机") { return .headphones }
        return .generic
    }
}

struct BluetoothBatterySnapshot {
    let name: String
    let percentage: Double?
    let detail: String
    let kind: BluetoothDeviceKind
}
