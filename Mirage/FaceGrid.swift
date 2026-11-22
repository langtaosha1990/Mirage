import ARKit
import RealityKit
import UIKit

final class FaceGrid {
    private struct Vertex {
        var position: SIMD3<Float>
        var uv: SIMD2<Float>
    }

    let entity: ModelEntity
    private let mesh: LowLevelMesh
    private let flipTextureVertically: Bool

    init(geometry: ARFaceGeometry, painting: CGImage? = nil, opacity: Float = 0.85,
         flipTextureVertically: Bool = false) throws {
        let indices = geometry.triangleIndices
        guard !geometry.vertices.isEmpty, !indices.isEmpty, indices.count.isMultiple(of: 3),
              geometry.textureCoordinates.count == geometry.vertices.count,
              indices.allSatisfy({ geometry.vertices.indices.contains(Int($0)) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = geometry.vertices.count
        descriptor.indexCapacity = geometry.triangleIndices.count
        descriptor.indexType = .uint16
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Vertex>.offset(of: \.uv)!)
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableIndices { bytes in
            indices.withUnsafeBytes { bytes.copyMemory(from: $0) }
        }
        mesh.parts.replaceAll([.init(indexOffset: 0, indexCount: indices.count, topology: .triangle,
                                     bounds: BoundingBox(min: SIMD3(repeating: -0.3), max: SIMD3(repeating: 0.3)))])
        let texture: TextureResource
        if let painting {
            texture = try TextureResource.generate(from: painting, options: .init(semantic: .color))
        } else if let url = Bundle.main.url(forResource: "wireframeTexture", withExtension: "png") {
            texture = try TextureResource.load(contentsOf: url)
        } else {
            let coordinates = geometry.textureCoordinates
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
                UIColor.cyan.setStroke()
                context.cgContext.setLineWidth(1.4)
                func point(_ index: Int) -> CGPoint {
                    let uv = coordinates[Int(indices[index])]
                    return CGPoint(x: CGFloat(uv.x) * 512, y: (1 - CGFloat(uv.y)) * 512)
                }
                for start in stride(from: 0, to: indices.count, by: 3) {
                    context.cgContext.addLines(between: [point(start), point(start + 1), point(start + 2), point(start)])
                    context.cgContext.strokePath()
                }
            }
            guard let cgImage = image.cgImage else { throw CocoaError(.fileReadCorruptFile) }
            texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        }
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        self.mesh = mesh
        self.flipTextureVertically = flipTextureVertically
        entity = ModelEntity(mesh: try MeshResource(from: mesh), materials: [material])
        update(geometry)
    }

    func update(_ geometry: ARFaceGeometry) {
        let positions = geometry.vertices
        let uv = geometry.textureCoordinates
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let vertices = bytes.bindMemory(to: Vertex.self)
            for index in positions.indices {
                let textureUV = SIMD2(uv[index].x, flipTextureVertically ? 1 - uv[index].y : uv[index].y)
                vertices[index] = Vertex(position: positions[index] + [0, 0, 0.001], uv: textureUV)
            }
        }
    }
}
