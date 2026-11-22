import RealityKit
import UIKit
import simd

struct SwimmingFish: Component {
    var velocity: SIMD3<Float>
}

struct FishSchoolSystem: System {
    private static let query = EntityQuery(where: .has(SwimmingFish.self))
    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        let fish = Array(context.entities(matching: Self.query, updatingSystemWhen: .rendering))
        let samples = fish.compactMap { entity -> (Entity, SIMD3<Float>, SIMD3<Float>)? in
            guard let state = entity.components[SwimmingFish.self] else { return nil }
            return (entity, entity.position, state.velocity)
        }
        let dt = min(Float(context.deltaTime), 0.05)
        for (entity, position, velocity) in samples {
            let center: SIMD3<Float> = [0, 0.28, 0]
            var force = (center - position) * 1.5
            var count: Float = 0
            var averageVelocity = SIMD3<Float>.zero
            var averageOffset = SIMD3<Float>.zero
            for (other, otherPosition, otherVelocity) in samples where other !== entity {
                let offset = otherPosition - position
                let distance = simd_length(offset)
                guard distance > 0.001, distance < 0.22 else { continue }
                count += 1
                averageOffset += offset
                averageVelocity += otherVelocity
                if distance < 0.075 { force -= offset / distance * (0.075 - distance) * 28 }
            }
            if count > 0 {
                force += (averageVelocity / count - velocity) * 1.4 + averageOffset / count * 0.7
            }
            let nextVelocity = velocity + force * dt
            let direction = simd_length(nextVelocity) > 0.001 ? simd_normalize(nextVelocity) : SIMD3<Float>(1, 0, 0)
            let speed = min(max(simd_length(nextVelocity), 0.10), 0.23)
            entity.position += direction * speed * dt
            entity.orientation = simd_quatf(from: [1, 0, 0], to: direction)
            entity.components.set(SwimmingFish(velocity: direction * speed))
        }
    }
}

enum OceanEffect {
    private static let register: Void = {
        SwimmingFish.registerComponent()
        FishSchoolSystem.registerSystem()
    }()

    static func prepare() { _ = register }

    static func makeAnchor() -> AnchorEntity {
        let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.18, 0.18]))
        let bodyMesh = MeshResource.generateSphere(radius: 0.036)
        let tailMesh = MeshResource.generateCone(height: 0.04, radius: 0.025)
        let eyeMesh = MeshResource.generateSphere(radius: 0.004)
        let eyeMaterial = UnlitMaterial(color: .black)
        let colors: [UIColor] = [.systemYellow, .systemCyan, .systemOrange]
        for index in 0..<14 {
            let root = Entity()
            let angle = Float(index) * 2.39996
            root.position = [cos(angle) * 0.20, 0.18 + Float(index % 4) * 0.06, sin(angle) * 0.20]
            root.components.set(SwimmingFish(velocity: [-sin(angle) * 0.16, 0, cos(angle) * 0.16]))
            let material = SimpleMaterial(color: colors[index % colors.count], roughness: 0.45, isMetallic: false)
            let body = ModelEntity(mesh: bodyMesh, materials: [material])
            body.scale = [1.25, 0.65, 0.35]
            root.addChild(body)
            let tail = ModelEntity(mesh: tailMesh, materials: [material])
            tail.scale = [0.28, 1, 0.9]
            tail.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
            tail.position.x = -0.053
            root.addChild(tail)
            for side: Float in [-1, 1] {
                let eye = ModelEntity(mesh: eyeMesh, materials: [eyeMaterial])
                eye.position = [0.026, 0.006, side * 0.010]
                root.addChild(eye)
            }
            anchor.addChild(root)
        }
        return anchor
    }
}
