import AppKit

enum StatusBarRunner: String, CaseIterable, Identifiable {
    case runCat
    case beagle
    case chicken
    case dinosaur
    case fishman
    case frog
    case horse
    case rabbit
    case rubberDuck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runCat: return "跑步猫"
        case .beagle: return "小猎犬"
        case .chicken: return "小鸡"
        case .dinosaur: return "恐龙"
        case .fishman: return "鱼人"
        case .frog: return "青蛙"
        case .horse: return "马"
        case .rabbit: return "兔"
        case .rubberDuck: return "橡皮鸭"
        }
    }

    fileprivate var resourceName: String {
        switch self {
        case .runCat: return "runner-runcat"
        case .beagle: return "runner-beagle"
        case .chicken: return "runner-chicken"
        case .dinosaur: return "runner-dinosaur"
        case .fishman: return "runner-fishman"
        case .frog: return "runner-frog"
        case .horse: return "runner-horse"
        case .rabbit: return "runner-rabbit"
        case .rubberDuck: return "runner-rubberduck"
        }
    }

    fileprivate var frameCount: Int {
        switch self {
        case .runCat: return 5
        case .beagle: return 9
        case .chicken: return 5
        case .dinosaur: return 7
        case .fishman: return 5
        case .frog: return 5
        case .horse: return 6
        case .rabbit: return 5
        case .rubberDuck: return 6
        }
    }
}

/// Renders bundled RunCatNeo and RunnerGallery sprite sheets as macOS template images.
/// Artwork: Copyright 2026 Kyome22 (Takuto Nakamura), Apache-2.0.
final class StatusBarLogoAnimator {
    private static let artworkHeight: CGFloat = 20
    private static let titleGap: CGFloat = 2.5

    private weak var button: NSStatusBarButton?
    private let frames: [NSImage]
    private let isAnimated: Bool
    private var frameIndex = 0
    private var timer: Timer?
    private var frameInterval: TimeInterval?

    init(button: NSStatusBarButton, runner: StatusBarRunner, animated: Bool, cpuUsage: Double) {
        self.button = button
        frames = Self.makeFrames(for: runner)
        isAnimated = animated

        button.image = frames.first
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        setCPUUsage(cpuUsage)
    }

    deinit {
        timer?.invalidate()
    }

    /// Mirrors RunCatNeo's runner behavior: its baseline animation is 2 fps,
    /// then CPU usage scales the playback rate from 1x through 20x.
    func setCPUUsage(_ cpuUsage: Double) {
        guard isAnimated, frames.count > 1 else { return }
        let speed = max(1, min(20, cpuUsage / 5))
        let interval = 0.5 / speed
        guard frameInterval == nil || abs((frameInterval ?? interval) - interval) > 0.002 else { return }
        frameInterval = interval
        timer?.invalidate()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        button?.image = frames[frameIndex]
    }

    private static func makeFrames(for runner: StatusBarRunner) -> [NSImage] {
        guard let url = Bundle.main.url(forResource: runner.resourceName, withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let data = source.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let cgImage = bitmap.cgImage,
              cgImage.width.isMultiple(of: runner.frameCount) else {
            return []
        }

        let frameWidth = cgImage.width / runner.frameCount
        let aspectRatio = CGFloat(frameWidth) / CGFloat(cgImage.height)
        let artworkWidth = artworkHeight * aspectRatio
        let imageSize = NSSize(width: artworkWidth + titleGap, height: artworkHeight)

        return (0..<runner.frameCount).compactMap { index in
            let sourceRect = CGRect(
                x: index * frameWidth,
                y: 0,
                width: frameWidth,
                height: cgImage.height
            )
            guard let cropped = cgImage.cropping(to: sourceRect) else { return nil }

            let frame = NSImage(size: imageSize)
            frame.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: cropped, size: NSSize(width: artworkWidth, height: artworkHeight))
                .draw(in: NSRect(x: 0, y: 0, width: artworkWidth, height: artworkHeight))
            frame.unlockFocus()
            frame.isTemplate = true
            return frame
        }
    }
}
