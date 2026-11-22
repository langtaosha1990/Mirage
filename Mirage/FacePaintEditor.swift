import PencilKit
import UIKit

final class FacePaintEditor: UIViewController {
    var drawing = PKDrawing()
    var onApply: ((PKDrawing, CGImage?) -> Void)?
    private let canvas = PKCanvasView()
    private let guide = UIImageView(image: UIImage(named: "wireframeTexture"))
    private let colors: [UIColor] = [.systemPink, .systemTeal, .systemYellow, .white]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "面部彩绘"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "应用", style: .done, target: self, action: #selector(apply))
        guide.alpha = 0.35
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.monoline, color: colors[0], width: 12)
        let palette = UIStackView()
        palette.spacing = 8
        palette.distribution = .fillEqually
        for (index, name) in ["粉", "青", "黄", "白", "擦除", "清空"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.tag = index
            button.addTarget(self, action: #selector(selectTool(_:)), for: .touchUpInside)
            palette.addArrangedSubview(button)
        }
        for child in [guide, canvas, palette] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        let safe = view.safeAreaLayoutGuide
        let preferredWidth = canvas.widthAnchor.constraint(equalToConstant: 512)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            canvas.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            canvas.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -32),
            preferredWidth, canvas.heightAnchor.constraint(equalTo: canvas.widthAnchor),
            guide.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            guide.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            guide.topAnchor.constraint(equalTo: canvas.topAnchor),
            guide.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            palette.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 12),
            palette.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            palette.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            palette.heightAnchor.constraint(equalToConstant: 44),
            palette.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -8)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard canvas.bounds.width > 0, canvas.bounds.width != canvasWidth else { return }
        let oldWidth = canvasWidth
        canvasWidth = canvas.bounds.width
        let scale = canvasWidth / (oldWidth > 0 ? oldWidth : 512)
        canvas.drawing = (oldWidth > 0 ? canvas.drawing : drawing)
            .transformed(using: CGAffineTransform(scaleX: scale, y: scale))
    }

    private var canvasWidth: CGFloat = 0

    @objc private func selectTool(_ button: UIButton) {
        switch button.tag {
        case 0..<colors.count: canvas.tool = PKInkingTool(.monoline, color: colors[button.tag], width: 12)
        case 4: canvas.tool = PKEraserTool(.vector)
        default: canvas.drawing = PKDrawing()
        }
    }

    @objc private func apply() {
        guard canvasWidth > 0 else { return }
        let scale = 512 / canvasWidth
        let normalized = canvas.drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        let image = normalized.strokes.isEmpty ? nil : normalized.image(from: CGRect(x: 0, y: 0, width: 512, height: 512), scale: 1).cgImage
        onApply?(normalized, image)
        dismiss(animated: true)
    }

    @objc private func cancel() { dismiss(animated: true) }
}
