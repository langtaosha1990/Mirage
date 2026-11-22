import ARKit
import RealityKit
import SceneKit
import UIKit

final class AppleFaceCharacter {
    let entity = Entity()
    private let jaw: Entity
    private let leftEye: Entity
    private let rightEye: Entity
    private let jawY: Float
    private let jawHeight: Float
    private let leftEyeDepth: Float
    private let rightEyeDepth: Float

    init() throws {
        guard let url = Bundle.main.url(forResource: "robotHead", withExtension: "scn") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let scene = try SCNScene(url: url)
        func part(_ name: String, color: UIColor) throws -> ModelEntity {
            guard let node = scene.rootNode.childNode(withName: name, recursively: true),
                  let geometry = node.geometry,
                  let positions = geometry.sources(for: .vertex).first,
                  let normals = geometry.sources(for: .normal).first,
                  let triangles = geometry.elements.first, triangles.primitiveType == .triangles else {
                throw CocoaError(.fileReadCorruptFile)
            }
            func vectors(_ source: SCNGeometrySource) -> [SIMD3<Float>] {
                source.data.withUnsafeBytes { bytes in
                    (0..<source.vectorCount).map { index in
                        let offset = source.dataOffset + index * source.dataStride
                        return SIMD3(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
                                     bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                                     bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
                    }
                }
            }
            let indices = triangles.data.withUnsafeBytes { bytes in
                (0..<(triangles.primitiveCount * 3)).map { index -> UInt32 in
                    let offset = index * triangles.bytesPerIndex
                    switch triangles.bytesPerIndex {
                    case 1: return UInt32(bytes.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                    case 2: return UInt32(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                    default: return bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                    }
                }
            }
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(vectors(positions))
            descriptor.normals = MeshBuffers.Normals(vectors(normals))
            descriptor.primitives = .triangles(indices)
            let part = ModelEntity(mesh: try MeshResource.generate(from: [descriptor]),
                                   materials: [SimpleMaterial(color: color, roughness: 0.65, isMetallic: false)])
            part.transform = Transform(matrix: node.simdWorldTransform)
            return part
        }
        let yellow = UIColor(red: 1, green: 0.79, blue: 0.12, alpha: 1)
        let head = try part("head", color: yellow)
        jaw = try part("jaw", color: yellow)
        leftEye = try part("eyeLeft", color: .systemTeal)
        rightEye = try part("eyeRight", color: .systemTeal)
        jawY = jaw.position.y
        jawHeight = jaw.visualBounds(relativeTo: nil).extents.y
        leftEyeDepth = leftEye.scale.z
        rightEyeDepth = rightEye.scale.z
        for part in [head, jaw, leftEye, rightEye] { entity.addChild(part) }
    }

    func update(_ face: ARFaceAnchor) {
        let shapes = face.blendShapes
        jaw.position.y = jawY - jawHeight * (shapes[.jawOpen]?.floatValue ?? 0)
        leftEye.scale.z = leftEyeDepth * max(0.05, 1 - (shapes[.eyeBlinkLeft]?.floatValue ?? 0))
        rightEye.scale.z = rightEyeDepth * max(0.05, 1 - (shapes[.eyeBlinkRight]?.floatValue ?? 0))
    }
}
