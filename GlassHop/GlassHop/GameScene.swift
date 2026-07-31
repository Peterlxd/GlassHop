import SceneKit
import SwiftUI
import UIKit

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
    private var isConfigured = false

    private let platformColors = [
        UIColor(red: 0.16, green: 0.77, blue: 0.82, alpha: 1),
        UIColor(red: 0.95, green: 0.34, blue: 0.54, alpha: 1),
        UIColor(red: 0.98, green: 0.67, blue: 0.22, alpha: 1),
        UIColor(red: 0.42, green: 0.50, blue: 0.98, alpha: 1)
    ]

    func attach(to view: JumpSCNView) {
        guard view.scene !== scene else { return }
        configureScene()
        view.scene = scene
        view.delegate = self
        restart()
    }

    func restart() {
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
        moveCamera(toward: start.position, animated: false)
        publish(force: true)
    }

    func beginCharge() {
        guard state == .ready else { return }
        state = .charging
        chargeStartedAt = CACurrentMediaTime()
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
        publish(force: true)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
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
    }

    private func configureScene() {
        guard !isConfigured else { return }
        isConfigured = true
        scene.rootNode.addChildNode(world)
        scene.rootNode.addChildNode(cameraFocus)
        scene.background.contents = UIColor(red: 0.025, green: 0.045, blue: 0.075, alpha: 1)
        scene.fogColor = UIColor(red: 0.025, green: 0.045, blue: 0.075, alpha: 1)
        scene.fogStartDistance = 14
        scene.fogEndDistance = 34

        let floor = SCNFloor()
        floor.reflectivity = 0.18
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.04, green: 0.08, blue: 0.13, alpha: 1)
        floor.firstMaterial?.roughness.contents = 0.78
        let floorNode = SCNNode(geometry: floor)
        floorNode.position.y = -0.30
        scene.rootNode.addChildNode(floorNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.42, green: 0.55, blue: 0.76, alpha: 1)
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.color = UIColor(red: 0.74, green: 0.94, blue: 1, alpha: 1)
        key.light?.intensity = 1_400
        key.light?.castsShadow = true
        key.light?.shadowRadius = 10
        key.position = SCNVector3(-3, 8, 5)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.color = UIColor(red: 0.86, green: 0.30, blue: 0.58, alpha: 1)
        rim.light?.intensity = 620
        rim.eulerAngles = SCNVector3(-0.9, -0.6, 0)
        scene.rootNode.addChildNode(rim)

        let camera = SCNCamera()
        camera.wantsHDR = true
        camera.bloomIntensity = 0.32
        camera.bloomBlurRadius = 7
        camera.bloomThreshold = 0.72
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
        moveCamera(toward: player.position, animated: false)

        guard progress >= 1 else { return }
        resolveLanding()
    }

    private func resolveLanding() {
        guard let target else { return }
        let distance = horizontalDistance(player.position, target.position)
        let landed = distance <= min(target.width, target.length) * 0.43

        if landed {
            score += distance < 0.28 ? 2 : 1
            player.land()
            let next = makeNextPlatform(from: target)
            self.target = next
            state = .ready
            moveCamera(toward: target.position, animated: true)
            publish(force: true)
        } else {
            state = .gameOver
            let direction = normalized(horizontalVector(from: target.position, to: player.position))
            player.fall(direction: direction)
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
        let platform = GlassPlatformNode(width: width, length: length, tint: platformColors[colorIndex])
        platform.position = position
        world.addChildNode(platform)
        platforms.append(platform)
        return platform
    }

    private func moveCamera(toward point: SCNVector3, animated: Bool) {
        let target = SCNVector3(point.x, 0, point.z - 1.35)
        let apply = {
            self.cameraFocus.position = target
            self.cameraNode.position = SCNVector3(target.x, 8.8, target.z + 10.8)
        }
        guard animated else {
            apply()
            return
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.34
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        apply()
        SCNTransaction.commit()
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
    private let height: Float = 0.52
    var topY: Float { position.y + height / 2 }

    init(width: Float, length: Float, tint: UIColor) {
        self.width = width
        self.length = length
        super.init()

        let base = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.18)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = tint.withAlphaComponent(0.88)
        material.metalness.contents = 0.22
        material.roughness.contents = 0.18
        material.fresnelExponent = 1.25
        base.materials = [material]
        addChildNode(SCNNode(geometry: base))

        let cap = SCNBox(width: CGFloat(width * 0.82), height: 0.025, length: CGFloat(length * 0.82), chamferRadius: 0.12)
        let capMaterial = SCNMaterial()
        capMaterial.lightingModel = .constant
        capMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.48)
        capMaterial.transparency = 0.56
        cap.materials = [capMaterial]
        let capNode = SCNNode(geometry: cap)
        capNode.position.y = height / 2 + 0.014
        addChildNode(capNode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
