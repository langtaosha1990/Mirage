import AVFoundation
import Photos
import UIKit

final class VideoPreviewViewController: UIViewController {
    private let videoURL: URL
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private let saveButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private var playbackObserver: NSObjectProtocol?
    private var playbackStatus: NSKeyValueObservation?

    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        configurePlayback()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            player.isMuted = true
        }
        player.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }

    deinit {
        if let playbackObserver { NotificationCenter.default.removeObserver(playbackObserver) }
        try? FileManager.default.removeItem(at: videoURL)
    }

    private func configureUI() {
        view.backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)

        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.black.withAlphaComponent(0.6).cgColor, UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.75).cgColor]
        gradient.locations = [0, 0.45, 1]
        let shade = PreviewGradientView(gradient: gradient)
        shade.translatesAutoresizingMaskIntoConstraints = false
        shade.isUserInteractionEnabled = false
        view.addSubview(shade)

        let closeButton = makeIconButton(symbol: "xmark")
        closeButton.accessibilityLabel = "重拍"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(closeButton)

        let title = UILabel()
        title.text = "视频预览"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

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
            shade.topAnchor.constraint(equalTo: view.topAnchor), shade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shade.trailingAnchor.constraint(equalTo: view.trailingAnchor), shade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44), closeButton.heightAnchor.constraint(equalToConstant: 44),
            title.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor), title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actions.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), actions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            actions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18), actions.heightAnchor.constraint(equalToConstant: 54)
        ])
    }

    private func configurePlayback() {
        let item = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: item)
        playerLayer.player = player
        playbackStatus = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "无法解码这段视频，请重新录制。"
            DispatchQueue.main.async {
                guard let self, self.view.window != nil else { return }
                self.presentMessage(title: "视频无法播放", message: message)
            }
        }
        playbackObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
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
        configuration.baseBackgroundColor = title == "分享" ? UIColor(red: 0.66, green: 0.47, blue: 1, alpha: 1) : UIColor.white.withAlphaComponent(0.94)
        configuration.baseForegroundColor = title == "分享" ? .white : .black
        configuration.cornerStyle = .capsule
        button.configuration = configuration
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func save() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.presentMessage(title: "无法保存", message: "请在系统设置中允许 Mirage 添加视频。") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.videoURL)
            } completionHandler: { success, _ in
                DispatchQueue.main.async { self.presentMessage(title: success ? "已保存" : "保存失败", message: success ? "视频已添加到系统照片。" : "请稍后重试。") }
            }
        }
    }

    @objc private func share() {
        let controller = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        if let popover = controller.popoverPresentationController { popover.sourceView = shareButton; popover.sourceRect = shareButton.bounds }
        present(controller, animated: true)
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

private final class PreviewGradientView: UIView {
    private let gradient: CAGradientLayer
    init(gradient: CAGradientLayer) { self.gradient = gradient; super.init(frame: .zero); layer.addSublayer(gradient) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}
