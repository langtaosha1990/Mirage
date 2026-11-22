import ARKit
import RealityKit
import UIKit

private enum EffectAssets {
    static let pigEar = MeshResource.generateCone(height: 0.10, radius: 0.052)
    static let pigInnerEar = MeshResource.generateSphere(radius: 0.025)
    static let elephantEar = MeshResource.generateSphere(radius: 0.06)
    static let elephantInnerEar = MeshResource.generateSphere(radius: 0.042)
    static let elephantTrunk = MeshResource.generateCylinder(height: 0.15, radius: 0.023)
    static let elephantTip = MeshResource.generateSphere(radius: 0.026)
    static let aura = MeshResource.generateBox(size: [0.20, 0.008, 0.008], cornerRadius: 0.004)
    static let orbitSmall = MeshResource.generateSphere(radius: 0.008)
    static let orbitLarge = MeshResource.generateSphere(radius: 0.012)
    static let crystal = MeshResource.generateCone(height: 0.22, radius: 0.075)
}

enum CameraMode { case world, selfie }

protocol MirageEffect {
    var id: String { get }
    var displayName: String { get }
    var symbol: String { get }
    func supports(_ mode: CameraMode) -> Bool
    func install(in arView: ARView, mode: CameraMode) -> AnchorEntity?
}

enum DemoEffect: String, CaseIterable, MirageEffect {
    case none, handshake, mime, bowler, mimeAndHat, pig, elephant, aura, faceGrid, yellowFace, facePaint, orbit, crystal, ocean, robot, drummer, biplane, baseball

    var usesManualPlacement: Bool { self == .handshake || appleModel != nil }

    var usesFaceUpdates: Bool {
        [.faceGrid, .yellowFace, .facePaint, .mime, .mimeAndHat].contains(self)
    }
    var appleModel: String? {
        switch self {
        case .robot: "robot"
        case .drummer: "toy_drummer"
        case .biplane: "toy_biplane_realistic"
        case .baseball: "ball_baseball_realistic"
        default: nil
        }
    }
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: "原相机"
        case .handshake: "握手合影"
        case .pig: "猪耳朵"
        case .elephant: "小象"
        case .aura: "光环"
        case .orbit: "星轨"
        case .crystal: "晶体"
        case .faceGrid: "面部网格"
        case .yellowFace: "黄色娃娃"
        case .facePaint: "面部彩绘"
        case .mime: "默剧小丑"
        case .bowler: "黑礼帽"
        case .mimeAndHat: "小丑＋礼帽"
        case .ocean: "海底鱼群"
        case .robot: "机器人"
        case .drummer: "鼓手"
        case .biplane: "双翼机"
        case .baseball: "棒球"
        }
    }
    var symbol: String {
        switch self {
        case .none: "circle.slash"
        case .handshake: "handshake"
        case .pig: "hare.fill"
        case .elephant: "wind"
        case .aura: "sparkles"
        case .orbit: "circle.dotted"
        case .crystal: "diamond.fill"
        case .faceGrid: "faceid"
        case .yellowFace: "face.smiling"
        case .facePaint: "paintbrush"
        case .mime: "theatermasks"
        case .bowler: "hat.cap"
        case .mimeAndHat: "sparkles"
        case .ocean: "fish"
        case .robot: "cpu"
        case .drummer: "music.note"
        case .biplane: "airplane"
        case .baseball: "baseball"
        }
    }
    func supports(_ mode: CameraMode) -> Bool {
        switch self {
        case .pig, .elephant, .aura, .faceGrid, .yellowFace, .facePaint, .mime, .bowler, .mimeAndHat: mode == .selfie
        case .orbit, .crystal, .ocean, .handshake: mode == .world
        case .robot, .drummer, .biplane, .baseball:
            mode == .world && appleModel.flatMap { Bundle.main.url(forResource: $0, withExtension: "usdz") } != nil
        case .none: true
        }
    }
    func hint(for mode: CameraMode) -> String {
        switch self {
        case .none: mode == .selfie ? "看向镜头，记录此刻" : "移动手机，探索周围空间"
        case .handshake: "对准地面，点一下放置人物"
        case .pig: "转动头部，猪耳朵会跟随你"
        case .elephant: "小象鼻已就位，试着左右摇头"
        case .aura: "保持面部在画面中央"
        case .orbit: "缓慢移动手机，观察星轨"
        case .crystal: "移动手机寻找平面"
        case .faceGrid: "看向镜头，试着改变表情"
        case .yellowFace: "试试眨眼或张嘴"
        case .facePaint: "点右下角画笔编辑彩绘"
        case .mime, .bowler, .mimeAndHat: "看向镜头，让特效对准脸部"
        case .ocean: "缓慢移动手机，寻找桌面或地面"
        case .robot, .drummer, .biplane, .baseball: "移动手机寻找桌面或地面"
        }
    }
    func install(in arView: ARView, mode: CameraMode) -> AnchorEntity? {
        switch self {
        case .none: return nil
        case .handshake: return nil
        case .robot, .drummer, .biplane, .baseball: return nil
        case .faceGrid, .yellowFace, .facePaint: return AnchorEntity(.face)
        case .mime, .bowler, .mimeAndHat:
            let anchor = AnchorEntity(.face)
            if self != .mime { MimeEffect.addHat(to: anchor) }
            return anchor
        case .ocean: return OceanEffect.makeAnchor()
        case .pig:
            let anchor = AnchorEntity(.face)
            let pink = SimpleMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.62, alpha: 1), roughness: 0.55, isMetallic: false)
            let inner = SimpleMaterial(color: UIColor(red: 1, green: 0.72, blue: 0.78, alpha: 1), roughness: 0.7, isMetallic: false)
            for side: Float in [-1, 1] {
                let ear = ModelEntity(mesh: EffectAssets.pigEar, materials: [pink])
                ear.position = [side * 0.085, 0.115, 0]
                ear.orientation = simd_quatf(angle: side * -0.18, axis: [0, 0, 1])
                anchor.addChild(ear)
                let center = ModelEntity(mesh: EffectAssets.pigInnerEar, materials: [inner])
                center.scale = [1.15, 1.55, 0.35]
                center.position = [side * 0.085, 0.118, -0.026]
                anchor.addChild(center)
            }
            return anchor
        case .elephant:
            let anchor = AnchorEntity(.face)
            let gray = SimpleMaterial(color: UIColor(red: 0.58, green: 0.68, blue: 0.78, alpha: 1), roughness: 0.68, isMetallic: false)
            let inner = SimpleMaterial(color: UIColor(red: 0.84, green: 0.61, blue: 0.68, alpha: 1), roughness: 0.75, isMetallic: false)
            for side: Float in [-1, 1] {
                let ear = ModelEntity(mesh: EffectAssets.elephantEar, materials: [gray])
                ear.scale = [0.45, 1.15, 0.18]
                ear.position = [side * 0.095, 0.025, 0.005]
                anchor.addChild(ear)
                let earInner = ModelEntity(mesh: EffectAssets.elephantInnerEar, materials: [inner])
                earInner.scale = [0.35, 1.05, 0.12]
                earInner.position = [side * 0.096, 0.025, -0.012]
                anchor.addChild(earInner)
            }
            let trunk = ModelEntity(mesh: EffectAssets.elephantTrunk, materials: [gray])
            trunk.position = [0, -0.075, -0.105]
            trunk.orientation = simd_quatf(angle: 0.10, axis: [1, 0, 0])
            anchor.addChild(trunk)
            let tip = ModelEntity(mesh: EffectAssets.elephantTip, materials: [gray])
            tip.scale = [1, 0.75, 1]
            tip.position = [0.012, -0.15, -0.112]
            anchor.addChild(tip)
            return anchor
        case .aura:
            let anchor = AnchorEntity(.face)
            let ring = ModelEntity(mesh: EffectAssets.aura, materials: [UnlitMaterial(color: UIColor(red: 0.72, green: 0.55, blue: 1, alpha: 0.92))])
            ring.position = [0, 0.16, -0.04]; anchor.addChild(ring); return anchor
        case .orbit:
            let anchor = AnchorEntity(world: [0, 0, -0.75])
            let colors: [UIColor] = [.systemPurple, .systemPink, .systemCyan, .white]
            for index in 0..<18 {
                let angle = Float(index) / 18 * .pi * 2
                let radius: Float = 0.22 + Float(index % 3) * 0.035
                let mesh = index.isMultiple(of: 2) ? EffectAssets.orbitSmall : EffectAssets.orbitLarge
                let sphere = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: colors[index % colors.count])])
                sphere.position = [cos(angle) * radius, sin(angle * 2) * 0.08, sin(angle) * radius]; anchor.addChild(sphere)
            }
            return anchor
        case .crystal:
            let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.18, 0.18]))
            let material = SimpleMaterial(color: UIColor(red: 0.45, green: 0.82, blue: 1, alpha: 0.82), roughness: 0.18, isMetallic: true)
            let crystal = ModelEntity(mesh: EffectAssets.crystal, materials: [material])
            crystal.position.y = 0.11; crystal.generateCollisionShapes(recursive: true); anchor.addChild(crystal); return anchor
        }
    }
}

final class EffectEngine {
    private var modelTask: Task<Void, Never>?
    private var faceGrid: FaceGrid?
    private var painting: CGImage?

    func setFacePainting(_ painting: CGImage?) {
        self.painting = painting
        faceGrid?.entity.removeFromParent()
        faceGrid = nil
    }
    private var faceCharacter: AppleFaceCharacter?
    private var didAttemptFaceCharacter = false
    private var currentAnchor: AnchorEntity?
    private var placeableModel: Entity?
    private var mediaPlane: MediaPlane?

    func advancePlacedImage() -> Bool {
        guard hasPlacedModel, let mediaPlane else { return false }
        mediaPlane.advance()
        return true
    }
    private var drummerPlayback: AnimationPlaybackController?
    var isDrummerPlaying: Bool { drummerPlayback?.isPlaying == true }

    @discardableResult
    func toggleDrummerAnimation() -> Bool {
        guard hasPlacedModel, currentEffectID == DemoEffect.drummer.id, let placeableModel else { return false }
        if let playback = drummerPlayback {
            playback.stop()
            drummerPlayback = nil
            return true
        }
        func animatedEntity(_ entity: Entity) -> (Entity, AnimationResource)? {
            if let animation = entity.availableAnimations.first { return (entity, animation) }
            for child in entity.children {
                if let match = animatedEntity(child) { return match }
            }
            return nil
        }
        guard let (entity, animation) = animatedEntity(placeableModel) else { return false }
        drummerPlayback = entity.playAnimation(animation.repeat(), transitionDuration: 0.15)
        return true
    }
    private var dragOffset: SIMD3<Float>?
    var canPlaceModel: Bool { placeableModel != nil }
    var hasPlacedModel: Bool { placeableModel != nil && currentAnchor != nil }

    func placementTransform(at point: CGPoint, in view: ARView) -> simd_float4x4? {
        view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first?.worldTransform
    }

    func placeModel(at transform: simd_float4x4, in view: ARView) {
        guard let model = placeableModel else { return }
        if currentAnchor != nil {
            let point = transform.columns.3
            model.setPosition(SIMD3(point.x, point.y, point.z), relativeTo: nil)
        } else {
            let anchor: AnchorEntity
            if currentEffectID == DemoEffect.handshake.id {
                let hit = transform.columns.3
                let ground = SIMD3(hit.x, hit.y, hit.z)
                anchor = AnchorEntity(world: ground)
                let towardCamera = view.cameraTransform.translation - ground
                model.orientation = simd_quatf(angle: atan2(towardCamera.x, towardCamera.z), axis: [0, 1, 0])
            } else {
                anchor = AnchorEntity(world: transform)
            }
            anchor.addChild(model)
            view.scene.addAnchor(anchor)
            currentAnchor = anchor
        }
    }

    func beginModelDrag(at point: CGPoint, in view: ARView) {
        dragOffset = nil
        guard hasPlacedModel, let model = placeableModel,
              let transform = placementTransform(at: point, in: view) else { return }
        let bounds = model.visualBounds(relativeTo: nil)
        guard let center = view.project(bounds.center),
              let base = view.project(model.position(relativeTo: nil)) else { return }
        let radius = max(44, hypot(center.x - base.x, center.y - base.y) * 1.5)
        guard hypot(center.x - point.x, center.y - point.y) <= radius else { return }
        let hit = transform.columns.3
        dragOffset = model.position(relativeTo: nil) - SIMD3(hit.x, hit.y, hit.z)
    }

    func updateModelDrag(at point: CGPoint, in view: ARView) {
        guard let dragOffset, let model = placeableModel,
              let transform = placementTransform(at: point, in: view) else { return }
        let hit = transform.columns.3
        let position = SIMD3(hit.x, hit.y, hit.z) + dragOffset
        guard simd_distance(position, model.position(relativeTo: nil)) < 0.25 else { return }
        model.setPosition(position, relativeTo: nil)
    }

    func endModelDrag() { dragOffset = nil }

    func resizeModel(by multiplier: Float) {
        guard hasPlacedModel, let model = placeableModel, multiplier.isFinite else { return }
        let scale = min(4, max(0.25, model.scale.x * multiplier))
        model.scale = SIMD3(repeating: scale)
    }
    private var currentEffectID: String?
    func runWorldTracking(in arView: ARView) -> Bool {
        guard ARWorldTrackingConfiguration.isSupported else { return false }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .none
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors]); return true
    }
    func runFaceTracking(in arView: ARView) -> Bool {
        guard ARFaceTrackingConfiguration.isSupported else { return false }
        let configuration = ARFaceTrackingConfiguration(); configuration.isLightEstimationEnabled = true
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors]); return true
    }
    func apply(_ effect: some MirageEffect, to arView: ARView, mode: CameraMode) {
        guard currentEffectID != effect.id else { return }
        removeCurrentEffect(from: arView)
        currentEffectID = effect.id
        if effect.id == DemoEffect.handshake.id {
            modelTask = Task { [weak self] in
                do {
                    let plane = try await MediaPlane.handshake()
                    guard !Task.isCancelled, let self, self.currentEffectID == effect.id else { return }
                    self.mediaPlane = plane
                    self.placeableModel = plane.root
                } catch {
                    if !Task.isCancelled { self?.currentEffectID = nil }
                }
            }
            return
        }
        if let name = (effect as? DemoEffect)?.appleModel {
            modelTask = Task { [weak self] in
                do {
                    guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let model = try await Entity(contentsOf: url)
                    guard !Task.isCancelled, let self, self.currentEffectID == effect.id else { return }
                    let names = name == "ball_baseball_realistic"
                        ? ["ball_baseball_realistic_bc"] : ["drummer_realistic_bc", "accessories_realistic_bc"]
                    let textures = names.map { name in
                        Bundle.main.url(forResource: name, withExtension: "png")
                            .flatMap { try? TextureResource.load(contentsOf: $0) }
                    }
                    let bounds = model.visualBounds(relativeTo: nil)
                    let factor = 0.25 / max(0.001, max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z)))
                    model.scale *= factor
                    model.position -= SIMD3(bounds.center.x, bounds.min.y, bounds.center.z) * factor
                    self.prepareDemoModelForRendering(model, textures: textures)
                    let container = Entity()
                    container.addChild(model)
                    self.placeableModel = container
                } catch {
                    if !Task.isCancelled { self?.currentEffectID = nil }
                }
            }
            return
        }
        guard effect.supports(mode), let anchor = effect.install(in: arView, mode: mode) else { return }
        currentAnchor = anchor
        arView.scene.addAnchor(anchor)
    }

    private func prepareDemoModelForRendering(_ entity: Entity, textures: [TextureResource?], accessory: Bool = false) {
        // These four mesh prims bind to the accessory material in the original USD.
        let accessory = accessory || ["polySurface221", "polySurface222", "polySurface223", "polySurface224"]
            .contains(where: { entity.name.hasPrefix($0) })
        if var model = entity.components[ModelComponent.self] {
            entity.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: false))
            entity.components.set(DynamicLightShadowComponent(castsShadow: false))
            model.materials = model.materials.map { material -> any RealityKit.Material in
                if textures.count == 1, let standard = material as? PhysicallyBasedMaterial,
                   standard.baseColor.texture != nil { return material }
                let slot = textures.count > 1 && accessory ? 1 : 0
                var basic = UnlitMaterial(color: slot == 1 ? .systemYellow : (textures.count == 1 ? .white : .systemBlue))
                if let texture = textures[slot] {
                    basic.color = .init(tint: .white, texture: .init(texture))
                }
                return basic
            }
            entity.components.set(model)
        }
        for child in entity.children { prepareDemoModelForRendering(child, textures: textures, accessory: accessory) }
    }
    func removeCurrentEffect(from arView: ARView) {
        modelTask?.cancel()
        modelTask = nil
        drummerPlayback?.stop()
        drummerPlayback = nil
        placeableModel = nil
        mediaPlane = nil
        dragOffset = nil
        faceGrid = nil
        faceCharacter = nil
        didAttemptFaceCharacter = false
        currentEffectID = nil
        guard let currentAnchor else { return }
        arView.scene.removeAnchor(currentAnchor)
        self.currentAnchor = nil
    }

    func updateFace(_ face: ARFaceAnchor) {
        guard let currentAnchor else { return }
        if currentEffectID == DemoEffect.yellowFace.id {
            if !didAttemptFaceCharacter {
                didAttemptFaceCharacter = true
                faceCharacter = try? AppleFaceCharacter()
                if let faceCharacter { currentAnchor.addChild(faceCharacter.entity) }
            }
            faceCharacter?.update(face)
            return
        }
        let isPainting = currentEffectID == DemoEffect.facePaint.id
        let isMime = currentEffectID == DemoEffect.mime.id || currentEffectID == DemoEffect.mimeAndHat.id
        guard currentEffectID == DemoEffect.faceGrid.id || isMime || (isPainting && painting != nil) else { return }
        let geometry = face.geometry
        if faceGrid == nil {
            let texture = isMime ? MimeEffect.makeup : (isPainting ? painting : nil)
            faceGrid = try? FaceGrid(geometry: geometry, painting: texture,
                                     opacity: isMime ? 1 : 0.85)
            if let faceGrid { currentAnchor.addChild(faceGrid.entity) }
        }
        faceGrid?.update(geometry)
    }
}
