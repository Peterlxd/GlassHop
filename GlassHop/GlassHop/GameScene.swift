import SceneKit
import SwiftUI
import UIKit
import AVFoundation

struct JumpSceneView: UIViewRepresentable {
    @ObservedObject var game: GameViewModel

    func makeUIView(context: Context) -> JumpSCNView {
        let view = JumpSCNView(engine: game.engine)
        game.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: JumpSCNView, context: Context) {
        game.attach(to: uiView)
    }
}

final class JumpSCNView: SCNView {
    let engine: JumpGameEngine

    init(engine: JumpGameEngine, frame: CGRect = .zero) {
        self.engine = engine
        super.init(frame: frame, options: nil)
        backgroundColor = UIColor(red: 0.025, green: 0.045, blue: 0.075, alpha: 1)
        preferredFramesPerSecond = 60
        antialiasingMode = .multisampling4X
        isPlaying = true
        rendersContinuously = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine.beginCharge()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine.releaseCharge()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine.releaseCharge()
    }
}

final class JumpGameEngine: NSObject, SCNSceneRendererDelegate {
    var gameStateChanged: ((GameState, Int, CGFloat) -> Void)?

    private let scene = SCNScene()
    private let world = SCNNode()
    private let cameraNode = SCNNode()
    private let cameraFocus = SCNNode()
    private let player = GlassPlayerNode()
    private var platforms: [GlassPlatformNode] = []
    private var target: GlassPlatformNode?
    private var state: GameState = .ready
    private var score = 0
    private var charge: CGFloat = 0
    private var chargeStartedAt: TimeInterval = 0
    private var jumpStartedAt: TimeInterval = 0
    private var jumpDuration: TimeInterval = 0
    private var jumpOrigin = SCNVector3Zero
    private var jumpDestination = SCNVector3Zero
    private var lastPublishedCharge: CGFloat = -1
    private var lastFrameTime: TimeInterval = 0
    private var cameraFocusGoal = SCNVector3Zero
    private var cameraPositionGoal = SCNVector3Zero
    private var isConfigured = false

    private let platformColors = [
        UIColor(red: 0.11, green: 0.56, blue: 0.62, alpha: 1),
        UIColor(red: 0.73, green: 0.22, blue: 0.40, alpha: 1),
        UIColor(red: 0.72, green: 0.48, blue: 0.18, alpha: 1),
        UIColor(red: 0.26, green: 0.32, blue: 0.72, alpha: 1)
    ]

    func attach(to view: JumpSCNView) {
        guard view.scene !== scene else { return }
        configureScene()
        view.scene = scene
        view.delegate = self
        restart(playsFeedback: false)
    }

    func restart(playsFeedback: Bool = true) {
        guard isConfigured else { return }
        world.childNodes.forEach { $0.removeFromParentNode() }
        platforms.removeAll()
        score = 0
        charge = 0
        lastPublishedCharge = -1
        state = .ready

        let start = addPlatform(position: SCNVector3(0, 0, 0), width: 2.7, length: 2.7, colorIndex: 0)
        let first = addPlatform(position: SCNVector3(2.55, 0.18, -3.1), width: 2.25, length: 2.25, colorIndex: 1)
        player.reset()
        player.position = SCNVector3(start.position.x, start.topY + player.radius, start.position.z)
        world.addChildNode(player)
        target = first
        lastFrameTime = 0
        moveCamera(toward: start.position, animated: false)
        if playsFeedback {
            GameFeedback.shared.restarted()
        }
        publish(force: true)
    }

    func beginCharge() {
        guard state == .ready else { return }
        state = .charging
        chargeStartedAt = CACurrentMediaTime()
        GameFeedback.shared.chargeStarted()
        publish(force: true)
    }

    func releaseCharge() {
        guard state == .charging, let target else { return }
        charge = max(0.12, charge)
        state = .jumping
        jumpStartedAt = CACurrentMediaTime()
        jumpOrigin = player.position
        let targetPoint = SCNVector3(target.position.x, target.topY + player.radius, target.position.z)
        let direction = normalized(horizontalVector(from: jumpOrigin, to: targetPoint))
        let requestedDistance = 1.25 + Float(charge) * 5.6
        jumpDestination = SCNVector3(
            jumpOrigin.x + direction.x * requestedDistance,
            targetPoint.y,
            jumpOrigin.z + direction.z * requestedDistance
        )
        jumpDuration = 0.48 + TimeInterval(charge) * 0.34
        player.launch(direction: direction)
        GameFeedback.shared.launched()
        publish(force: true)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let deltaTime: TimeInterval
        if lastFrameTime > 0 {
            deltaTime = min(max(time - lastFrameTime, 1 / 120), 1 / 24)
        } else {
            deltaTime = 1 / 60
        }
        lastFrameTime = time

        switch state {
        case .charging:
            charge = min(1, CGFloat((time - chargeStartedAt) / 1.15))
            player.setCharge(charge)
            publish()
        case .jumping:
            updateJump(at: time)
        default:
            break
        }

        smoothCamera(deltaTime: deltaTime)
    }

    private func configureScene() {
        guard !isConfigured else { return }
        isConfigured = true
        scene.rootNode.addChildNode(world)
        scene.rootNode.addChildNode(cameraFocus)
        scene.background.contents = UIColor(red: 0.018, green: 0.028, blue: 0.040, alpha: 1)
        scene.fogColor = UIColor(red: 0.018, green: 0.028, blue: 0.040, alpha: 1)
        scene.fogStartDistance = 14
        scene.fogEndDistance = 34

        let floor = SCNFloor()
        floor.reflectivity = 0.18
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.025, green: 0.045, blue: 0.060, alpha: 1)
        floor.firstMaterial?.roughness.contents = 0.90
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -0.30
        scene.rootNode.addChildNode(floorNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.32, green: 0.39, blue: 0.48, alpha: 1)
        ambient.light?.intensity = 150
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.color = UIColor(red: 0.74, green: 0.94, blue: 1, alpha: 1)
        key.light?.intensity = 520
        key.light?.castsShadow = true
        key.light?.shadowRadius = 10
        key.position = SCNVector3(-3, 8, 5)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.color = UIColor(red: 0.45, green: 0.27, blue: 0.38, alpha: 1)
        rim.light?.intensity = 160
        rim.eulerAngles = SCNVector3(-0.9, -0.6, 0)
        scene.rootNode.addChildNode(rim)

        let camera = SCNCamera()
        camera.wantsHDR = true
        camera.bloomIntensity = 0.05
        camera.bloomBlurRadius = 4
        camera.bloomThreshold = 0.95
        camera.zFar = 70
        cameraNode.camera = camera
        let lookAt = SCNLookAtConstraint(target: cameraFocus)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]
        scene.rootNode.addChildNode(cameraNode)
    }

    private func updateJump(at time: TimeInterval) {
        let progress = min(1, CGFloat((time - jumpStartedAt) / jumpDuration))
        let apex = 1.1 + Float(charge) * 1.35
        player.position = SCNVector3(
            lerp(jumpOrigin.x, jumpDestination.x, progress),
            lerp(jumpOrigin.y, jumpDestination.y, progress) + sin(Float(progress) * .pi) * apex,
            lerp(jumpOrigin.z, jumpDestination.z, progress)
        )

        let cameraProgress = progress * progress * (3 - 2 * progress)
        let cameraPoint = SCNVector3(
            lerp(jumpOrigin.x, jumpDestination.x, cameraProgress),
            0,
            lerp(jumpOrigin.z, jumpDestination.z, cameraProgress)
        )
        moveCamera(toward: cameraPoint, animated: true)

        guard progress >= 1 else { return }
        resolveLanding()
    }

    private func resolveLanding() {
        guard let target else { return }
        let distance = horizontalDistance(player.position, target.position)
        let landed = distance <= min(target.width, target.length) * 0.43

        if landed {
            let perfect = distance < 0.28
            score += perfect ? 2 : 1
            player.land()
            GameFeedback.shared.landed(perfect: perfect)
            let next = makeNextPlatform(from: target)
            self.target = next
            state = .ready
            moveCamera(toward: target.position, animated: true)
            publish(force: true)
        } else {
            state = .gameOver
            let direction = normalized(horizontalVector(from: target.position, to: player.position))
            player.fall(direction: direction)
            GameFeedback.shared.fell()
            publish(force: true)
        }
    }

    private func makeNextPlatform(from current: GlassPlatformNode) -> GlassPlatformNode {
        let side: Float = Bool.random() ? 1 : -1
        let distance = Float.random(in: 3.0...4.5)
        let lateral = side * distance * Float.random(in: 0.55...0.82)
        let forward = -distance * Float.random(in: 0.58...0.82)
        let height = current.position.y + Float.random(in: -0.04...0.28)
        let width = Float.random(in: 1.85...2.55)
        let length = Float.random(in: 1.85...2.55)
        return addPlatform(
            position: SCNVector3(current.position.x + lateral, height, current.position.z + forward),
            width: width,
            length: length,
            colorIndex: score % platformColors.count
        )
    }

    @discardableResult
    private func addPlatform(position: SCNVector3, width: Float, length: Float, colorIndex: Int) -> GlassPlatformNode {
        let platform = GlassPlatformNode(width: width, length: length, tint: platformColors[colorIndex], style: colorIndex)
        platform.position = position
        world.addChildNode(platform)
        platforms.append(platform)
        return platform
    }

    private func moveCamera(toward point: SCNVector3, animated: Bool) {
        cameraFocusGoal = SCNVector3(point.x, 0, point.z - 1.35)
        cameraPositionGoal = SCNVector3(cameraFocusGoal.x, 8.8, cameraFocusGoal.z + 10.8)

        if !animated {
            cameraFocus.position = cameraFocusGoal
            cameraNode.position = cameraPositionGoal
        }
    }

    private func smoothCamera(deltaTime: TimeInterval) {
        let followSpeed: Float = state == .jumping ? 8.5 : 6.2
        let alpha = 1 - exp(-followSpeed * Float(deltaTime))
        cameraFocus.position = smoothVector(cameraFocus.position, cameraFocusGoal, alpha: alpha)
        cameraNode.position = smoothVector(cameraNode.position, cameraPositionGoal, alpha: alpha)
    }

    private func smoothVector(_ current: SCNVector3, _ target: SCNVector3, alpha: Float) -> SCNVector3 {
        SCNVector3(
            current.x + (target.x - current.x) * alpha,
            current.y + (target.y - current.y) * alpha,
            current.z + (target.z - current.z) * alpha
        )
    }

    private func publish(force: Bool = false) {
        guard force || abs(charge - lastPublishedCharge) >= 0.02 else { return }
        lastPublishedCharge = charge
        let callback = gameStateChanged
        let publishedState = state
        let publishedScore = score
        let publishedCharge = charge
        DispatchQueue.main.async {
            callback?(publishedState, publishedScore, publishedCharge)
        }
    }

    private func lerp(_ from: Float, _ to: Float, _ progress: CGFloat) -> Float {
        from + (to - from) * Float(progress)
    }

    private func horizontalVector(from: SCNVector3, to: SCNVector3) -> SCNVector3 {
        SCNVector3(to.x - from.x, 0, to.z - from.z)
    }

    private func normalized(_ vector: SCNVector3) -> SCNVector3 {
        let magnitude = max(sqrt(vector.x * vector.x + vector.z * vector.z), 0.001)
        return SCNVector3(vector.x / magnitude, 0, vector.z / magnitude)
    }

    private func horizontalDistance(_ left: SCNVector3, _ right: SCNVector3) -> Float {
        sqrt(pow(left.x - right.x, 2) + pow(left.z - right.z, 2))
    }
}

private final class GlassPlatformNode: SCNNode {
    let width: Float
    let length: Float
    private let height: Float = 0.56
    var topY: Float { position.y + height / 2 }

    init(width: Float, length: Float, tint: UIColor, style: Int) {
        self.width = width
        self.length = length
        super.init()

        addUndercarriage(width: width, length: length)
        addMainBlock(width: width, length: length, tint: tint)
        addSoftTop(width: width, length: length, tint: tint)
        addStyleDetail(width: width, length: length, tint: tint, style: style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addUndercarriage(width: Float, length: Float) {
        let base = SCNBox(width: CGFloat(width * 0.98), height: 0.18, length: CGFloat(length * 0.98), chamferRadius: 0.14)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.020, green: 0.027, blue: 0.035, alpha: 1)
        material.roughness.contents = 0.78
        material.metalness.contents = 0.06
        base.materials = [material]

        let node = SCNNode(geometry: base)
        node.position.y = -height / 2 + 0.04
        addChildNode(node)
    }

    private func addMainBlock(width: Float, length: Float, tint: UIColor) {
        let body = SCNBox(width: CGFloat(width), height: CGFloat(height * 0.86), length: CGFloat(length), chamferRadius: 0.22)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = tint.withAlphaComponent(0.88)
        material.metalness.contents = 0.03
        material.roughness.contents = 0.38
        material.fresnelExponent = 1.20
        body.materials = [material]

        let node = SCNNode(geometry: body)
        node.position.y = 0
        addChildNode(node)
    }

    private func addSoftTop(width: Float, length: Float, tint: UIColor) {
        let cap = SCNBox(width: CGFloat(width * 0.78), height: 0.035, length: CGFloat(length * 0.78), chamferRadius: 0.12)
        let capMaterial = SCNMaterial()
        capMaterial.lightingModel = .physicallyBased
        capMaterial.diffuse.contents = tint.lightened(by: 0.16).withAlphaComponent(0.72)
        capMaterial.roughness.contents = 0.26
        capMaterial.metalness.contents = 0.01
        cap.materials = [capMaterial]

        let capNode = SCNNode(geometry: cap)
        capNode.position.y = height / 2 + 0.012
        addChildNode(capNode)
    }

    private func addStyleDetail(width: Float, length: Float, tint: UIColor, style: Int) {
        switch style % 4 {
        case 0:
            addCenterTile(width: width, length: length, tint: tint.darkened(by: 0.10))
        case 1:
            addRaisedPuck(width: width, length: length, tint: tint.lightened(by: 0.12))
        case 2:
            addStackedInset(width: width, length: length, tint: tint.darkened(by: 0.08))
        default:
            addCornerButton(width: width, length: length, tint: tint.lightened(by: 0.10))
        }
    }

    private func addCenterTile(width: Float, length: Float, tint: UIColor) {
        let tile = SCNBox(width: CGFloat(width * 0.44), height: 0.045, length: CGFloat(length * 0.44), chamferRadius: 0.08)
        tile.materials = [platformMaterial(color: tint.withAlphaComponent(0.70), roughness: 0.34)]
        let node = SCNNode(geometry: tile)
        node.position.y = height / 2 + 0.044
        addChildNode(node)
    }

    private func addRaisedPuck(width: Float, length: Float, tint: UIColor) {
        let puck = SCNCylinder(radius: CGFloat(min(width, length) * 0.18), height: 0.065)
        puck.radialSegmentCount = 36
        puck.materials = [platformMaterial(color: tint.withAlphaComponent(0.76), roughness: 0.30)]
        let node = SCNNode(geometry: puck)
        node.position.y = height / 2 + 0.058
        addChildNode(node)
    }

    private func addStackedInset(width: Float, length: Float, tint: UIColor) {
        let slab = SCNBox(width: CGFloat(width * 0.62), height: 0.055, length: CGFloat(length * 0.50), chamferRadius: 0.09)
        slab.materials = [platformMaterial(color: tint.withAlphaComponent(0.74), roughness: 0.36)]
        let node = SCNNode(geometry: slab)
        node.position = SCNVector3(0, height / 2 + 0.052, 0)
        addChildNode(node)
    }

    private func addCornerButton(width: Float, length: Float, tint: UIColor) {
        let button = SCNBox(width: CGFloat(width * 0.28), height: 0.060, length: CGFloat(length * 0.28), chamferRadius: 0.07)
        button.materials = [platformMaterial(color: tint.withAlphaComponent(0.76), roughness: 0.32)]
        let node = SCNNode(geometry: button)
        node.position = SCNVector3(width * 0.18, height / 2 + 0.055, -length * 0.18)
        addChildNode(node)
    }

    private func platformMaterial(color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = 0.02
        material.fresnelExponent = 1.15
        return material
    }
}

private extension UIColor {
    func lightened(by amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: min(red + amount, 1),
            green: min(green + amount, 1),
            blue: min(blue + amount, 1),
            alpha: alpha
        )
    }

    func darkened(by amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: max(red - amount, 0),
            green: max(green - amount, 0),
            blue: max(blue - amount, 0),
            alpha: alpha
        )
    }
}

private final class GlassPlayerNode: SCNNode {
    let radius: Float = 0.36

    override init() {
        super.init()
        let body = SCNSphere(radius: CGFloat(radius))
        body.segmentCount = 32
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.86, green: 0.97, blue: 1, alpha: 0.86)
        material.metalness.contents = 0.36
        material.roughness.contents = 0.06
        material.fresnelExponent = 1.4
        body.materials = [material]
        addChildNode(SCNNode(geometry: body))

        let halo = SCNTorus(ringRadius: 0.22, pipeRadius: 0.015)
        halo.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.72)
        let haloNode = SCNNode(geometry: halo)
        haloNode.eulerAngles.x = .pi / 2
        haloNode.position.y = -0.18
        addChildNode(haloNode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        removeAllActions()
        opacity = 1
        scale = SCNVector3(1, 1, 1)
        eulerAngles = SCNVector3Zero
    }

    func setCharge(_ amount: CGFloat) {
        let squash = Float(amount) * 0.20
        scale = SCNVector3(1 + squash, 1 - squash, 1 + squash)
    }

    func launch(direction: SCNVector3) {
        scale = SCNVector3(1, 1, 1)
        let angle = atan2(direction.x, direction.z)
        eulerAngles.y = angle
    }

    func land() {
        let compress = SCNAction.scale(to: 0.82, duration: 0.05)
        let settle = SCNAction.scale(to: 1, duration: 0.13)
        runAction(.sequence([compress, settle]))
    }

    func fall(direction: SCNVector3) {
        let move = SCNAction.moveBy(x: CGFloat(direction.x * 3.5), y: -3.5, z: CGFloat(direction.z * 3.5), duration: 0.58)
        move.timingMode = .easeIn
        let spin = SCNAction.rotateBy(x: 2.0, y: 1.2, z: 1.4, duration: 0.58)
        runAction(.group([move, spin, .fadeOut(duration: 0.58)]))
    }
}

private final class GameFeedback {
    static let shared = GameFeedback()

    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationImpact = UINotificationFeedbackGenerator()

    private init() {
        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: audioFormat)
    }

    func chargeStarted() {
        perform { feedback in
            feedback.lightImpact.impactOccurred(intensity: 0.45)
            feedback.playTone(from: 180, to: 230, duration: 0.06, volume: 0.10)
            feedback.prepare()
        }
    }

    func launched() {
        perform { feedback in
            feedback.mediumImpact.impactOccurred(intensity: 0.72)
            feedback.playTone(from: 260, to: 620, duration: 0.13, volume: 0.16)
        }
    }

    func landed(perfect: Bool) {
        perform { feedback in
            if perfect {
                feedback.heavyImpact.impactOccurred(intensity: 0.92)
                feedback.notificationImpact.notificationOccurred(.success)
                feedback.playTone(from: 720, to: 1_080, duration: 0.17, volume: 0.20)
            } else {
                feedback.mediumImpact.impactOccurred(intensity: 0.65)
                feedback.playTone(from: 420, to: 610, duration: 0.11, volume: 0.14)
            }
            feedback.prepare()
        }
    }

    func fell() {
        perform { feedback in
            feedback.notificationImpact.notificationOccurred(.error)
            feedback.playTone(from: 240, to: 85, duration: 0.28, volume: 0.18)
        }
    }

    func restarted() {
        perform { feedback in
            feedback.lightImpact.impactOccurred(intensity: 0.35)
            feedback.playTone(from: 440, to: 620, duration: 0.08, volume: 0.09)
            feedback.prepare()
        }
    }

    private func perform(_ block: @escaping (GameFeedback) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            block(self)
        }
    }

    private func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notificationImpact.prepare()
    }

    private func playTone(from startFrequency: Double, to endFrequency: Double, duration: Double, volume: Float) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            return
        }

        let frameCount = AVAudioFrameCount(max(1, Int(audioFormat.sampleRate * duration)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?.pointee else { return }

        var phase = 0.0
        for index in 0..<Int(frameCount) {
            let progress = Double(index) / Double(frameCount)
            let frequency = startFrequency + (endFrequency - startFrequency) * progress
            phase += 2 * Double.pi * frequency / audioFormat.sampleRate
            let envelope = pow(1 - progress, 1.8)
            samples[index] = Float(sin(phase) * envelope) * volume
        }

        audioPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !audioPlayer.isPlaying {
            audioPlayer.play()
        }
    }
}
