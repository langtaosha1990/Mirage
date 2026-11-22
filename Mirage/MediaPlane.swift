import Foundation
import RealityKit

final class MediaPlane {
    let root = Entity()
    private let panels: [ModelEntity]
    private var index = 0

    private init(aspectRatio: Float, height: Float, first: UnlitMaterial, remaining: [UnlitMaterial]) {
        let mesh = MeshResource.generatePlane(width: height * aspectRatio, height: height)
        panels = ([first] + remaining).enumerated().map { index, material in
            let panel = ModelEntity(mesh: mesh, materials: [material])
            panel.position.y = height / 2
            panel.isEnabled = index == 0
            panel.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: false))
            panel.components.set(DynamicLightShadowComponent(castsShadow: false))
            return panel
        }
        for panel in panels { root.addChild(panel) }
    }

    func advance() {
        panels[index].isEnabled = false
        index = (index + 1) % panels.count
        panels[index].isEnabled = true
    }

    static func handshake() async throws -> MediaPlane {
        func loadSlide(_ name: String) async throws -> UnlitMaterial {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let texture = try await TextureResource(contentsOf: url)
            var material = UnlitMaterial()
            material.color = .init(texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            return material
        }
        let first = try await loadSlide("handshake-mime")
        let side = try await loadSlide("handshake-mime-side")
        return MediaPlane(aspectRatio: 0.5, height: 1.65, first: first, remaining: [side])
    }
}
