import Photos
import UIKit

final class CapturePreviewViewController: UIViewController {
    private let image: UIImage
    private let imageView = UIImageView()
    private let saveButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    init(image: UIImage) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        let closeButton = makeIconButton(symbol: "xmark")
        closeButton.accessibilityLabel = "重拍"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(closeButton)

        configureActionButton(saveButton, title: "保存", symbol: "square.and.arrow.down")
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        configureActionButton(shareButton, title: "分享", symbol: "square.and.arrow.up")
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [saveButton, shareButton])
        actions.axis = .horizontal
        actions.spacing = 12
        actions.distribution = .fillEqually
        actions.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actions)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor), imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor), imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), closeButton.widthAnchor.constraint(equalToConstant: 44), closeButton.heightAnchor.constraint(equalToConstant: 44),
            actions.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), actions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            actions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18), actions.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func makeIconButton(symbol: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 22
        button.setImage(UIImage(systemName: symbol), for: .normal)
        return button
    }

    private func configureActionButton(_ button: UIButton, title: String, symbol: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.94)
        configuration.baseForegroundColor = .black
        configuration.cornerStyle = .capsule
        button.configuration = configuration
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func save() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.presentMessage(title: "无法保存", message: "请在系统设置中允许 Mirage 添加照片。") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: self.image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    self.presentMessage(title: success ? "已保存" : "保存失败", message: success ? "照片已添加到系统照片。" : "请稍后重试。")
                }
            }
        }
    }

    @objc private func share() {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = controller.popoverPresentationController { popover.sourceView = shareButton; popover.sourceRect = shareButton.bounds }
        present(controller, animated: true)
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
