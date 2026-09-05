import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Shortcut recorder

/// Captures a key combination. It has to intercept `performKeyEquivalent` as well
/// as `keyDown`, or combinations that match a menu item (⌘N and friends) are
/// swallowed by the menu before the field ever sees them.
final class RecorderView: NSView {
    var onCapture: ((Shortcut) -> Void)?
    /// In-note shortcuts are matched by the note itself, so a bare key is safe.
    /// A global one without a modifier would swallow that key system-wide.
    var allowsBareKeys = false
    var shortcut: Shortcut = .none { didSet { needsDisplay = true } }
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { stop(); return }
        if event.keyCode == UInt16(kVK_Delete) {
            shortcut = .none; onCapture?(.none); stop(); return
        }
        guard let s = Shortcut.from(event: event, allowingBareKey: allowsBareKeys) else {
            NSSound.beep()
            return
        }
        shortcut = s
        onCapture?(s)
        stop()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private func stop() {
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                   : NSColor.textBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor
                   : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? NotyL10n.text("shortcut.press_keys") : shortcut.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: r.midX - size.width / 2,
                                            y: r.midY - size.height / 2), withAttributes: attrs)
    }
}

struct ShortcutField: NSViewRepresentable {
    let shortcut: Shortcut
    var allowsBareKeys = false
    let onChange: (Shortcut) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.shortcut = shortcut
        v.allowsBareKeys = allowsBareKeys
        v.onCapture = onChange
        return v
    }
    func updateNSView(_ v: RecorderView, context: Context) {
        v.shortcut = shortcut
        v.allowsBareKeys = allowsBareKeys
        v.onCapture = onChange
    }
}

// MARK: - Model

enum DeckCorner: String, CaseIterable, Identifiable {
    case topLeft
    case bottomLeft
    case topRight
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "左上"
        case .bottomLeft: return "左下"
        case .topRight: return "右上"
        case .bottomRight: return "右下"
        }
    }

    init(onLeftEdge: Bool, yRatio: CGFloat) {
        switch (onLeftEdge, yRatio >= 0.5) {
        case (true, true): self = .topLeft
        case (true, false): self = .bottomLeft
        case (false, true): self = .topRight
        case (false, false): self = .bottomRight
        }
    }

    var onLeftEdge: Bool { self == .topLeft || self == .bottomLeft }
    var yRatio: CGFloat { self == .topLeft || self == .topRight ? 1 : 0 }
}

final class SettingsModel: ObservableObject {
    @Published var appLanguage: AppLanguage {
        didSet {
            guard !loading, !syncing, appLanguage != oldValue else { return }
            NotySettings.appLanguage = appLanguage
            NotesAppBridge.shared.delegate?.relaunchForLanguageChange(previous: oldValue)
        }
    }
    @Published var deckStyle: DeckStyle { didSet { NotySettings.deckStyle = deckStyle; apply() } }
    @Published var alwaysShown: Bool    { didSet { NotySettings.deckAlwaysShown = alwaysShown; apply() } }
    @Published var pillHidden: Bool     { didSet { NotySettings.deckPillHidden = pillHidden; apply() } }
    @Published var deckScale: Double    { didSet { NotySettings.deckScale = deckScale; apply() } }
    @Published var deckCorner: DeckCorner {
        didSet {
            NotySettings.deckOnLeftEdge = deckCorner.onLeftEdge
            NotySettings.deckYRatio = deckCorner.yRatio
            apply()
        }
    }
    @Published var displayTarget: String { didSet { NotySettings.displayTarget = displayTarget; apply() } }
    @Published var screens: [NSScreen] = NSScreen.screens
    @Published var edgeWidth: Double    { didSet { NotySettings.edgeWidth = edgeWidth; apply() } }
    @Published var overFullScreen: Bool { didSet { NotySettings.showOverFullScreen = overFullScreen; apply() } }

    @Published var fontName: String     { didSet { NotySettings.noteFontName = fontName; apply() } }
    @Published var fontSize: Double     { didSet { NotySettings.noteFontSize = fontSize; apply() } }
    @Published var markdown: Bool       { didSet { NotySettings.markdownStyling = markdown; apply() } }
    @Published var noteSizeIndex: Int   { didSet { NotySettings.noteSizeIndex = noteSizeIndex; apply() } }
    @Published var openOnHover: Bool    { didSet { NotySettings.openOnHover = openOnHover; apply() } }
    @Published var tabPreview: Bool     { didSet { NotySettings.tabPreview = tabPreview; apply() } }

    @Published var scNewNote: Shortcut  { didSet { NotySettings.scNewNote = scNewNote; HotKeys.shared.reload() } }
    @Published var scAllNotes: Shortcut { didSet { NotySettings.scAllNotes = scAllNotes; HotKeys.shared.reload() } }
    @Published var scArchive: Shortcut  { didSet { NotySettings.scArchive = scArchive; HotKeys.shared.reload() } }
    @Published var scCapture: Shortcut  { didSet { NotySettings.scCapture = scCapture; HotKeys.shared.reload() } }
    // Handled by the open note itself, so these need no hotkey registration.
    @Published var scArchiveNote: Shortcut { didSet { NotySettings.scArchiveNote = scArchiveNote } }
    @Published var scClose: Shortcut   { didSet { NotySettings.scClose = scClose } }
    @Published var scFind: Shortcut    { didSet { NotySettings.scFind = scFind } }
    @Published var scTask: Shortcut    { didSet { NotySettings.scTask = scTask } }
    @Published var scPin: Shortcut     { didSet { NotySettings.scPin = scPin } }
    @Published var scColour: Shortcut  { didSet { NotySettings.scColour = scColour } }
    @Published var scDelete: Shortcut  { didSet { NotySettings.scDelete = scDelete } }
    @Published var scBigger: Shortcut  { didSet { NotySettings.scBigger = scBigger } }
    @Published var scSmaller: Shortcut { didSet { NotySettings.scSmaller = scSmaller } }

    private var loading = true
    /// True while values are applied back from UserDefaults (e.g. after a
    /// failed relaunch) — those writes must not re-trigger another relaunch.
    private var syncing = false

    init() {
        appLanguage = NotySettings.appLanguage
        deckStyle = NotySettings.deckStyle
        alwaysShown = NotySettings.deckAlwaysShown
        pillHidden = NotySettings.deckPillHidden
        deckScale = NotySettings.deckScale
        deckCorner = DeckCorner(
            onLeftEdge: NotySettings.deckOnLeftEdge,
            yRatio: NotySettings.deckYRatio
        )
        displayTarget = NotySettings.displayTarget
        screens = NSScreen.screens
        edgeWidth = NotySettings.edgeWidth
        overFullScreen = NotySettings.showOverFullScreen
        fontName = NotySettings.noteFontName
        fontSize = NotySettings.noteFontSize
        markdown = NotySettings.markdownStyling
        noteSizeIndex = NotySettings.noteSizeIndex
        openOnHover = NotySettings.openOnHover
        tabPreview = NotySettings.tabPreview
        scNewNote = NotySettings.scNewNote
        scAllNotes = NotySettings.scAllNotes
        scArchive = NotySettings.scArchive
        scCapture = NotySettings.scCapture
        scArchiveNote = NotySettings.scArchiveNote
        scClose = NotySettings.scClose
        scFind = NotySettings.scFind
        scTask = NotySettings.scTask
        scPin = NotySettings.scPin
        scColour = NotySettings.scColour
        scDelete = NotySettings.scDelete
        scBigger = NotySettings.scBigger
        scSmaller = NotySettings.scSmaller
        loading = false

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.screens = NSScreen.screens
            }
    }

    /// Re-read a handful of values straight from UserDefaults without firing
    /// their didSet side-effects — used after a failed language-change relaunch
    /// to roll the picker back to what the running process actually speaks.
    func syncFromDefaults() {
        syncing = true
        appLanguage = NotySettings.appLanguage
        displayTarget = NotySettings.displayTarget
        tabPreview = NotySettings.tabPreview
        syncing = false
    }

    private func apply() {
        guard !loading else { return }
        NotesAppBridge.shared.delegate?.refreshDecks()
    }


    /// Warn about a combination already used by another Noty shortcut.
    func duplicate(of s: Shortcut, ignoring label: String) -> Bool {
        guard s.isSet else { return false }
        let others = [("new", scNewNote), ("all", scAllNotes), ("archive", scArchive),
                      ("capture", scCapture),
                      ("archiveNote", scArchiveNote), ("close", scClose), ("find", scFind),
                      ("task", scTask), ("pin", scPin), ("colour", scColour),
                      ("delete", scDelete), ("bigger", scBigger), ("smaller", scSmaller)]
            .filter { $0.0 != label }
        return others.contains { $0.1 == s }
    }
}

// MARK: - Window

final class NotySettingsWindow: NSObject, NSWindowDelegate {
    static let shared = NotySettingsWindow()
    private var window: NSWindow?
    private let model = SettingsModel()

    var isOpen: Bool { window?.isVisible ?? false }

    func syncPreferences() {
        model.syncFromDefaults()
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = NotyL10n.text("settings.window_title")
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: NotySettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            if LibraryWindow.shared.isOpen == false { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

// MARK: - View

struct NotySettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        // One long scroll made twelve shortcut fields, nine deck controls and the
        // note settings compete for the same eye. Tabs are what a NotySettings window
        // is supposed to be, and they leave somewhere obvious to put updates.
        TabView {
            pane(NotyL10n.text("settings.shortcuts.caption")) { shortcutsTab }
                .tabItem { Label(NotyL10n.text("settings.shortcuts.tab"), systemImage: "command") }
            pane(NotyL10n.text("settings.deck.caption")) { deckTab }
                .tabItem { Label(NotyL10n.text("settings.deck.tab"), systemImage: "menucard") }
            pane(NotyL10n.text("settings.notes.caption")) { notesTab }
                .tabItem { Label(NotyL10n.text("settings.notes.tab"), systemImage: "textformat") }
        }
        .padding(14)
        .frame(width: 600, height: 500)
    }

    @ViewBuilder
    private var shortcutsTab: some View {
        // Two columns: twelve stacked rows made the window scroll for
        // what is really a reference table.
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 7) {
                subhead(NotyL10n.text("settings.shortcuts.global"))
                shortcutRow(NotyL10n.text("shortcut.new_note"), model.scNewNote, "new") { model.scNewNote = $0 }
                shortcutRow(NotyL10n.text("shortcut.all_notes"), model.scAllNotes, "all") { model.scAllNotes = $0 }
                shortcutRow(NotyL10n.text("shortcut.archive_window"), model.scArchive, "archive") { model.scArchive = $0 }
                shortcutRow(NotyL10n.text("shortcut.quick_capture"), model.scCapture, "capture") { model.scCapture = $0 }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 7) {
                subhead(NotyL10n.text("settings.shortcuts.in_note"))
                shortcutRow(NotyL10n.text("action.close"), model.scClose, "close", bare: true) { model.scClose = $0 }
                shortcutRow(NotyL10n.text("shortcut.archive_note"), model.scArchiveNote, "archiveNote", bare: true) { model.scArchiveNote = $0 }
                shortcutRow(NotyL10n.text("action.delete"), model.scDelete, "delete", bare: true) { model.scDelete = $0 }
                shortcutRow(NotyL10n.text("action.find"), model.scFind, "find", bare: true) { model.scFind = $0 }
                shortcutRow(NotyL10n.text("shortcut.toggle_task"), model.scTask, "task", bare: true) { model.scTask = $0 }
                shortcutRow(NotyL10n.text("action.pin"), model.scPin, "pin", bare: true) { model.scPin = $0 }
                shortcutRow(NotyL10n.text("action.cycle_colour"), model.scColour, "colour", bare: true) { model.scColour = $0 }
                shortcutRow(NotyL10n.text("menu.bigger_text"), model.scBigger, "bigger", bare: true) { model.scBigger = $0 }
                shortcutRow(NotyL10n.text("menu.smaller_text"), model.scSmaller, "smaller", bare: true) { model.scSmaller = $0 }
            }
        }
        Text(NotyL10n.text("settings.shortcuts.hint"))
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    @ViewBuilder
    private var deckTab: some View {
        row(NotyL10n.text("settings.deck.language")) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $model.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.localizedName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Text(NotyL10n.text("settings.deck.language_help"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        Divider().padding(.vertical, 2)
        row(NotyL10n.text("settings.deck.style")) {
            Picker("", selection: $model.deckStyle) {
                ForEach(DeckStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
        }
        row(NotyL10n.text("settings.deck.size")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Slider(value: $model.deckScale,
                           in: NotySettings.deckScaleRange.lowerBound...NotySettings.deckScaleRange.upperBound,
                           step: 0.05).frame(width: 210)
                    Text("\(Int((model.deckScale * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                }
                Text(NotyL10n.text("settings.deck.size_help"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        if model.screens.count > 1 {
            row(NotyL10n.text("settings.deck.display")) {
                Picker("", selection: $model.displayTarget) {
                    Text(NotyL10n.text("display.all")).tag("all")
                    Text(NotyL10n.text("display.main")).tag("main")
                    ForEach(model.screens, id: \.self) { s in
                        if let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
                            let name = s.localizedName
                            let title = s == NSScreen.main ? NotyL10n.format("display.named_main", name) : name
                            Text(title).tag("id:\(id)")
                        }
                    }
                }.labelsHidden().frame(width: 220)
            }
        }
        row("固定位置") {
            Picker("", selection: $model.deckCorner) {
                ForEach(DeckCorner.allCases) { corner in
                    Text(corner.title).tag(corner)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
        row(NotyL10n.text("settings.deck.detection_area")) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $model.edgeWidth) {
                    ForEach(NotySettings.edgeWidths, id: \.width) { Text(NotyL10n.text($0.nameKey)).tag($0.width) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 300)
                Text(NotyL10n.format("settings.deck.detection_help", Int(model.edgeWidth)))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            Toggle(NotyL10n.text("settings.deck.keep_open"), isOn: $model.alwaysShown)
            Text(NotyL10n.text("settings.deck.keep_open_help"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(NotyL10n.text("settings.deck.hide_pill"), isOn: $model.pillHidden)
                        Text(NotyL10n.text("settings.deck.hide_pill_help"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
        // Pointless alongside hover-to-open — the note itself opens — so the
        // row disappears rather than sitting there doing nothing.
        if !model.openOnHover {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(NotyL10n.text("settings.deck.hover_preview"), isOn: $model.tabPreview)
                Text(NotyL10n.text("settings.deck.hover_preview_help"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            Toggle(NotyL10n.text("settings.deck.hover_open"), isOn: $model.openOnHover)
            Text(NotyL10n.text("settings.deck.hover_open_help"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Toggle(NotyL10n.text("menu.show_over_fullscreen"), isOn: $model.overFullScreen)
        Text(NotyL10n.text("settings.deck.drag_help"))
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    @ViewBuilder
    private var notesTab: some View {
        row(NotyL10n.text("settings.notes.font")) {
            Picker("", selection: $model.fontName) {
                ForEach(Ink.faces, id: \.body) { Text($0.localizedName).tag($0.body) }
            }.labelsHidden().frame(width: 200)
        }
        row(NotyL10n.text("settings.notes.note_size")) {
            Picker("", selection: $model.noteSizeIndex) {
                ForEach(Array(NotySettings.noteSizes.enumerated()), id: \.offset) { i, s in
                    Text(NotyL10n.text(s.nameKey)).tag(i)
                }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 300)
        }
        row(NotyL10n.text("settings.notes.text_size")) {
            HStack(spacing: 10) {
                Slider(value: $model.fontSize,
                       in: NotySettings.fontRange.lowerBound...NotySettings.fontRange.upperBound,
                       step: 0.5).frame(width: 210)
                Text(NotyL10n.format("settings.notes.font_size_value", model.fontSize))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            Toggle(NotyL10n.text("settings.notes.markdown"), isOn: $model.markdown)
            Text(NotyL10n.text("settings.notes.markdown_help"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
    }


    // MARK: pieces

    /// One tab. The heading is gone — the tab itself is the heading now — but the
    /// caption earns its line, so it stays.
    private func pane(_ caption: String,
                      @ViewBuilder _ content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text(caption).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 11) { content() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
    }

    private func subhead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func row(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).font(.system(size: 12.5))
                .frame(width: 104, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func shortcutRow(_ label: String, _ value: Shortcut, _ key: String,
                             bare: Bool = false,
                             _ set: @escaping (Shortcut) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).frame(width: 96, alignment: .leading)
            ShortcutField(shortcut: value, allowsBareKeys: bare, onChange: set)
                .frame(width: 96, height: 24)
            if model.duplicate(of: value, ignoring: key) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .help(NotyL10n.text("shortcut.duplicate"))
            }
            Spacer(minLength: 0)
        }
    }
}
