import ARKit
import PencilKit
import AVFAudio
import RealityKit
import UIKit

final class ViewController: UIViewController {
    private let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private let effectEngine = EffectEngine()
    private let videoRecorder = VideoRecorder()
    private var pendingVideoURL: URL?
    private var needsSessionResume = false
    private var effects = DemoEffect.allCases
    private var selectedEffect: DemoEffect = .none
    private var cameraMode: CameraMode = .world
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private let maximumRecordingDuration: TimeInterval = 30
    private var isSwitchingEffect = false
    private var isStartingSession = false
    private var lastSessionRestartAt = Date.distantPast
    private let titleLabel = UILabel()
    private let modeBadge = PaddingLabel(insets: .init(top: 7, left: 12, bottom: 7, right: 12))
    private let hintLabel = PaddingLabel(insets: .init(top: 8, left: 12, bottom: 8, right: 12))
    private let effectStack = UIStackView()
    private let effectPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let captureButton = UIButton(type: .custom)
    private let recordInnerView = UIView()
    private let recordingLabel = PaddingLabel(insets: .init(top: 7, left: 11, bottom: 7, right: 11))
    private let flipButton = UIButton(type: .system)
    private let libraryButton = UIButton(type: .system)
    private let paintButton = UIButton(type: .system)
    private let animationButton = UIButton(type: .system)
    private let placementReticle = UIImageView(image: UIImage(systemName: "scope"))
    private var lastPlacementCheck: TimeInterval = 0
    private var faceDrawing = PKDrawing()
    private let unavailableView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        configureLifecycleObservers()
        arView.session.delegate = self
        requestCameraAndStart()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arView.session.pause()
        needsSessionResume = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if pendingVideoURL != nil {
            presentPendingVideo()
        } else if needsSessionResume, AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            startSession()
        }
    }

    private func configureLifecycleObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    private func configureUI() {
        OceanEffect.prepare()
        view.backgroundColor = UIColor(red: 0.025, green: 0.025, blue: 0.045, alpha: 1)
        arView.translatesAutoresizingMaskIntoConstraints = false
        // Plane-anchored effects do not require RealityKit's projective grounding pass.
        arView.renderOptions.formUnion([.disableMotionBlur, .disableGroundingShadows])
        view.addSubview(arView)
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(placeARModel(_:))))
        let moveModel = UIPanGestureRecognizer(target: self, action: #selector(moveARModel(_:)))
        moveModel.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(moveModel)
        arView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(scaleARModel(_:))))
        placementReticle.translatesAutoresizingMaskIntoConstraints = false
        placementReticle.tintColor = .systemMint
        placementReticle.isHidden = true
        arView.addSubview(placementReticle)
        NSLayoutConstraint.activate([
            placementReticle.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
            placementReticle.centerYAnchor.constraint(equalTo: arView.centerYAnchor),
            placementReticle.widthAnchor.constraint(equalToConstant: 32),
            placementReticle.heightAnchor.constraint(equalToConstant: 32)
        ])

        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.black.withAlphaComponent(0.72).cgColor, UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.82).cgColor]
        gradient.locations = [0, 0.42, 1]
        let overlay = GradientView(gradient: gradient)
        overlay.isUserInteractionEnabled = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)

        titleLabel.text = "MIRAGE"
        titleLabel.font = .systemFont(ofSize: 18, weight: .black)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        modeBadge.font = .systemFont(ofSize: 12, weight: .semibold)
        modeBadge.textColor = .white
        modeBadge.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        modeBadge.layer.cornerRadius = 15
        modeBadge.clipsToBounds = true
        modeBadge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeBadge)

        configureIconButton(flipButton, symbol: "arrow.triangle.2.circlepath.camera")
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        view.addSubview(flipButton)

        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = .white
        hintLabel.textAlignment = .center
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        hintLabel.layer.cornerRadius = 16
        hintLabel.clipsToBounds = true
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        configureRecordingLabel()
        view.addSubview(recordingLabel)
        configureEffectPanel()
        view.addSubview(effectPanel)
        configureCaptureButton()
        view.addSubview(captureButton)
        configureIconButton(libraryButton, symbol: "photo.on.rectangle")
        libraryButton.addTarget(self, action: #selector(showLibraryPlaceholder), for: .touchUpInside)
        view.addSubview(libraryButton)
        configureIconButton(paintButton, symbol: "paintbrush")
        paintButton.accessibilityLabel = "编辑面部彩绘"
        paintButton.isHidden = true
        paintButton.addTarget(self, action: #selector(editFacePainting), for: .touchUpInside)
        view.addSubview(paintButton)
        configureIconButton(animationButton, symbol: "play.fill")
        animationButton.isHidden = true
        animationButton.accessibilityLabel = "播放鼓手动画"
        animationButton.addTarget(self, action: #selector(toggleModelAnimation), for: .touchUpInside)
        view.addSubview(animationButton)
        configureUnavailableView()
        view.addSubview(unavailableView)

        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor), arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor), arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor), overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor), overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            modeBadge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor), modeBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            flipButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor), flipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flipButton.widthAnchor.constraint(equalToConstant: 44), flipButton.heightAnchor.constraint(equalToConstant: 44),
            recordingLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), recordingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), hintLabel.bottomAnchor.constraint(equalTo: effectPanel.topAnchor, constant: -15),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28), hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            effectPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), effectPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            effectPanel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -18), effectPanel.heightAnchor.constraint(equalToConstant: 108),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor), captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            captureButton.widthAnchor.constraint(equalToConstant: 76), captureButton.heightAnchor.constraint(equalToConstant: 76),
            libraryButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor), libraryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            libraryButton.widthAnchor.constraint(equalToConstant: 48), libraryButton.heightAnchor.constraint(equalToConstant: 48),
            paintButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            paintButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            paintButton.widthAnchor.constraint(equalToConstant: 48),
            paintButton.heightAnchor.constraint(equalToConstant: 48),
            animationButton.centerXAnchor.constraint(equalTo: paintButton.centerXAnchor),
            animationButton.centerYAnchor.constraint(equalTo: paintButton.centerYAnchor),
            animationButton.widthAnchor.constraint(equalToConstant: 48),
            animationButton.heightAnchor.constraint(equalToConstant: 48),
            unavailableView.centerXAnchor.constraint(equalTo: view.centerXAnchor), unavailableView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            unavailableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), unavailableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])
        updateModeUI()
    }

    private func configureEffectPanel() {
        effectPanel.layer.cornerRadius = 24
        effectPanel.clipsToBounds = true
        effectPanel.translatesAutoresizingMaskIntoConstraints = false
        let sectionLabel = UILabel()
        sectionLabel.text = "精选特效"
        sectionLabel.textColor = .white
        sectionLabel.font = .systemFont(ofSize: 13, weight: .bold)
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        effectPanel.contentView.addSubview(sectionLabel)
        effectStack.axis = .horizontal
        effectStack.distribution = .fillEqually
        effectStack.spacing = 10
        effectStack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        effectPanel.contentView.addSubview(scroll)
        scroll.addSubview(effectStack)
        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: effectPanel.contentView.topAnchor, constant: 12), sectionLabel.leadingAnchor.constraint(equalTo: effectPanel.contentView.leadingAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 7),
            scroll.leadingAnchor.constraint(equalTo: effectPanel.contentView.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: effectPanel.contentView.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: effectPanel.contentView.bottomAnchor, constant: -10),
            effectStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            effectStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            effectStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            effectStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            effectStack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }

    private func configureRecordingLabel() {
        recordingLabel.text = "● 00:00"
        recordingLabel.textColor = .white
        recordingLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        recordingLabel.backgroundColor = UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 0.9)
        recordingLabel.layer.cornerRadius = 15
        recordingLabel.clipsToBounds = true
        recordingLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingLabel.isHidden = true
    }

    private func reloadEffectButtons() {
        effectStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, effect) in effects.enumerated() {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: effect.symbol)
            configuration.title = effect.displayName
            configuration.imagePlacement = .top
            configuration.imagePadding = 5
            configuration.baseForegroundColor = effect == selectedEffect ? .black : .white
            configuration.background.backgroundColor = effect == selectedEffect ? .white : .clear
            configuration.background.cornerRadius = 17
            configuration.titleTextAttributesTransformer = .init { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 11, weight: .semibold)
                return outgoing
            }
            let button = UIButton(configuration: configuration)
            button.tag = index
            button.addTarget(self, action: #selector(selectEffect(_:)), for: .touchUpInside)
            effectStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 72).isActive = true
        }
    }

    private func configureCaptureButton() {
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        captureButton.layer.cornerRadius = 38
        captureButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        captureButton.layer.borderWidth = 6
        captureButton.layer.shadowColor = UIColor.black.cgColor
        captureButton.layer.shadowOpacity = 0.25
        captureButton.layer.shadowRadius = 12
        captureButton.accessibilityLabel = "开始录制"
        recordInnerView.isUserInteractionEnabled = false
        recordInnerView.backgroundColor = UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        recordInnerView.layer.cornerRadius = 27
        recordInnerView.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addSubview(recordInnerView)
        NSLayoutConstraint.activate([
            recordInnerView.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor), recordInnerView.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            recordInnerView.widthAnchor.constraint(equalToConstant: 54), recordInnerView.heightAnchor.constraint(equalToConstant: 54)
        ])
        captureButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
    }

    private func configureIconButton(_ button: UIButton, symbol: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 22
        button.setImage(UIImage(systemName: symbol), for: .normal)
    }

    private func configureUnavailableView() {
        unavailableView.layer.cornerRadius = 22
        unavailableView.clipsToBounds = true
        unavailableView.translatesAutoresizingMaskIntoConstraints = false
        unavailableView.isHidden = true
        let title = UILabel(); title.text = "需要相机权限"; title.font = .systemFont(ofSize: 20, weight: .bold); title.textColor = .white; title.textAlignment = .center
        let body = UILabel(); body.text = "Mirage 使用相机呈现并拍摄实时 AR 特效。"; body.font = .systemFont(ofSize: 14); body.textColor = UIColor.white.withAlphaComponent(0.76); body.textAlignment = .center; body.numberOfLines = 0
        let settings = UIButton(type: .system); settings.setTitle("前往设置", for: .normal); settings.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold); settings.tintColor = .white; settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, body, settings]); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        unavailableView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: unavailableView.contentView.topAnchor, constant: 24), stack.leadingAnchor.constraint(equalTo: unavailableView.contentView.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: unavailableView.contentView.trailingAnchor, constant: -22), stack.bottomAnchor.constraint(equalTo: unavailableView.contentView.bottomAnchor, constant: -20)])
    }

    private func requestCameraAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { granted ? self?.startSession() : self?.showCameraUnavailable() }
            }
        default: showCameraUnavailable()
        }
    }

    private func startSession() {
        guard !isStartingSession else { return }
        needsSessionResume = false
        isStartingSession = true
        unavailableView.isHidden = true
        effectEngine.removeCurrentEffect(from: arView)
        let didStart = cameraMode == .world ? effectEngine.runWorldTracking(in: arView) : effectEngine.runFaceTracking(in: arView)
        if !didStart {
            cameraMode = .world
            _ = effectEngine.runWorldTracking(in: arView)
            showToast("当前设备不支持面部追踪，已切换至空间模式")
        }
        applySelectedEffect()
        updateModeUI()
        captureButton.isEnabled = true
        lastSessionRestartAt = Date()
        isStartingSession = false
    }

    private func applySelectedEffect() {
        animationButton.isHidden = true
        placementReticle.isHidden = true
        paintButton.isHidden = selectedEffect != .facePaint
        guard selectedEffect.supports(cameraMode) else { selectedEffect = .none; reloadEffectButtons(); return }
        effectEngine.apply(selectedEffect, to: arView, mode: cameraMode)
        hintLabel.text = selectedEffect.hint(for: cameraMode)
    }

    @objc private func placeARModel(_ gesture: UITapGestureRecognizer) {
        if effectEngine.advancePlacedImage() { return }
        guard effectEngine.canPlaceModel, !effectEngine.hasPlacedModel,
              let transform = effectEngine.placementTransform(at: gesture.location(in: arView), in: arView) else { return }
        effectEngine.placeModel(at: transform, in: arView)
        if selectedEffect == .handshake {
            animationButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
            animationButton.accessibilityLabel = "切换下一张图片"
            animationButton.isHidden = false
        }
        if selectedEffect == .drummer {
            animationButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            animationButton.accessibilityLabel = "播放鼓手动画"
            animationButton.isHidden = false
        }
    }

    @objc private func toggleModelAnimation() {
        if effectEngine.advancePlacedImage() { return }
        guard selectedEffect == .drummer, effectEngine.toggleDrummerAnimation() else {
            showToast("鼓手模型未加载到可播放的动画")
            return
        }
        let playing = effectEngine.isDrummerPlaying
        animationButton.setImage(UIImage(systemName: playing ? "stop.fill" : "play.fill"), for: .normal)
        animationButton.accessibilityLabel = playing ? "停止鼓手动画" : "播放鼓手动画"
    }

    @objc private func moveARModel(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: arView)
        switch gesture.state {
        case .began: effectEngine.beginModelDrag(at: point, in: arView)
        case .changed: effectEngine.updateModelDrag(at: point, in: arView)
        case .ended, .cancelled, .failed: effectEngine.endModelDrag()
        default: break
        }
    }

    @objc private func scaleARModel(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        effectEngine.resizeModel(by: Float(gesture.scale))
        gesture.scale = 1
    }

    private func updateModeUI() {
        modeBadge.text = cameraMode == .world ? "空间 AR" : "自拍"
        effects = DemoEffect.allCases.filter { $0.supports(cameraMode) }
        reloadEffectButtons()
        hintLabel.text = selectedEffect.hint(for: cameraMode)
    }

    private func showCameraUnavailable() { unavailableView.isHidden = false; captureButton.isEnabled = false }
    @objc private func flipCamera() {
        guard !videoRecorder.isRecording else { return }
        cameraMode = cameraMode == .world ? .selfie : .world; selectedEffect = .none; startSession()
    }
    @objc private func selectEffect(_ sender: UIButton) {
        guard !videoRecorder.isRecording, !isSwitchingEffect, effects.indices.contains(sender.tag) else { return }
        let nextEffect = effects[sender.tag]
        if nextEffect == selectedEffect {
            _ = effectEngine.advancePlacedImage()
            return
        }
        isSwitchingEffect = true
        effectStack.isUserInteractionEnabled = false
        selectedEffect = nextEffect
        reloadEffectButtons()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applySelectedEffect()
            self.effectStack.isUserInteractionEnabled = true
            self.isSwitchingEffect = false
        }
    }
    @objc private func toggleRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        videoRecorder.isRecording ? stopVideoRecording() : requestMicrophoneAndRecord()
    }

    private func requestMicrophoneAndRecord() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startVideoRecording(microphoneEnabled: true)
        case .denied:
            showToast("麦克风未授权，将录制无声视频")
            startVideoRecording(microphoneEnabled: false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async { self?.startVideoRecording(microphoneEnabled: granted) }
            }
        @unknown default:
            startVideoRecording(microphoneEnabled: false)
        }
    }

    private func startVideoRecording(microphoneEnabled: Bool) {
        captureButton.isEnabled = false
        videoRecorder.start(arView: arView, microphoneEnabled: microphoneEnabled) { [weak self] result in
            guard let self else { return }
            self.captureButton.isEnabled = true
            switch result {
            case .success:
                self.recordingStartedAt = Date()
                self.setRecordingUI(active: true)
                self.recordingTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.updateRecordingTime), userInfo: nil, repeats: true)
            case .failure(let error):
                self.showToast(error.localizedDescription)
            }
        }
    }

    private func stopVideoRecording() {
        guard videoRecorder.isRecording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        captureButton.isEnabled = false
        recordingLabel.text = "正在处理…"
        videoRecorder.stop { [weak self] result in
            guard let self else { return }
            self.captureButton.isEnabled = true
            self.setRecordingUI(active: false)
            switch result {
            case .success(let url):
                self.pendingVideoURL = url
                self.presentPendingVideo()
            case .failure(let error):
                self.showToast(error.localizedDescription)
            }
        }
    }

    private func presentPendingVideo() {
        guard let url = pendingVideoURL, view.window != nil,
              UIApplication.shared.applicationState == .active,
              presentedViewController == nil else { return }
        pendingVideoURL = nil
        let controller = VideoPreviewViewController(videoURL: url)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    @objc private func updateRecordingTime() {
        guard let recordingStartedAt else { return }
        let elapsed = Date().timeIntervalSince(recordingStartedAt)
        recordingLabel.text = String(format: "● %02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
        if elapsed >= maximumRecordingDuration { stopVideoRecording() }
    }

    private func setRecordingUI(active: Bool) {
        paintButton.isEnabled = !active
        recordingLabel.isHidden = !active
        effectPanel.alpha = active ? 0.35 : 1
        flipButton.isEnabled = !active
        libraryButton.isEnabled = !active
        effectStack.isUserInteractionEnabled = !active
        recordInnerView.layer.cornerRadius = active ? 7 : 27
        recordInnerView.transform = active ? CGAffineTransform(scaleX: 0.48, y: 0.48) : .identity
        captureButton.accessibilityLabel = active ? "停止录制" : "开始录制"
    }

    @objc private func editFacePainting() {
        guard selectedEffect == .facePaint, !videoRecorder.isRecording else { return }
        let editor = FacePaintEditor()
        editor.drawing = faceDrawing
        editor.onApply = { [weak self] drawing, image in
            self?.faceDrawing = drawing
            self?.effectEngine.setFacePainting(image)
        }
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }
    @objc private func showLibraryPlaceholder() { showToast("作品库将在下一阶段接入") }
    @objc private func openSettings() { guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url) }
    @objc private func appWillResignActive() {
        if videoRecorder.isRecording { stopVideoRecording() }
        arView.session.pause()
    }
    @objc private func appDidBecomeActive() {
        if pendingVideoURL != nil {
            presentPendingVideo()
            return
        }
        guard presentedViewController == nil else { return }
        guard view.window != nil, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        startSession()
    }

    private func showToast(_ message: String) {
        let toast = PaddingLabel(insets: .init(top: 10, left: 16, bottom: 10, right: 16))
        toast.text = message; toast.textColor = .white; toast.font = .systemFont(ofSize: 13, weight: .medium); toast.textAlignment = .center; toast.numberOfLines = 0
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.72); toast.layer.cornerRadius = 18; toast.clipsToBounds = true; toast.alpha = 0; toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([toast.centerXAnchor.constraint(equalTo: view.centerXAnchor), toast.centerYAnchor.constraint(equalTo: view.centerYAnchor), toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32), toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)])
        UIView.animate(withDuration: 0.2, animations: { toast.alpha = 1 }) { _ in UIView.animate(withDuration: 0.25, delay: 1.6, options: []) { toast.alpha = 0 } completion: { _ in toast.removeFromSuperview() } }
    }
}

extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard selectedEffect.usesManualPlacement, frame.timestamp - lastPlacementCheck > 0.12 else { return }
        lastPlacementCheck = frame.timestamp
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let canPlace = effectEngine.canPlaceModel && effectEngine.placementTransform(at: center, in: arView) != nil
        placementReticle.isHidden = !canPlace || effectEngine.hasPlacedModel
        if case .normal = frame.camera.trackingState {
            let placedHint = selectedEffect == .handshake ? "轻点切图 · 拖动移位 · 双指缩放" : "单指移动 · 双指缩放"
            hintLabel.text = effectEngine.hasPlacedModel ? placedHint
                : (canPlace ? "点击平面放置模型" : selectedEffect.hint(for: cameraMode))
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard cameraMode == .selfie, selectedEffect.usesFaceUpdates,
              let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first(where: \.isTracked) else { return }
        effectEngine.updateFace(face)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard cameraMode == .world else { return }
        switch camera.trackingState {
        case .normal:
            hintLabel.text = selectedEffect.hint(for: cameraMode)
        case .notAvailable:
            hintLabel.text = "当前设备暂时无法进行空间追踪"
        case .limited(let reason):
            switch reason {
            case .initializing: hintLabel.text = "正在了解周围空间…"
            case .excessiveMotion: hintLabel.text = "请缓慢移动手机"
            case .insufficientFeatures: hintLabel.text = "请对准纹理更丰富的区域"
            case .relocalizing: hintLabel.text = "正在恢复空间位置…"
            @unknown default: hintLabel.text = "正在准备空间特效…"
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard !videoRecorder.isRecording, Date().timeIntervalSince(lastSessionRestartAt) > 1.5 else { return }
        showToast("AR 会话出现问题，正在恢复")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.startSession()
        }
    }
}

private final class PaddingLabel: UILabel {
    let insets: UIEdgeInsets
    init(insets: UIEdgeInsets) { self.insets = insets; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize { let base = super.intrinsicContentSize; return .init(width: base.width + insets.left + insets.right, height: base.height + insets.top + insets.bottom) }
}

private final class GradientView: UIView {
    private let gradient: CAGradientLayer
    init(gradient: CAGradientLayer) { self.gradient = gradient; super.init(frame: .zero); layer.addSublayer(gradient) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}
