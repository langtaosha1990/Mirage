import RealityKit
import UIKit

enum MimeEffect {
    static let makeup: CGImage? = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { renderer in
            let context = renderer.cgContext
            func softOval(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: UIColor, fade: CGFloat = 0.7) {
                context.saveGState()
                context.translateBy(x: x * 512, y: y * 512)
                context.scaleBy(x: width * 256, y: height * 256)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: [color.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                                             locations: [0, fade, 1]) {
                    context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                               endCenter: .zero, endRadius: 1, options: [])
                }
                context.restoreGState()
            }
            softOval(x: 0.5, y: 0.47, width: 0.64, height: 0.90,
                     color: UIColor(white: 0.98, alpha: 0.84), fade: 0.70)
            for x: CGFloat in [0.32, 0.68] {
                softOval(x: x, y: 0.48, width: 0.16, height: 0.18,
                         color: UIColor(red: 0.83, green: 0.34, blue: 0.38, alpha: 0.58), fade: 0.15)
            }
            UIColor(white: 0.06, alpha: 1).setFill()
            for side: CGFloat in [-1, 1] {
                let brow = UIBezierPath()
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: (0.5 + side * x) * 512, y: y * 512)
                }
                brow.move(to: point(0.055, 0.319))
                brow.addQuadCurve(to: point(0.228, 0.356), controlPoint: point(0.13, 0.255))
                brow.addQuadCurve(to: point(0.055, 0.319), controlPoint: point(0.136, 0.292))
                brow.fill()
                for (center, height) in [(0.367, 0.072), (0.414, 0.054)] {
                    softOval(x: 0.5 + side * 0.146, y: center, width: 0.131, height: height,
                             color: UIColor(white: 0.055, alpha: 0.90), fade: 0.52)
                }
            }
            let lips = UIBezierPath()
            lips.move(to: CGPoint(x: 204, y: 312))
            lips.addCurve(to: CGPoint(x: 256, y: 292), controlPoint1: CGPoint(x: 224, y: 298), controlPoint2: CGPoint(x: 241, y: 283))
            lips.addCurve(to: CGPoint(x: 308, y: 312), controlPoint1: CGPoint(x: 271, y: 283), controlPoint2: CGPoint(x: 288, y: 298))
            lips.addQuadCurve(to: CGPoint(x: 204, y: 312), controlPoint: CGPoint(x: 256, y: 305))
            lips.close()
            lips.move(to: CGPoint(x: 204, y: 312))
            lips.addQuadCurve(to: CGPoint(x: 308, y: 312), controlPoint: CGPoint(x: 256, y: 347))
            lips.addQuadCurve(to: CGPoint(x: 204, y: 312), controlPoint: CGPoint(x: 256, y: 370))
            lips.close()
            lips.fill()
        }.cgImage
    }()

    static func addHat(to anchor: AnchorEntity) {
        let felt = SimpleMaterial(color: UIColor(white: 0.055, alpha: 1), roughness: 0.92, isMetallic: false)
        let ribbon = SimpleMaterial(color: UIColor(white: 0.14, alpha: 1), roughness: 0.72, isMetallic: false)
        let hat = Entity()
        hat.position = [0, 0.097, -0.008]
        hat.scale = [0.84, 0.78, 0.85]
        hat.orientation = simd_quatf(angle: -0.035, axis: [0, 0, 1])
        let brim = ModelEntity(mesh: .generateSphere(radius: 0.108), materials: [felt])
        brim.scale = [1, 0.095, 0.84]
        let crown = ModelEntity(mesh: .generateSphere(radius: 0.085), materials: [felt])
        crown.scale = [1, 0.79, 0.84]
        crown.position.y = 0.041
        let band = ModelEntity(mesh: .generateCylinder(height: 0.015, radius: 0.079), materials: [ribbon])
        band.scale.z = 0.85
        band.position.y = 0.017
        for part in [brim, crown, band] { hat.addChild(part) }
        anchor.addChild(hat)
    }
}
