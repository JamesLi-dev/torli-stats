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
    case classicCat
    case goldenRetriever
    case wallBreaker
    case dojoPanda

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
        case .classicCat: return "经典猫"
        case .goldenRetriever: return "金毛寻回犬"
        case .wallBreaker: return "破墙者"
        case .dojoPanda: return "道场熊猫"
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
        case .classicCat: return "runner-classic-cat"
        case .goldenRetriever: return "runner-golden-retriever"
        case .wallBreaker: return "runner-wall-breaker"
        case .dojoPanda: return "runner-dojo-panda"
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
        case .classicCat: return 5
        case .goldenRetriever: return 8
        case .wallBreaker: return 16
        case .dojoPanda: return 12
        }
    }

    fileprivate var usesTemplateRendering: Bool {
        switch self {
        case .wallBreaker, .dojoPanda: return false
        default: return true
        }
    }
}

/// Renders bundled RunCatNeo and RunnerGallery sprite sheets. Monochrome
/// runners use menu-bar template rendering; color runners retain their artwork.
/// See THIRD_PARTY_NOTICES.md for Apache-2.0 attribution.
final class StatusBarLogoAnimator {
    private static let artworkHeight: CGFloat = 20

    private let onFrameChange: (NSImage?) -> Void
    private let frames: [NSImage]
    private let isAnimated: Bool
    private var frameIndex = 0
    private var timer: Timer?
    private var frameInterval: TimeInterval?
    private var awaitingFirstCPUSample = true

    init(
        runner: StatusBarRunner,
        animated: Bool,
        cpuUsage: Double,
        onFrameChange: @escaping (NSImage?) -> Void
    ) {
        self.onFrameChange = onFrameChange
        frames = Self.makeFrames(for: runner)
        isAnimated = animated

        renderCurrentFrame()
        setCPUUsage(cpuUsage)
    }

    deinit {
        timer?.invalidate()
    }

    /// Mirrors RunCatNeo's runner behavior: its baseline animation is 2 fps,
    /// then CPU usage scales the playback rate from 1x through 20x. The first
    /// CPU sample is commonly zero while the sampler establishes its baseline;
    /// keep a responsive startup rate instead of showing a static-looking logo.
    func setCPUUsage(_ cpuUsage: Double) {
        guard isAnimated, frames.count > 1 else { return }
        let speed: Double
        if awaitingFirstCPUSample, cpuUsage <= 0 {
            speed = 6
        } else {
            awaitingFirstCPUSample = false
            speed = max(1, min(20, cpuUsage / 5))
        }
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
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        onFrameChange(frames.indices.contains(frameIndex) ? frames[frameIndex] : nil)
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
        // The status bar compositor supplies the same inter-item spacing for
        // runners and metric groups, so runner frames should not include an
        // additional transparent trailing gap of their own.
        let imageSize = NSSize(width: artworkWidth, height: artworkHeight)

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
            frame.isTemplate = runner.usesTemplateRendering
            return frame
        }
    }
}
