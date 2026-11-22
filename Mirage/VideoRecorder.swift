@preconcurrency import AVFoundation
import RealityKit
import CoreImage
import Metal
import UIKit

@MainActor
final class VideoRecorder: NSObject {
    enum RecorderError: LocalizedError {
        case invalidSize, writerCreationFailed, noFrames

        var errorDescription: String? {
            switch self {
            case .invalidSize: "渲染画面尺寸无效"
            case .writerCreationFailed: "无法创建视频编码器"
            case .noFrames: "没有采集到可用的视频画面"
            }
        }
    }

    private weak var arView: ARView?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var capture: RenderFrameCapture?
    private var audioRecorder: AVAudioRecorder?
    private var audioURL: URL?
    private var videoURL: URL?
    private let encodingQueue = DispatchQueue(label: "com.mirage.video-encoding", qos: .userInitiated)
    private(set) var isRecording = false

    func start(arView: ARView, microphoneEnabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard writer == nil else { completion(.failure(RecorderError.writerCreationFailed)); return }
        let scale = arView.window?.windowScene?.screen.nativeScale ?? arView.traitCollection.displayScale
        let rawWidth = Int(arView.bounds.width * scale)
        let rawHeight = Int(arView.bounds.height * scale)
        let downscale = min(1, 960 / Double(max(rawWidth, rawHeight)))
        let scaledWidth = Int(Double(rawWidth) * downscale)
        let scaledHeight = Int(Double(rawHeight) * downscale)
        let width = scaledWidth - scaledWidth % 2
        let height = scaledHeight - scaledHeight % 2
        guard width > 0, height > 0 else { completion(.failure(RecorderError.invalidSize)); return }

        do {
            let url = temporaryURL(extension: "mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: min(14_000_000, width * height * 5),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 20
            ]
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
            guard writer.canAdd(input) else { throw RecorderError.writerCreationFailed }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? RecorderError.writerCreationFailed }
            writer.startSession(atSourceTime: .zero)

            self.arView = arView
            self.writer = writer
            self.videoInput = input
            self.pixelBufferAdaptor = adaptor
            self.videoURL = url
            guard let pool = adaptor.pixelBufferPool else { throw RecorderError.writerCreationFailed }
            if microphoneEnabled { startMicrophoneRecording() }
            let capture = RenderFrameCapture(pool: pool, input: input, adaptor: adaptor, queue: encodingQueue)
            self.capture = capture
            isRecording = true
            arView.renderCallbacks.postProcess = capture.render
            completion(.success(()))
        } catch {
            reset()
            completion(.failure(error))
        }
    }

    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        guard isRecording, let writer, let videoInput, let videoURL else { return }
        isRecording = false
        arView?.renderCallbacks.postProcess = nil
        let capture = self.capture
        capture?.stopAcceptingFrames()
        if audioRecorder != nil {
            audioRecorder?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        let finish: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            guard capture?.frameCount ?? 0 > 0, writer.status == .writing else {
                let error = writer.error ?? RecorderError.noFrames
                writer.cancelWriting()
                DispatchQueue.main.async { self.reset(); completion(.failure(error)) }
                return
            }
            videoInput.markAsFinished()
            writer.finishWriting {
                let writerError = writer.error
                DispatchQueue.main.async {
                    guard writer.status == .completed, writerError == nil else {
                        self.reset()
                        completion(.failure(writerError ?? RecorderError.writerCreationFailed))
                        return
                    }
                    Task { @MainActor in
                        do {
                            try await self.validateVideo(at: videoURL)
                        } catch {
                            self.reset()
                            completion(.failure(error))
                            return
                        }
                        if let audioURL = self.audioURL {
                            self.merge(videoURL: videoURL, audioURL: audioURL) { result in
                                let playableURL = (try? result.get()) ?? videoURL
                                self.reset(keeping: playableURL)
                                completion(.success(playableURL))
                            }
                        } else {
                            self.reset(keeping: videoURL)
                            completion(.success(videoURL))
                        }
                    }
                }
            }
        }
        if let capture {
            capture.pending.notify(queue: encodingQueue, execute: finish)
        } else {
            encodingQueue.async(execute: finish)
        }
    }

    private func startMicrophoneRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .videoRecording, options: [.allowBluetoothHFP])
            try session.setActive(true)
            let url = temporaryURL(extension: "m4a")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            recorder.record()
            audioURL = url
            audioRecorder = recorder
        } catch {
            audioURL = nil
            audioRecorder = nil
        }
    }

    private func merge(videoURL: URL, audioURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        Task {
            do {
                let videoAsset = AVURLAsset(url: videoURL)
                let audioAsset = AVURLAsset(url: audioURL)
                let duration = try await videoAsset.load(.duration)
                guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first else { throw RecorderError.noFrames }
                let composition = AVMutableComposition()
                let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                try videoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
                videoTrack?.preferredTransform = try await sourceVideo.load(.preferredTransform)
                if let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
                   let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    let audioDuration = try await audioAsset.load(.duration)
                    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: sourceAudio, at: .zero)
                }
                let output = temporaryURL(extension: "mov")
                guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw RecorderError.writerCreationFailed }
                try await exporter.export(to: output, as: .mov)
                completion(.success(output))
            } catch { completion(.failure(error)) }
        }
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mirage-\(UUID().uuidString)").appendingPathExtension(pathExtension)
    }

    private func validateVideo(at url: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.maximumSize = CGSize(width: 160, height: 160)
        _ = try await generator.image(at: .zero)
    }

    private func reset(keeping keptURL: URL? = nil) {
        [videoURL, audioURL].compactMap { $0 }.filter { $0 != keptURL }.forEach { try? FileManager.default.removeItem(at: $0) }
        capture = nil
        writer = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        audioRecorder = nil
        audioURL = nil
        videoURL = nil
        arView = nil
        isRecording = false
    }
}

// Admission is locked across the render and UI threads. Writer access and frameCount
// are confined to the encoding queue after setup.
nonisolated private final class RenderFrameCapture: @unchecked Sendable {
    let pending = DispatchGroup()
    private let lock = NSLock()
    private let pool: CVPixelBufferPool
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let queue: DispatchQueue
    private let startedAt = CACurrentMediaTime()
    private var firstWrittenTime: CMTime?
    private var accepting = true
    private var busy = false
    private var lastFrameTime = -1.0
    private var cache: CVMetalTextureCache?
    private var imageContext: CIContext?
    private(set) var frameCount = 0

    init(pool: CVPixelBufferPool, input: AVAssetWriterInput,
         adaptor: AVAssetWriterInputPixelBufferAdaptor, queue: DispatchQueue) {
        self.pool = pool
        self.input = input
        self.adaptor = adaptor
        self.queue = queue
    }

    func stopAcceptingFrames() {
        lock.lock()
        accepting = false
        lock.unlock()
    }

    func render(_ context: ARView.PostProcessContext) {
        if let blit = context.commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
            blit.endEncoding()
        }

        let elapsed = CACurrentMediaTime() - startedAt
        lock.lock()
        guard accepting, !busy, elapsed - lastFrameTime >= 1.0 / 31 else {
            lock.unlock()
            return
        }
        busy = true
        lastFrameTime = elapsed
        pending.enter()
        lock.unlock()

        if cache == nil {
            CVMetalTextureCacheCreate(nil, nil, context.device, nil, &cache)
            imageContext = CIContext(mtlDevice: context.device, options: [.cacheIntermediates: false])
        }
        var buffer: CVPixelBuffer?
        guard let cache, let imageContext,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer, let image = CIImage(mtlTexture: context.sourceColorTexture) else {
            releaseFrame()
            return
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var metalBuffer: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                                                        width, height, 0, &metalBuffer) == kCVReturnSuccess,
              let metalBuffer, let destination = CVMetalTextureGetTexture(metalBuffer) else {
            releaseFrame()
            return
        }

        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: CGFloat(width) / image.extent.width,
            y: CGFloat(height) / image.extent.height
        ))
        imageContext.render(scaled, to: destination, commandBuffer: context.commandBuffer,
                            bounds: CGRect(x: 0, y: 0, width: width, height: height),
                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let time = CMTime(seconds: elapsed, preferredTimescale: 600)
        context.commandBuffer.addCompletedHandler { command in
            let succeeded = command.status == .completed
            self.queue.async {
                defer { self.releaseFrame() }
                withExtendedLifetime(metalBuffer) {
                    guard succeeded, self.input.isReadyForMoreMediaData else { return }
                    let origin = self.firstWrittenTime ?? time
                    if self.adaptor.append(buffer, withPresentationTime: time - origin) {
                        self.firstWrittenTime = origin
                        self.frameCount += 1
                    }
                }
            }
        }
    }

    private func releaseFrame() {
        lock.lock()
        busy = false
        pending.leave()
        lock.unlock()
    }
}
