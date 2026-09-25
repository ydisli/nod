@preconcurrency import AVFoundation
import AppKit
import NodCore
import SwiftUI

/// The calibration state machine. Hands-free by design: every step advances
/// on its own once the face is steady, keys are only a convenience.
@MainActor @Observable
final class CalibrationSession {
    enum Kind: Equatable {
        case movement(TrackingInput)
        case gestures
    }

    enum Phase: Equatable {
        case framing, neutral, targets, gestures, result
        case failed(String)
    }

    enum GestureStage { case ready, perform, relax }

    struct Checks: Equatable {
        var face = false, light = false, centred = false, distance = false
        var allGood: Bool { face && light && centred && distance }
    }

    let kind: Kind
    let displaySize: CGSize
    let displayID: UInt32
    let targets: [Vec2]
    let gestureList: [FaceGesture]

    private(set) var phase: Phase = .framing
    private(set) var progress: Double = 0
    private(set) var targetIndex = 0
    private(set) var settling = true
    private(set) var gestureIndex = 0
    private(set) var gestureStage: GestureStage = .ready
    private(set) var latest: FaceSample?
    private(set) var checks = Checks()
    private(set) var liveGestureLevel: Double = 0
    private(set) var result: CalibrationProfile?
    private(set) var resultBaseline: GestureBaseline?
    private(set) var countdown: Double = 0
    private(set) var faceMissing = false

    @ObservationIgnored var onFinish: ((CalibrationProfile?, GestureBaseline?) -> Void)?

    private let existingBaseline: GestureBaseline?
    private let settleTime: Double
    private let sampleTime: Double
    private var stepStart = 0.0
    private var goodSince: Double?
    private var lastFace = 0.0
    private var neutralMetrics: [FaceMetrics] = []
    private var neutralNoses: [Vec2] = []
    private var neutralScales: [Double] = []
    private var points: [CalibrationPoint] = []
    private var targetNoses: [[Vec2]] = []
    private var targetSamples = 0
    private var gestureValues: [Double] = []
    private var peaks: [FaceGesture: Double] = [:]
    private var log: [CalibrationLog.Entry] = []

    var input: TrackingInput? {
        if case let .movement(i) = kind { return i }
        return nil
    }

    init(kind: Kind, displaySize: CGSize, displayID: UInt32, existingBaseline: GestureBaseline?, gestures: [FaceGesture]) {
        self.kind = kind
        self.displaySize = displaySize
        self.displayID = displayID
        self.existingBaseline = existingBaseline
        self.targets = CalibrationLayout.targets()
        self.gestureList = gestures
        let eyes = kind == .movement(.eyes)
        // Long enough to finish turning towards a corner before recording.
        settleTime = eyes ? 1.2 : 1.1
        sampleTime = eyes ? 1.3 : 1.0
        targetNoses = Array(repeating: [], count: targets.count)
        stepStart = Self.now()
    }

    static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    /// A session frozen in a given state, for screenshots.
    static func demo(phase: Phase, sample: FaceSample?, input: TrackingInput = .nose) -> CalibrationSession {
        let s = CalibrationSession(kind: .movement(input), displaySize: CGSize(width: 1512, height: 982), displayID: 0,
                                   existingBaseline: nil, gestures: [])
        s.phase = phase
        s.latest = sample
        switch phase {
        case .framing:
            s.checks = Checks(face: true, light: true, centred: true, distance: false)
        case .targets:
            s.targetIndex = 4
            s.settling = false
            s.progress = 0.65
        case .result:
            s.result = CalibrationProfile(
                input: input, createdAt: Date(), displaySize: Vec2(1512, 982), displayID: nil,
                mapping: PointerCalibration(basis: .affine, featureMean: [0, 0], featureScale: [1, 1], coefficientsX: [0, 0, 0],
                                            coefficientsY: [0, 0, 0], meanError: 0.022, sampleCount: 243),
                neutralNose: .zero, neutralFaceScale: 0.12, travel: Vec2(0.6, 0.45))
            s.countdown = 3
        default:
            break
        }
        return s
    }

    // MARK: Input

    func ingest(_ sample: FaceSample?) {
        let now = Self.now()
        latest = sample
        if let s = sample {
            lastFace = now
            faceMissing = false
            checks = Checks(
                face: s.confidence > 0.5,
                light: s.brightness > 0.18,
                centred: (0.22...0.78).contains(s.faceCenter.x) && (0.15...0.85).contains(s.faceCenter.y),
                distance: (0.065...0.34).contains(s.faceScale)
            )
        } else {
            checks = Checks()
            faceMissing = now - lastFace > 0.6
        }
        guard let s = sample else { return }

        switch phase {
        case .neutral:
            neutralMetrics.append(s.metrics)
            neutralNoses.append(s.nose)
            neutralScales.append(s.faceScale)
            log.append(.init(sample: s, phase: "neutral", target: nil, recording: true))
        case .targets:
            log.append(.init(sample: s, phase: "target", target: targets[targetIndex], recording: !settling))
            guard !settling, let input else { return }
            points.append(CalibrationPoint(target: targets[targetIndex], features: s.features(for: input)))
            targetNoses[targetIndex].append(s.nose)
            targetSamples += 1
        case .gestures:
            let g = gestureList[gestureIndex]
            let v = gestureValue(g, s.metrics)
            liveGestureLevel = gestureLevel(g, v)
            if gestureStage == .perform { gestureValues.append(v) }
        default:
            break
        }
    }

    func tick() {
        let now = Self.now()
        let t = now - stepStart
        switch phase {
        case .framing:
            if checks.allGood {
                if goodSince == nil { goodSince = now }
                progress = min((now - (goodSince ?? now)) / 1.0, 1)
                if progress >= 1 { begin(.neutral) }
            } else {
                goodSince = nil
                progress = 0
            }
        case .neutral:
            progress = min(Double(neutralMetrics.count) / 50, 1)
            if progress >= 1 { finishNeutral() }
        case .targets:
            if settling {
                progress = min(t / settleTime, 1)
                if t >= settleTime {
                    settling = false
                    stepStart = now
                    targetSamples = 0
                    progress = 0
                }
            } else {
                progress = min(t / sampleTime, 1)
                if t >= sampleTime, targetSamples >= 10 { nextTarget() }
            }
        case .gestures:
            switch gestureStage {
            case .ready:
                progress = min(t / 1.2, 1)
                if t >= 1.2 { gestureStage = .perform; stepStart = now; gestureValues = [] }
            case .perform:
                progress = min(t / 2.2, 1)
                if t >= 2.2 { finishGesture(); gestureStage = .relax; stepStart = now }
            case .relax:
                progress = min(t / 0.8, 1)
                if t >= 0.8 { nextGesture() }
            }
        case .result:
            countdown = max(0, 4 - t)
            if t >= 4 { finish() }
        case .failed:
            break
        }
    }

    // MARK: Keys

    /// Space: move on without waiting.
    func skip() {
        switch phase {
        case .framing where checks.face: begin(.neutral)
        case .targets where settling: stepStart = Self.now() - settleTime
        case .gestures: nextGesture()
        case .result: finish()
        default: break
        }
    }

    func cancel() {
        onFinish?(nil, nil)
        onFinish = nil
    }

    func redo() {
        points = []
        targetNoses = Array(repeating: [], count: targets.count)
        neutralMetrics = []
        neutralNoses = []
        neutralScales = []
        peaks = [:]
        result = nil
        resultBaseline = nil
        targetIndex = 0
        gestureIndex = 0
        begin(.framing)
    }

    func finish() {
        onFinish?(result, resultBaseline)
        onFinish = nil
    }

    // MARK: Steps

    private func begin(_ p: Phase) {
        phase = p
        progress = 0
        stepStart = Self.now()
        goodSince = nil
        if p == .targets {
            settling = true
            targetSamples = 0
        }
        if p == .gestures {
            gestureStage = .ready
            gestureValues = []
        }
    }

    private func finishNeutral() {
        let neutral = GestureDetector.median(neutralMetrics)
        var base = GestureBaseline(neutral: neutral, peaks: existingBaseline?.peaks ?? [:])
        if case .gestures = kind { base.peaks = existingBaseline?.peaks ?? [:] }
        resultBaseline = base
        switch kind {
        case .movement: begin(.targets)
        case .gestures: gestureList.isEmpty ? begin(.result) : begin(.gestures)
        }
    }

    private func nextTarget() {
        if targetIndex + 1 < targets.count {
            targetIndex += 1
            settling = true
            stepStart = Self.now()
            targetSamples = 0
            progress = 0
            return
        }
        finishTargets()
    }

    private func finishTargets() {
        guard let input else { return }
        let ridge = Double(points.count) * (input == .eyes ? 0.02 : 0.005)
        guard let mapping = PointerCalibration.fit(points: points, basis: .quadratic, ridge: ridge) else {
            CalibrationLog.write(input: input, entries: log, profile: nil)
            phase = .failed("There were not enough steady readings. Check the light on your face and try again.")
            return
        }
        let scale = median(neutralScales)
        let noseMedians = targetNoses.map { list in Vec2(median(list.map(\.x)), median(list.map(\.y))) }
        result = CalibrationProfile(
            input: input,
            createdAt: Date(),
            displaySize: Vec2(Double(displaySize.width), Double(displaySize.height)),
            displayID: displayID,
            mapping: mapping,
            neutralNose: Vec2(median(neutralNoses.map(\.x)), median(neutralNoses.map(\.y))),
            neutralFaceScale: scale,
            travel: CalibrationProfile.estimateTravel(targets: targets, noses: noseMedians, faceScale: scale)
        )
        CalibrationLog.write(input: input, entries: log, profile: result)
        begin(.result)
    }

    private func finishGesture() {
        let g = gestureList[gestureIndex]
        guard !gestureValues.isEmpty else { return }
        // A high percentile, not the max: one glitchy frame must not set the bar.
        let sorted = gestureValues.sorted()
        let peak = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.85))]
        peaks[g] = peak
    }

    private func nextGesture() {
        if gestureIndex + 1 < gestureList.count {
            gestureIndex += 1
            gestureStage = .ready
            stepStart = Self.now()
            gestureValues = []
            liveGestureLevel = 0
            return
        }
        if var base = resultBaseline {
            for (g, p) in peaks { base.peaks[g] = p }
            resultBaseline = base
        }
        begin(.result)
    }

    // MARK: Gesture measurement

    private func gestureValue(_ g: FaceGesture, _ m: FaceMetrics) -> Double {
        let n = resultBaseline?.neutral ?? m
        switch g {
        case .mouthOpen: return m.mouthOpen
        case .browRaise: return m.browRaise
        case .smile: return m.smile
        case .longBlink:
            return min(GestureDetector.closedness(open: m.leftEyeOpen, neutral: n.leftEyeOpen),
                       GestureDetector.closedness(open: m.rightEyeOpen, neutral: n.rightEyeOpen))
        case .leftWink: return GestureDetector.closedness(open: m.leftEyeOpen, neutral: n.leftEyeOpen)
        case .rightWink: return GestureDetector.closedness(open: m.rightEyeOpen, neutral: n.rightEyeOpen)
        }
    }

    /// 0...1 strength for the live meter, against a typical full expression.
    private func gestureLevel(_ g: FaceGesture, _ v: Double) -> Double {
        let n = resultBaseline?.neutral
        switch g {
        case .mouthOpen: return ((v - (n?.mouthOpen ?? 0)) / 0.3).clamped(0, 1.2)
        case .browRaise: return ((v - (n?.browRaise ?? 0)) / 0.08).clamped(0, 1.2)
        case .smile: return ((v - (n?.smile ?? 0)) / 0.2).clamped(0, 1.2)
        case .longBlink, .leftWink, .rightWink: return (v / 0.85).clamped(0, 1.2)
        }
    }

    // MARK: Result wording

    var errorPoints: Double? { result?.meanErrorPoints }

    var qualityLabel: String {
        guard let e = errorPoints else { return "" }
        switch e {
        case ..<45: return "Excellent"
        case ..<90: return "Good"
        case ..<150: return "Fair"
        default: return "Rough, better light may help"
        }
    }

    private func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }
}

/// The raw numbers of the last calibration run, kept on this Mac so tracking
/// can be tuned against real data (and attached to a bug report). Only
/// landmark-derived numbers, never images.
enum CalibrationLog {
    struct Entry: Codable {
        var phase: String
        var target: Vec2?
        var recording: Bool
        var time: Double
        var nose: Vec2
        var headAngle: Vec2
        var gaze: Vec2
        var faceScale: Double
        var confidence: Double
        var metrics: FaceMetrics

        init(sample s: FaceSample, phase: String, target: Vec2?, recording: Bool) {
            self.phase = phase
            self.target = target
            self.recording = recording
            time = s.time
            nose = s.nose
            headAngle = s.headAngle
            gaze = s.gaze
            faceScale = s.faceScale
            confidence = s.confidence
            metrics = s.metrics
        }
    }

    struct File: Codable {
        var input: TrackingInput
        var date: Date
        var profile: CalibrationProfile?
        var entries: [Entry]
    }

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nod")
        return dir.appendingPathComponent("last-calibration-v1.json")
    }

    static func write(input: TrackingInput, entries: [Entry], profile: CalibrationProfile?) {
        let file = File(input: input, date: Date(), profile: profile, entries: entries)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Controller

/// Runs a calibration in a full-screen window on the mapping display.
@MainActor
final class CalibrationController {
    private let model: AppModel
    private var window: NSWindow?
    private var session: CalibrationSession?
    private var timer: Timer?
    private var keyMonitor: Any?
    private var cursorHidden = false
    var onClose: (() -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    var isRunning: Bool { session != nil }

    func start(_ kind: CalibrationSession.Kind) {
        guard session == nil, let display = Displays.mappingDisplay(preferred: model.settings.displayID),
              let screen = Displays.screen(for: display.id) ?? NSScreen.main else { return }

        let gestures: [FaceGesture]
        if case .gestures = kind {
            let enabled = FaceGesture.allCases.filter { model.settings.binding(for: $0).enabled }
            gestures = enabled.isEmpty ? [.mouthOpen, .browRaise] : enabled
        } else {
            gestures = []
        }
        let session = CalibrationSession(kind: kind, displaySize: screen.frame.size, displayID: display.id,
                                         existingBaseline: model.gestureBaseline, gestures: gestures)
        session.onFinish = { [weak self] profile, baseline in self?.close(profile: profile, baseline: baseline) }
        self.session = session

        model.beginCalibration()
        model.retainFrames("calibration")
        model.calibrationSink = { [weak session] sample in session?.ingest(sample) }

        let w = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: CalibrationView(session: session, capture: model.pipeline.session))
        w.setFrame(screen.frame, display: true)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        NSCursor.hide()
        cursorHidden = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak session] _ in
            MainActor.assumeIsolated { session?.tick() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak session] event in
            guard let session else { return event }
            switch Int(event.keyCode) {
            case 53: session.cancel()                       // Escape
            case 49, 36, 76: session.skip()                 // Space, Return, Enter
            case 15 where session.phase == .result: session.redo() // R
            default: return event
            }
            return nil
        }
    }

    private func close(profile: CalibrationProfile?, baseline: GestureBaseline?) {
        timer?.invalidate()
        timer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        window?.orderOut(nil)
        window = nil
        model.calibrationSink = nil
        model.releaseFrames("calibration")
        model.endCalibration(profile: profile, baseline: baseline)
        session = nil
        onClose?()
    }
}

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

struct CalibrationView: View {
    let session: CalibrationSession
    let capture: AVCaptureSession

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.ink.opacity(0.97)
                RadialGradient(colors: [Theme.blue.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.6)

                switch session.phase {
                case .framing: framing
                case .neutral: neutral
                case .targets: targets(in: geo.size)
                case .gestures: gestures
                case .result: result
                case let .failed(message): failed(message)
                }

                VStack {
                    Spacer()
                    footer.padding(.bottom, 18)
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    // MARK: Framing

    private var framing: some View {
        VStack(spacing: 22) {
            title("Let's find your face", "Sit the way you normally do, facing the screen.")
            ZStack {
                CameraPreview(session: capture)
                FaceMeshView(sample: session.latest, framing: .camera, showGrid: false, placeholder: .none)
                if session.progress > 0 {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .trim(from: 0, to: session.progress)
                        .stroke(Theme.anodized, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
            .frame(width: 520, height: 390)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.inkLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)

            HStack(spacing: 12) {
                check("Face found", session.checks.face)
                check("Good light", session.checks.light)
                check("Centred", session.checks.centred)
                check(distanceText, session.checks.distance)
            }
            Text(session.checks.allGood ? "Perfect. Hold still…" : "Nod starts on its own when all four are green.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var distanceText: String {
        guard let s = session.latest else { return "Distance" }
        if s.faceScale < 0.065 { return "Come closer" }
        if s.faceScale > 0.34 { return "Move back" }
        return "Distance"
    }

    private func check(_ text: String, _ ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Theme.teal : .white.opacity(0.4))
            Text(text).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.white.opacity(ok ? 0.1 : 0.05)))
        .overlay(Capsule().strokeBorder(ok ? Theme.teal.opacity(0.5) : .white.opacity(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: ok)
    }

    // MARK: Neutral

    private var neutral: some View {
        VStack(spacing: 34) {
            title("Relax your face", session.input == .eyes ? "Look at the dot with a natural expression." : "Look at the dot and let your face rest.")
            TargetMark(settling: false, progress: session.progress, pulse: true)
            Spacer().frame(height: 40)
        }
    }

    // MARK: Targets

    private func targets(in size: CGSize) -> some View {
        let t = session.targets[session.targetIndex]
        let p = CGPoint(x: t.x * size.width, y: t.y * size.height)
        return ZStack {
            ForEach(0..<session.targetIndex, id: \.self) { i in
                let d = session.targets[i]
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.teal.opacity(0.55))
                    .position(x: d.x * size.width, y: d.y * size.height)
            }
            VStack(spacing: 8) {
                Text(session.input == .eyes ? "Follow the dot with your eyes" : "Point your nose at the dot")
                    .font(.system(size: 22, weight: .semibold))
                Text(session.input == .eyes ? "Keep your head still." : "Turn your head, keep your eyes relaxed.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(session.targetIndex + 1) of \(session.targets.count)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 4)
                if session.faceMissing {
                    Label("Can't see your face", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.gold)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 6)
                }
            }
            .position(x: size.width / 2, y: size.height * 0.3)
            TargetMark(settling: session.settling, progress: session.progress, pulse: false)
                .position(p)
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: session.targetIndex)
        }
    }

    // MARK: Gestures

    private var gestures: some View {
        let g = session.gestureList[session.gestureIndex]
        return VStack(spacing: 24) {
            Text("Expression \(session.gestureIndex + 1) of \(session.gestureList.count)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            IconBadge(symbol: g.symbol, colors: [Theme.teal, Theme.blue], size: 84)
                .shadow(color: Theme.teal.opacity(0.4), radius: 20)
            Text(g.instruction).font(.system(size: 26, weight: .semibold))
            Text(stageText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(session.gestureStage == .perform ? Theme.gold : .white.opacity(0.6))
            ActivationMeter(value: session.liveGestureLevel, height: 10, range: 1.2)
                .frame(width: 360)
            InkCard {
                FaceMeshView(sample: session.latest, activations: [:], placeholder: .searching)
            }
            .frame(width: 220, height: 165)
        }
    }

    private var stageText: String {
        switch session.gestureStage {
        case .ready: "Get ready…"
        case .perform: "Now, and hold it"
        case .relax: "Relax"
        }
    }

    // MARK: Result

    private var result: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.anodized, lineWidth: 5).frame(width: 96, height: 96)
                Image(systemName: "checkmark").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
            }
            .shadow(color: Theme.teal.opacity(0.5), radius: 24)
            if let e = session.errorPoints {
                Text("Calibrated").font(.system(size: 30, weight: .bold))
                Text("\(session.qualityLabel). Typical error about \(Int(e.rounded())) points.")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Expressions learned").font(.system(size: 30, weight: .bold))
                Text("Thresholds now match your face.").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 12) {
                Button("Redo") { session.redo() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Done") { session.finish() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 8)
            Text("Closing in \(Int(session.countdown.rounded(.up)))…")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(Theme.gold)
            Text("That didn't work").font(.system(size: 28, weight: .bold))
            Text(message).font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 12) {
                Button("Cancel") { session.cancel() }.buttonStyle(.bordered).controlSize(.large)
                Button("Try Again") { session.redo() }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: Chrome

    private func title(_ t: String, _ s: String) -> some View {
        VStack(spacing: 6) {
            Text(t).font(.system(size: 28, weight: .bold))
            Text(s).font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            PhaseDots(phase: session.phase, kind: session.kind)
            Text("Esc to cancel  ·  Space to skip ahead")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

/// The calibration target: a ring that closes in while you settle, then a
/// gold arc that fills while Nod records.
struct TargetMark: View {
    let settling: Bool
    let progress: Double
    let pulse: Bool
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.teal.opacity(0.35))
                .frame(width: 26, height: 26)
                .blur(radius: 8)
            Circle()
                .stroke(Theme.anodized, lineWidth: 3)
                .frame(width: ringSize, height: ringSize)
                .opacity(settling ? 1 : 0.35)
            if !settling || pulse {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
            }
            Circle().fill(.white).frame(width: 9, height: 9)
        }
        .frame(width: 100, height: 100)
        .scaleEffect(pulse && breathe ? 1.08 : 1)
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private var ringSize: CGFloat {
        settling ? 92 - 58 * CGFloat(progress) : 34
    }
}

/// Which stage of calibration we are in, as a row of dots.
struct PhaseDots: View {
    let phase: CalibrationSession.Phase
    let kind: CalibrationSession.Kind

    private var stages: [String] {
        if case .gestures = kind { return ["Face", "Rest", "Expressions", "Done"] }
        return ["Face", "Rest", "Targets", "Done"]
    }

    private var current: Int {
        switch phase {
        case .framing: 0
        case .neutral: 1
        case .targets, .gestures: 2
        case .result, .failed: 3
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(stages.enumerated()), id: \.offset) { i, name in
                HStack(spacing: 5) {
                    Circle()
                        .fill(i <= current ? AnyShapeStyle(Theme.anodized) : AnyShapeStyle(.white.opacity(0.18)))
                        .frame(width: 7, height: 7)
                    Text(name)
                        .font(.system(size: 11, weight: i == current ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(i == current ? 0.85 : 0.4))
                }
            }
        }
    }
}
