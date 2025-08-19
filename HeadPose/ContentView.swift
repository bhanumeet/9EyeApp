import SwiftUI
import AVFoundation
import UIKit
import TensorFlowLite
import CoreImage
import Accelerate
import MediaPlayer
import Photos
import CoreMotion
import Vision

// MARK: - Head Pose Results
struct HeadPoseResult {
    let yaw: Double
    let pitch: Double
    let roll: Double
    let timestamp: Date
}

// MARK: - Low Pass Filter Class
class LowPassFilter {
    private var values: [Double] = []
    private let maxSamples: Int
    
    init(samples: Int = 10) {
        self.maxSamples = samples
    }
    
    func addValue(_ value: Double) -> Double {
        values.append(value)
        
        // Keep only the last N samples
        if values.count > maxSamples {
            values.removeFirst()
        }
        
        // Return the average of all samples
        return values.reduce(0, +) / Double(values.count)
    }
    
    func reset() {
        values.removeAll()
    }
}

// MARK: - Share Sheet for iOS
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - TensorFlow Lite Head Pose Detector
class HeadPoseDetector {
    private var interpreter: Interpreter?
    private let modelQueue = DispatchQueue(label: "headPoseModelQueue", qos: .userInteractive)
    private let inputSize = CGSize(width: 224, height: 224)
    
    init() {
        loadModel()
    }
    
    private func loadModel() {
        guard let modelPath = Bundle.main.path(forResource: "epoch_100_static_bs1", ofType: "tflite") else {
            print("❌ Failed to find model file")
            return
        }
        
        do {
            var options = Interpreter.Options()
            options.threadCount = 3
            interpreter = try Interpreter(modelPath: modelPath, options: options)
            try interpreter?.allocateTensors()
            print("✅ TensorFlow Lite model loaded successfully")
        } catch {
            print("❌ Failed to load TensorFlow Lite model: \(error)")
        }
    }
    
    func detectHeadPose(from image: UIImage, completion: @escaping (HeadPoseResult?) -> Void) {
        modelQueue.async { [weak self] in
            guard let self = self,
                  let interpreter = self.interpreter else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            do {
                // Preprocess the image
                guard let inputData = self.preprocessImage(image) else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Run inference
                try interpreter.copy(inputData, toInputAt: 0)
                try interpreter.invoke()
                
                // Get output tensor
                let outputTensor = try interpreter.output(at: 0)
                let results = outputTensor.data.withUnsafeBytes { bytes in
                    Array(bytes.bindMemory(to: Float32.self))
                }
                
                guard results.count == 6 else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Convert 6D rotation to Euler angles
                let rotation6D = results.map { Double($0) }
                let angles = self.convert6DToEuler(rotation6D)
                
                let headPose = HeadPoseResult(
                    yaw: angles.0,
                    pitch: angles.1,
                    roll: angles.2,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
                    completion(headPose)
                }
                
            } catch {
                print("❌ Head pose detection error: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    private func preprocessImage(_ image: UIImage) -> Data? {
        // Resize image to model input size
        guard let resizedImage = resizeImage(image, to: inputSize),
              let cgImage = resizedImage.cgImage else {
            return nil
        }
        
        // Convert to pixel buffer
        guard let pixelBuffer = cgImage.toPixelBuffer(
            width: Int(inputSize.width),
            height: Int(inputSize.height)
        ) else {
            return nil
        }
        
        // Convert pixel buffer to normalized float array
        let imageData = pixelBufferToFloatArray(
            pixelBuffer: pixelBuffer,
            width: Int(inputSize.width),
            height: Int(inputSize.height)
        )
        
        return Data(bytes: imageData, count: imageData.count * MemoryLayout<Float32>.size)
    }
    
    private func pixelBufferToFloatArray(pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Float32] {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return []
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var floatArray: [Float32] = []
        floatArray.reserveCapacity(width * height * 3)
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * 4 // BGRA format
                
                let r = Float32(buffer[pixelIndex + 1]) / 255.0
                let g = Float32(buffer[pixelIndex + 2]) / 255.0
                let b = Float32(buffer[pixelIndex + 3]) / 255.0
                
                floatArray.append(r)
                floatArray.append(g)
                floatArray.append(b)
            }
        }
        
        return floatArray
    }
    
    // ✅ 6D TO EULER CONVERSION
    private func convert6DToEuler(_ rotation6D: [Double]) -> (Double, Double, Double) {
        let x_raw = [rotation6D[0], rotation6D[1], rotation6D[2]]
        let y_raw = [rotation6D[3], rotation6D[4], rotation6D[5]]
        
        let x_norm = sqrt(x_raw[0]*x_raw[0] + x_raw[1]*x_raw[1] + x_raw[2]*x_raw[2])
        guard x_norm > 1e-8 else { return (0, 0, 0) }
        let x = x_raw.map { $0 / x_norm }
        
        let dot = y_raw[0]*x[0] + y_raw[1]*x[1] + y_raw[2]*x[2]
        
        let y_ortho = [
            y_raw[0] - dot * x[0],
            y_raw[1] - dot * x[1],
            y_raw[2] - dot * x[2]
        ]
        
        let y_norm = sqrt(y_ortho[0]*y_ortho[0] + y_ortho[1]*y_ortho[1] + y_ortho[2]*y_ortho[2])
        guard y_norm > 1e-8 else { return (0, 0, 0) }
        let y = y_ortho.map { $0 / y_norm }
        
        let z = [
            x[1]*y[2] - x[2]*y[1],
            x[2]*y[0] - x[0]*y[2],
            x[0]*y[1] - x[1]*y[0]
        ]
        
        let R = [
            [x[0], y[0], z[0]],
            [x[1], y[1], z[1]],
            [x[2], y[2], z[2]]
        ]
        
        let (pitch, yaw, roll) = rotationMatrixToEulerXYZ(R)
        return (yaw, pitch, roll)
    }
    
    private func rotationMatrixToEulerXYZ(_ R: [[Double]]) -> (Double, Double, Double) {
        let sy = sqrt(R[0][0]*R[0][0] + R[1][0]*R[1][0])
        let singular = sy < 1e-6
        
        let x, y, z: Double
        
        if !singular {
            x = atan2(R[2][1], R[2][2])
            y = atan2(-R[2][0], sy)
            z = atan2(R[1][0], R[0][0])
        } else {
            x = atan2(-R[1][2], R[1][1])
            y = atan2(-R[2][0], sy)
            z = 0
        }
        
        return (x * 180.0 / .pi, y * 180.0 / .pi, z * 180.0 / .pi)
    }
    
    // Helper method to resize UIImage
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - ✅ FIXED Camera Manager with Proper Orientation Alignment
class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var completion: ((UIImage?) -> Void)?
    private var isConfigured = false
    
    // ✅ Published properties for UI binding
    @Published var faceBoxes: [CGRect] = []
    @Published private(set) var croppedHeads: [UIImage] = []
    
    // ✅ Head pose detector
    private let headPoseDetector = HeadPoseDetector()
    
    // ✅ Maximum number of heads to keep in queue
    let maxQueueSize = 20
    
    // ✅ Processing throttle to avoid overwhelming the model
    private var lastProcessTime: Date = Date()
    private let processingInterval: TimeInterval = 0.1
    
    // ✅ Video processing queue
    private let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
    
    // ✅ Preview layer & current view size
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentViewSize: CGSize = .zero
    
    // ✅ Head pose callback
    var onHeadPoseUpdate: ((HeadPoseResult) -> Void)?
    
    override init() {
        super.init()
        setupCamera()
        
        // Keep orientation notifications for reference but don't auto-change
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    // ✅ FIXED: Camera setup with aligned orientations
    func setupCamera() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        
        guard !isConfigured else {
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.startRunning()
                }
            }
            return
        }
        
        session.beginConfiguration()
        
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        
        // ✅ Use back camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        
        // ✅ Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        // ✅ Configure video output with fixed orientation to match Vision (.down)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            
            // ✅ CRITICAL: Set video connection to match Vision orientation (.down = 180°)
            if let connection = videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(0) {
                        connection.videoRotationAngle = 0
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portraitUpsideDown
                    }
                }
                connection.isVideoMirrored = false
            }
        }
        
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        
        session.commitConfiguration()
        isConfigured = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    // ✅ FIXED: Preview setup with aligned orientation
    func setupPreview(in view: UIView, viewSize: CGSize) {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = CGRect(origin: .zero, size: viewSize)
        
        // ✅ CRITICAL: Set preview layer to match Vision orientation (.down = 180°)
        if let connection = layer.connection {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portraitUpsideDown
                }
            }
        }
        
        view.layer.sublayers?.removeAll()
        view.layer.addSublayer(layer)
        previewLayer = layer
        currentViewSize = viewSize
        
        print("✅ Preview layer orientation set to match Vision (.down/180°)")
    }
    
    func updateViewSize(_ size: CGSize) {
        currentViewSize = size
        previewLayer?.frame = CGRect(origin: .zero, size: size)
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // ✅ FIXED: Vision detection with .down orientation (works correctly for tracking)
    private func detectFaces(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let self = self,
                  let faces = req.results as? [VNFaceObservation]
            else { return }
            self.handleDetections(faces, from: pixelBuffer)
        }

        // Keep .down orientation since tracking works correctly
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .downMirrored,
            options: [:]
        )
        try? handler.perform([request])
    }
    
    // ✅ FIXED: Handle detections with proper coordinate transformation
    private func handleDetections(
        _ faces: [VNFaceObservation],
        from pixelBuffer: CVPixelBuffer
    ) {
        guard let preview = previewLayer,
              currentViewSize != .zero
        else { return }

        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        let fullImage = UIImage(cgImage: cg)

        var boxes: [CGRect] = []
        var crops: [UIImage] = []

        for (index, face) in faces.enumerated() {
            let visionRect = face.boundingBox
            
            // ✅ Use built-in coordinate transformation (handles orientation automatically)
            let previewRect = preview.layerRectConverted(fromMetadataOutputRect: visionRect)
            
            // Debug logging for first face only
            if index == 0 {
//                print("=== Face \(index) ===")
//                print("Vision rect: \(visionRect)")
//                print("Preview rect: \(previewRect)")
//                print("Preview layer bounds: \(preview.bounds)")
//                print("Current view size: \(currentViewSize)")
//                print("Preview layer frame: \(preview.frame)")
//                print("==================")
            }
            
            boxes.append(previewRect)

            if let head = cropHeadImage(from: fullImage, boundingBox: visionRect) {
                crops.append(head)
            }
        }

        DispatchQueue.main.async {
            self.faceBoxes = boxes
            self.croppedHeads.append(contentsOf: crops)
            if self.croppedHeads.count > self.maxQueueSize {
                self.croppedHeads.removeFirst(
                    self.croppedHeads.count - self.maxQueueSize
                )
            }
            self.processLatestCropForHeadPose()
        }
    }
    
    private func processLatestCropForHeadPose() {
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= processingInterval,
              let latestCrop = croppedHeads.last else {
            return
        }
        
        lastProcessTime = now
        
        headPoseDetector.detectHeadPose(from: latestCrop) { [weak self] result in
            if let result = result {
                self?.onHeadPoseUpdate?(result)
            }
        }
    }
    
    private func cropHeadImage(
        from image: UIImage,
        boundingBox box: CGRect
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let padding: CGFloat = 0.3
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let paddedBox = CGRect(
            x: max(0, box.minX - padding * box.width),
            y: max(0, box.minY - padding * box.height),
            width: min(1, box.maxX + padding * box.width) - max(0, box.minX - padding * box.width),
            height: min(1, box.maxY + padding * box.height) - max(0, box.minY - padding * box.height)
        )
        
        // For cropping, Vision coordinates work directly
        let cropRect = CGRect(
            x: paddedBox.minX * imageWidth,
            y: (1 - paddedBox.maxY) * imageHeight,
            width: paddedBox.width * imageWidth,
            height: paddedBox.height * imageHeight
        )
        
        let clampedRect = CGRect(
            x: max(0, min(cropRect.minX, imageWidth - 1)),
            y: max(0, min(cropRect.minY, imageHeight - 1)),
            width: min(cropRect.width, imageWidth - max(0, cropRect.minX)),
            height: min(cropRect.height, imageHeight - max(0, cropRect.minY))
        )
        
        guard let cgCrop = cgImage.cropping(to: clampedRect) else {
            return nil
        }
        
        return UIImage(cgImage: cgCrop, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // ✅ Don't automatically change orientation - keep it fixed for landscape use
    @objc private func deviceOrientationDidChange() {
        //print("Device orientation changed but keeping camera orientation fixed for landscape use")
    }
}

// ✅ Photo Capture Delegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let data = photo.fileDataRepresentation(),
              let img = UIImage(data: data) else {
            completion?(nil)
            return
        }
        completion?(img)
        completion = nil
    }
}

// MARK: - ✅ AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        detectFaces(in: pixelBuffer)
    }
}

// MARK: - Enhanced Volume Button Manager with iOS 13+ compatibility
class VolumeButtonManager: NSObject, ObservableObject {
    private var volumeView: MPVolumeView?
    private var audioSession = AVAudioSession.sharedInstance()
    private var isListening = false
    private var volumeSlider: UISlider?
    
    private let targetVolume: Float = 0.5
    private let volumeBuffer: Float = 0.1
    
    private var isResettingVolume = false
    private var lastResetTime: Date = Date()
    private let resetCooldown: TimeInterval = 0.5
    
    var onVolumeButtonPressed: (() -> Void)?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func setupVolumeView() {
        DispatchQueue.main.async {
            self.volumeView?.removeFromSuperview()
            
            self.volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
            self.volumeView?.clipsToBounds = true
            self.volumeView?.isUserInteractionEnabled = false
            self.volumeView?.alpha = 0.0001
            self.volumeView?.showsVolumeSlider = true
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let keyWindow = windowScene.windows.first(where: \.isKeyWindow) {
                keyWindow.addSubview(self.volumeView!)
                keyWindow.sendSubviewToBack(self.volumeView!)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.findVolumeSlider()
                }
            }
        }
    }
    
    private func findVolumeSlider() {
        guard let volumeView = volumeView else { return }
        
        for subview in volumeView.subviews {
            if let slider = subview as? UISlider {
                volumeSlider = slider
                self.setVolumeToTarget()
                break
            }
        }
    }
    
    private func setVolumeToTarget() {
        guard let slider = volumeSlider else { return }
        
        let currentVolume = audioSession.outputVolume
        
        if currentVolume <= volumeBuffer || currentVolume >= (1.0 - volumeBuffer) {
            isResettingVolume = true
            lastResetTime = Date()
            slider.value = targetVolume
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isResettingVolume = false
            }
        }
    }
    
    func startListening() {
        guard !isListening else { return }
        
        isListening = true
        setupVolumeView()
        audioSession.addObserver(self, forKeyPath: "outputVolume", options: [.new, .old], context: nil)
    }
    
    func stopListening() {
        guard isListening else { return }
        
        isListening = false
        audioSession.removeObserver(self, forKeyPath: "outputVolume")
        
        DispatchQueue.main.async {
            self.volumeView?.removeFromSuperview()
            self.volumeView = nil
            self.volumeSlider = nil
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" && isListening {
            guard let change = change,
                  let newValue = change[.newKey] as? Float,
                  let oldValue = change[.oldKey] as? Float else {
                return
            }
            
            if isResettingVolume {
                return
            }
            
            let timeSinceReset = Date().timeIntervalSince(lastResetTime)
            if timeSinceReset < resetCooldown {
                return
            }
            
            let volumeDifference = abs(newValue - oldValue)
            if volumeDifference > 0.001 {
                DispatchQueue.main.async {
                    self.onVolumeButtonPressed?()
                    self.smartVolumeReset(oldValue: oldValue, newValue: newValue)
                }
            }
        }
    }
    
    private func smartVolumeReset(oldValue: Float, newValue: Float) {
        guard let slider = volumeSlider else { return }
        
        let volumeWentUp = newValue > oldValue
        let resetVolume: Float
        
        if newValue <= volumeBuffer {
            resetVolume = targetVolume
        } else if newValue >= (1.0 - volumeBuffer) {
            resetVolume = targetVolume
        } else {
            if volumeWentUp {
                resetVolume = max(volumeBuffer, newValue - 0.1)
            } else {
                resetVolume = min(1.0 - volumeBuffer, newValue + 0.1)
            }
        }
        
        isResettingVolume = true
        lastResetTime = Date()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            slider.value = resetVolume
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isResettingVolume = false
            }
        }
    }
    
    deinit {
        stopListening()
    }
}

// MARK: - Camera Preview SwiftUI Integration
struct CameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager
    let viewSize: CGSize
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        cameraManager.setupPreview(in: view, viewSize: viewSize)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        cameraManager.updateViewSize(viewSize)
    }
}

// MARK: - ImageView is imported from separate file

// MARK: - ✅ FIXED Main Content View - NO BLACK BAR
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var volumeButtonManager = VolumeButtonManager()
    @State private var capturedImages: [UIImage] = Array(repeating: UIImage(), count: 9)
    @State private var croppedEyeImages: [UIImage] = Array(repeating: UIImage(), count: 9)
    @State private var captureStatus: [Bool] = Array(repeating: false, count: 9)
    @State private var captureSequence: [Int] = [4, 1, 2, 5, 8, 7, 6, 3, 0]
    @State private var currentCaptureIndex = 0
    @State private var isShowingResults = false
    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var isProcessing = false
    @State private var redoIndex: Int? = nil
    @State private var isInRedoMode = false
    
    // STABLE Face tracking states with improved filtering
    @State private var yaw: Double = 0
    @State private var pitch: Double = 0
    @State private var roll: Double = 0
    @State private var showFaceTracking = true
    @State private var isFaceDetected = false
    
    // Raw values (before filtering)
    @State private var rawYaw: Double = 0
    @State private var rawPitch: Double = 0
    @State private var rawRoll: Double = 0
    
    // IMPROVED Low pass filters - increased for stability without lag
    @State private var yawFilter = LowPassFilter(samples: 8)
    @State private var pitchFilter = LowPassFilter(samples: 8)
    @State private var rollFilter = LowPassFilter(samples: 8)
    
    // Store face tracking data for each captured image
    @State private var capturedFaceData: [(yaw: Double, pitch: Double, roll: Double)] = Array(repeating: (yaw: 0, pitch: 0, roll: 0), count: 9)
    
    // MARK: - Baseline offset system for personalized guidance
    @State private var baselineYaw: Double = 0.0
    @State private var baselinePitch: Double = 0.0
    @State private var baselineRoll: Double = 0.0
    @State private var hasBaseline = false
    
    // MARK: - Face tracking logging states
    @State private var isLogging = false
    @State private var logStartTime: Date = Date()
    @State private var faceTrackingLogs: [(timestamp: TimeInterval, yaw: Double, pitch: Double, roll: Double)] = []
    @State private var showingLogAlert = false
    @State private var logFileName = ""
    @State private var showingShareSheet = false
    @State private var logFileURL: URL?

    var body: some View {
        // ✅ FIXED: TRUE FULLSCREEN - No black bars
        GeometryReader { geometry in
            if cameraPermissionStatus == .denied {
                permissionDeniedView
            } else if isShowingResults {
                ImageView(
                    images: getFilledImages(),
                    faceData: getFilledFaceData(),
                    onRedo: { displayIndex in
                        print("🔄 Going back to camera to manually retake image at display index: \(displayIndex)")
                        isShowingResults = false  // Go back to camera UI
                        redoIndex = displayIndex  // Set which image to replace
                        isInRedoMode = true      // ✅ NEW: Set redo mode flag
                        isProcessing = false     // Make sure camera button is enabled
                    },
                    onBack: {
                        resetCapture()
                    }
                )

            } else {
                cameraView(geometry: geometry)
            }
        }
        .ignoresSafeArea(.all) // ✅ CRITICAL: Ignore ALL safe areas for true fullscreen
        .statusBarHidden(true) // ✅ CRITICAL: Hide status bar completely
        .onAppear {
            checkCameraPermission()
            setupVolumeButtonCapture()
            setupFaceTrackingCallback()
        }
        .onDisappear {
            volumeButtonManager.stopListening()
        }
        .alert("Camera Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please allow camera access in Settings to use this app.")
        }
        .alert("Face Tracking Log Generated", isPresented: $showingLogAlert) {
            Button("Save File") {
                showingShareSheet = true
            }
            Button("Back") { }
        } message: {
            Text("Log file '\(logFileName)' has been generated with \(faceTrackingLogs.count) data points. Tap 'Share File' to save or send it.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = logFileURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: yaw) { _, _ in logFaceTrackingData() }
        .onChange(of: pitch) { _, _ in logFaceTrackingData() }
        .onChange(of: roll) { _, _ in logFaceTrackingData() }
    }
    
    // MARK: - Setup Face Tracking Callback
    private func setupFaceTrackingCallback() {
        cameraManager.onHeadPoseUpdate = { [self] result in
            self.rawYaw = result.yaw
            self.rawPitch = result.pitch
            self.rawRoll = result.roll
            
            if result.yaw == 0.0 && result.pitch == 0.0 && result.roll == 0.0 {
                self.isFaceDetected = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if self.rawYaw == 0.0 && self.rawPitch == 0.0 && self.rawRoll == 0.0 {
                        self.yawFilter.reset()
                        self.pitchFilter.reset()
                        self.rollFilter.reset()
                        
                        // ✅ Set to NaN when no face detected
                        self.yaw = Double.nan
                        self.pitch = Double.nan
                        self.roll = Double.nan
                    }
                }
            } else {
                self.isFaceDetected = true
                
                self.yaw = yawFilter.addValue(result.yaw)
                self.pitch = pitchFilter.addValue(result.pitch)
                self.roll = rollFilter.addValue(result.roll)
            }
        }
    }
    
    // MARK: - Helper functions for the sequence system
    private func getFilledImages() -> [UIImage] {
        return croppedEyeImages.enumerated().compactMap { index, image in
            captureStatus[index] ? image : nil
        }
    }
    
    private func getFilledFaceData() -> [(yaw: Double, pitch: Double, roll: Double)] {
        return capturedFaceData.enumerated().compactMap { index, data in
            captureStatus[index] ? data : nil
        }
    }
    
    private func getCurrentPhotoNumber() -> Int {
        if let redoIndex = redoIndex {
            return redoIndex + 1  // ✅ Show which photo is being retaken
        }
        
        if currentCaptureIndex < captureSequence.count {
            return captureSequence[currentCaptureIndex] + 1
        }
        return 1
    }
    
    private func getTotalCaptured() -> Int {
        return captureStatus.filter { $0 }.count
    }
    
    // MARK: Permission-denied placeholder
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("Camera Access Required")
                .font(.title2).bold()
            Text("Please enable camera access in Settings to capture photos.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Open Settings") {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // ✅ FIXED: Camera view with proper fullscreen positioning
    private func cameraView(geometry: GeometryProxy) -> some View {
        let screenBounds = UIScreen.main.bounds
        let safeArea = UIApplication.shared.windows.first?.safeAreaInsets ?? UIEdgeInsets.zero
        
        return ZStack {
            // ✅ FIXED: Camera Preview - TRUE FULLSCREEN
            CameraPreview(cameraManager: cameraManager, viewSize: screenBounds.size)
                .ignoresSafeArea(.all)
                .onAppear { cameraManager.setupCamera() }
            
            // ✅ Vision Face Bounding Boxes
            ForEach(cameraManager.faceBoxes.indices, id: \.self) { i in
                let rect = cameraManager.faceBoxes[i]
                Rectangle()
                    .stroke(Color.red, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            
            // ✅ FIXED: Camera Button - Properly positioned from bottom
            // MARK: - Updated camera button with redo mode support
            Button(action: {
                if isInRedoMode {
                    capturePhoto(replaceAt: redoIndex) // ✅ Pass the redoIndex explicitly
                } else {
                    capturePhoto(replaceAt: nil) // ✅ Normal capture
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 90, height: 90)
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    }
                }
            }
            .disabled(isProcessing || (getTotalCaptured() >= 9 && !isInRedoMode)) // ✅ Allow captures in redo mode


            .position(
                x: screenBounds.width * 0.5,
                y: screenBounds.height - safeArea.bottom - 100
            )
            
            // ✅ FIXED: Face Tracking Panel - Account for notch/dynamic island
            HStack(spacing: 12) {
                faceTrackingPanel(geometry: geometry)
            }
            .position(
                x: screenBounds.width * 0.15,
                y: safeArea.top + 120
            )
            
            // ✅ FIXED: Photo Preview Panel
            HStack(spacing: 12) {
                photoPreviewPanel(geometry: geometry)
            }
            .position(
                x: screenBounds.width * 0.15,
                y: screenBounds.height * 0.51
            )
            
            // ✅ FIXED: Yaw Guidance Panel
            HStack(spacing: 12) {
                yawGuidanceView(geometry: geometry)
            }
            .position(
                x: screenBounds.width * 0.15,
                y: screenBounds.height * 0.74
            )
            
            // ✅ FIXED: Face Tracking Logger Button
            HStack(spacing: 12) {
                faceTrackingLoggerButton(geometry: geometry)
            }
            .position(
                x: screenBounds.width * 0.85,
                y: safeArea.top + 120
            )
            
            // ✅ CENTER GUIDE BOX
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green, lineWidth: 3)
                .background(Color.clear)
                .frame(width: 150, height: 150)
                .position(
                    x: screenBounds.width * 0.5,
                    y: screenBounds.height * 0.5
                )
        }
    }
    
    // MARK: - Face Tracking Logger Button
    private func faceTrackingLoggerButton(geometry: GeometryProxy) -> some View {
        Button(action: toggleFaceTrackingLogger) {
            VStack(spacing: 8) {
                Image(systemName: isLogging ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: max(30, geometry.size.width * 0.04)))
                    .foregroundColor(isLogging ? .red : .white)
                
                Text(isLogging ? "STOP" : "LOG")
                    .font(.caption).bold()
                    .foregroundColor(isLogging ? .red : .white)
                
                if isLogging {
                    Text("\(faceTrackingLogs.count)")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isLogging ? Color.black.opacity(0.8) : Color.white.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isLogging ? Color.red : Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            )
        }
        .rotationEffect(.degrees(90))
        .frame(
            minWidth: max(80, geometry.size.width * 0.1),
            minHeight: max(100, geometry.size.height * 0.12)
        )
    }
    
    // MARK: - Face Tracking Logger Functions
    private func toggleFaceTrackingLogger() {
        if isLogging {
            stopFaceTrackingLogger()
        } else {
            startFaceTrackingLogger()
        }
    }

    private func startFaceTrackingLogger() {
        isLogging = true
        logStartTime = Date()
        faceTrackingLogs.removeAll()
        
        print("🔴 Started logging face tracking values")
    }

    private func stopFaceTrackingLogger() {
        isLogging = false
        print("⏹️ Stopped logging with \(faceTrackingLogs.count) total data points")
        
        if !faceTrackingLogs.isEmpty {
            generateLogFile()
        }
    }
    
    private func logFaceTrackingData() {
        guard isLogging else { return }
        
        let timestamp = Date().timeIntervalSince(logStartTime)
        
        let logEntry = (
            timestamp: timestamp,
            yaw: yaw,
            pitch: pitch,
            roll: roll
        )
        
        faceTrackingLogs.append(logEntry)
        
        // Prevent memory overflow
        if faceTrackingLogs.count > 15000 {
            faceTrackingLogs.removeFirst(1000)
        }
    }
    
    private func generateLogFile() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: logStartTime)
        let fileName = "face_tracking_\(timestamp).txt"
        
        var logContent = "Timestamp,Yaw,Pitch,Roll\n"
        
        for entry in faceTrackingLogs {
            logContent += String(format: "%.3f,%.2f,%.2f,%.2f\n",
                               entry.timestamp,
                               entry.yaw,
                               entry.pitch,
                               entry.roll)
        }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            logFileURL = fileURL
            logFileName = fileName
            showingLogAlert = true
            
        } catch {
            print("❌ Error creating log file: \(error)")
        }
    }
    
    // MARK: - Face Tracking Panel
    private func faceTrackingPanel(geometry: GeometryProxy) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: showFaceTracking ? "eye.fill" : "eye.slash.fill")
                    .font(.title3)
                    .foregroundColor(.black)
                    .onTapGesture { showFaceTracking.toggle() }
                
                HStack(spacing: 2) {
                    Circle()
                        .fill(isFaceDetected ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("FACE")
                        .font(.caption2)
                        .foregroundColor(.black)
                }
                
                Text("Q:\(cameraManager.croppedHeads.count)")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }

            if showFaceTracking {
                HStack(spacing: 15) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption)
                        Text("YAW")
                            .font(.caption2).bold()
                        Text(String(format: "%.0f°", (hasBaseline ? yaw - baselineYaw : yaw).isNaN ? 0 : (hasBaseline ? yaw - baselineYaw : yaw)))
                            .font(.caption).bold()
                    }
                    .foregroundColor(.red)
                    .frame(minWidth: max(40, geometry.size.width * 0.05))

                    VStack(spacing: 2) {
                        Image(systemName: "arrow.up.and.down")
                            .font(.caption)
                        Text("PITCH")
                            .font(.caption2).bold()
                        Text(String(format: "%.0f°", (hasBaseline ? pitch - baselinePitch : pitch).isNaN ? 0 : (hasBaseline ? pitch - baselinePitch : pitch)))
                            .font(.caption).bold()
                    }
                    .foregroundColor(.blue)
                    .frame(minWidth: max(45, geometry.size.width * 0.055))

                    VStack(spacing: 2) {
                        Image(systemName: "rotate.3d")
                            .font(.caption)
                        Text("ROLL")
                            .font(.caption2).bold()
                        Text(String(format: "%.0f°", (hasBaseline ? roll - baselineRoll : roll).isNaN ? 0 : (hasBaseline ? roll - baselineRoll : roll)))
                            .font(.caption).bold()
                    }
                    .foregroundColor(.green)
                    .frame(minWidth: max(40, geometry.size.width * 0.05))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
        )
        .rotationEffect(.degrees(90))
        .scaleEffect(1.0)
        .frame(
            minWidth: max(200, geometry.size.width * 0.25),
            minHeight: max(80, geometry.size.height * 0.095)
        )
    }
    
    // MARK: - Photo Preview Panel
    private func photoPreviewPanel(geometry: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            let currentPhotoNumber = getCurrentPhotoNumber()
            let name = "image\(currentPhotoNumber)"

            if let img = UIImage(named: name) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: max(60, geometry.size.width * 0.075),
                        height: max(60, geometry.size.width * 0.075)
                    )
                    .clipped()
                    .cornerRadius(8)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: max(40, geometry.size.width * 0.05)))
                    .foregroundColor(.black)
                    .frame(
                        width: max(60, geometry.size.width * 0.075),
                        height: max(60, geometry.size.width * 0.075)
                    )
            }

            Text("\(currentPhotoNumber)/9")
                .font(.title3).bold()
                .foregroundColor(.black)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
        )
        .rotationEffect(.degrees(90))
        .scaleEffect(1.0)
        .frame(
            minWidth: max(120, geometry.size.width * 0.15),
            minHeight: max(80, geometry.size.height * 0.095)
        )
    }

    // MARK: - Yaw Guidance View
    private func yawGuidanceView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            Text(getYawGuidanceMessage())
                .font(.title2)
                .fontWeight(.heavy)
                .foregroundColor(getYawGuidanceColor())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text(getTargetYawRange())
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
            
            if hasBaseline {
                Text("📍 Baseline Set")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            } else {
                Text("📸 Capture Center First")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, max(20, geometry.size.width * 0.025))
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
        )
        .rotationEffect(.degrees(90))
        .scaleEffect(1.0)
        .frame(
            minWidth: max(180, geometry.size.width * 0.225),
            minHeight: max(100, geometry.size.height * 0.12)
        )
    }
    
    // MARK: - Guidance Logic
    private func getYawGuidanceMessage() -> String {
        let currentPhotoNumber = getCurrentPhotoNumber()
        
        let offsetYaw = hasBaseline ? yaw - baselineYaw : yaw
        let offsetPitch = hasBaseline ? pitch - baselinePitch : pitch
        
        // ✅ Check for no face (NaN values)
        if offsetYaw.isNaN || offsetPitch.isNaN {
            return "NO FACE"
        }
        
        let yawGood = isYawInRange(offsetYaw, photoNumber: currentPhotoNumber)
        let pitchGood = isPitchInRange(offsetPitch, photoNumber: currentPhotoNumber)
        
        if yawGood && pitchGood {
            return "PERFECT! 👍"
        }
        
        var guidance: [String] = []
        
        // ✅ Simple yaw guidance
        if !yawGood {
            switch currentPhotoNumber {
            case 1, 4, 7: // Target: -17 < yaw < -13
                if offsetYaw > -13 {
                    guidance.append("Left")
                }
            case 2, 5, 8: // Target: -2 < yaw < 2
                if offsetYaw < -2 {
                    guidance.append("Right")
                } else if offsetYaw > 2 {
                    guidance.append("Left")
                }
            case 3, 6, 9: // Target: 13 < yaw < 17
                if offsetYaw < 13 {
                    guidance.append("Right")
                }
            default:
                break
            }
        }
        
        // ✅ Simple pitch guidance
        if !pitchGood {
            switch currentPhotoNumber {
            case 1, 2, 3: // Target: -17 < pitch < -13
                if offsetPitch > -13 {
                    guidance.append("Up")
                }
            case 4, 5, 6: // Target: -2 < pitch < 2
                if offsetPitch < -2 {
                    guidance.append("Up")
                } else if offsetPitch > 2 {
                    guidance.append("Down")
                }
            case 7, 8, 9: // Target: 13 < pitch < 17
                if offsetPitch < 13 {
                    guidance.append("Down")
                }
            default:
                break
            }
        }
        
        if guidance.isEmpty {
            return "HOLD"
        } else if guidance.count == 1 {
            return guidance[0]
        } else {
            return guidance.joined(separator: " & ")
        }
    }
    
    private func isYawInRange(_ yaw: Double, photoNumber: Int) -> Bool {
        if yaw.isNaN { return false }
        
        switch photoNumber {
        case 1, 4, 7:
            return -17 < yaw && yaw < -13
        case 2, 5, 8:
            return -2 < yaw && yaw < 2
        case 3, 6, 9:
            return 13 < yaw && yaw < 17
        default:
            return -2 < yaw && yaw < 2
        }
    }

    private func isPitchInRange(_ pitch: Double, photoNumber: Int) -> Bool {
        if pitch.isNaN { return false }
        
        switch photoNumber {
        case 1, 2, 3:
            return -17 < pitch && pitch < -13
        case 4, 5, 6:
            return -2 < pitch && pitch < 2
        case 7, 8, 9:
            return 13 < pitch && pitch < 17
        default:
            return -2 < pitch && pitch < 2
        }
    }

    private func getYawGuidanceColor() -> Color {
        let message = getYawGuidanceMessage()
        
        if message.contains("PERFECT") {
            return .green
        } else if message.contains("GOOD") {
            return .yellow
        } else {
            return .orange
        }
    }
    
    private func getTargetYawRange() -> String {
        let currentPhotoNumber = getCurrentPhotoNumber()
        
        let yawText: String
        let pitchText: String
        
        switch currentPhotoNumber {
        case 1, 4, 7:
            yawText = "Yaw: -17 < y < -13"
        case 2, 5, 8:
            yawText = "Yaw: -2 < y < 2"
        case 3, 6, 9:
            yawText = "Yaw: 13 < y < 17"
        default:
            yawText = "Yaw: -2 < y < 2"
        }
        
        switch currentPhotoNumber {
        case 1, 2, 3:
            pitchText = "Pitch: -17 < p < -13"
        case 4, 5, 6:
            pitchText = "Pitch: -2 < p < 2"
        case 7, 8, 9:
            pitchText = "Pitch: 13 < p < 17"
        default:
            pitchText = "Pitch: -2 < p < 2"
        }
        
        return "\(yawText)\n\(pitchText)"
    }
    
    // MARK: Setup Volume Button Capture
    private func setupVolumeButtonCapture() {
        volumeButtonManager.onVolumeButtonPressed = {
            if !self.isShowingResults && !self.isProcessing && self.getTotalCaptured() < 9 {
                self.capturePhoto(replaceAt: nil)
            }
        }
        volumeButtonManager.startListening()
    }
    
    // MARK: - Fixed capturePhoto function with better redo handling
    // MARK: - Fixed capturePhoto function with better redo handling
    private func capturePhoto(replaceAt index: Int?) {
        guard !isProcessing else { return }
        isProcessing = true
        
        // ✅ Use the stored redoIndex if we're in redo mode
        let targetRedoIndex = index ?? (isInRedoMode ? redoIndex : nil)
        
        print("📸 Capturing photo - Redo mode: \(targetRedoIndex != nil), Index: \(targetRedoIndex ?? -1)")
        
        cameraManager.capturePhoto { image in
            DispatchQueue.main.async {
                guard let img = image else {
                    print("❌ Failed to capture image")
                    self.isProcessing = false
                    return
                }
                
                let targetIndex: Int
                if let idx = targetRedoIndex {
                    // ✅ REDO MODE: Replace specific image
                    targetIndex = idx
                    print("🔄 Replacing image at index: \(idx)")
                } else {
                    // ✅ NORMAL MODE: Next in sequence
                    if self.currentCaptureIndex < self.captureSequence.count {
                        targetIndex = self.captureSequence[self.currentCaptureIndex]
                        self.currentCaptureIndex += 1
                        print("📷 Normal capture at index: \(targetIndex)")
                    } else {
                        print("❌ No more captures allowed")
                        self.isProcessing = false
                        return
                    }
                }
                
                // Store the full captured image first
                self.capturedImages[targetIndex] = img
                self.captureStatus[targetIndex] = true
                
                // Store face tracking data
                self.capturedFaceData[targetIndex] = (yaw: self.yaw, pitch: self.pitch, roll: self.roll)
                
                // ✅ Set baseline only for center image (index 4) and only if not already set
                if targetIndex == 4 && !self.hasBaseline && targetRedoIndex == nil {
                    self.baselineYaw = self.yaw
                    self.baselinePitch = self.pitch
                    self.baselineRoll = self.roll
                    self.hasBaseline = true
                    print("📍 Baseline set: yaw=\(self.yaw), pitch=\(self.pitch), roll=\(self.roll)")
                }
                
                // ✅ CRITICAL: Process for eye detection with proper completion handling
                print("🔍 Starting eye detection for index: \(targetIndex)")
                self.processImageForEyeDetection(img, at: targetIndex)
            }
        }
    }
    
    // MARK: - Fixed processImageForEyeDetection with better error handling
    private func processImageForEyeDetection(_ image: UIImage, at index: Int) {
        print("🔍 Processing image for eye detection at index: \(index)")
        
        guard let cgImage = image.cgImage else {
            print("❌ No CGImage available, using original")
            finishCrop(image, at: index)
            return
        }
        
        let request = VNDetectFaceLandmarksRequest { request, error in
            if let error = error {
                print("❌ Face landmarks detection error: \(error)")
                DispatchQueue.main.async {
                    finishCrop(image, at: index)
                }
                return
            }
            
            var croppedImage = image // Default fallback
            
            // If we found face landmarks, crop around the eyes
            if let results = request.results as? [VNFaceObservation],
               let face = results.first,
               let landmarks = face.landmarks,
               let leftEye = landmarks.leftEye,
               let rightEye = landmarks.rightEye {
                
                print("✅ Face landmarks detected, cropping around eyes")
                croppedImage = cropAroundEyes(
                    image: image,
                    face: face,
                    leftEye: leftEye,
                    rightEye: rightEye
                )
            } else {
                print("⚠️ No face landmarks found, using original image")
            }
            
            DispatchQueue.main.async {
                finishCrop(croppedImage, at: index)
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform face landmarks request: \(error)")
                DispatchQueue.main.async {
                    finishCrop(image, at: index)
                }
            }
        }
    }
    
    private func cropAroundEyes(image: UIImage, face: VNFaceObservation, leftEye: VNFaceLandmarkRegion2D, rightEye: VNFaceLandmarkRegion2D) -> UIImage {
        guard let cgImage = image.cgImage else {
            print("❌ No CGImage for cropping")
            return image
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        print("🖼️ Original image size: \(imageWidth) x \(imageHeight)")
        
        // Convert face bounding box to image coordinates
        let faceBox = face.boundingBox
        let faceRect = CGRect(
            x: faceBox.minX * imageWidth,
            y: (1 - faceBox.maxY) * imageHeight,
            width: faceBox.width * imageWidth,
            height: faceBox.height * imageHeight
        )
        
        print("👤 Face rect: \(faceRect)")
        
        // ✅ BETTER VALIDATION: Check if face is reasonable
        guard faceRect.width > 50 && faceRect.height > 50 else {
            print("❌ Face too small (\(faceRect.width) x \(faceRect.height)), using original image")
            return image
        }
        
        // Get all eye landmark points in image coordinates
        let leftEyePoints = leftEye.normalizedPoints.compactMap { point -> CGPoint? in
            let x = faceRect.minX + point.x * faceRect.width
            let y = faceRect.minY + (1 - point.y) * faceRect.height
            
            // ✅ VALIDATE each point is within image bounds
            guard x >= 0 && x <= imageWidth && y >= 0 && y <= imageHeight else {
                return nil
            }
            return CGPoint(x: x, y: y)
        }
        
        let rightEyePoints = rightEye.normalizedPoints.compactMap { point -> CGPoint? in
            let x = faceRect.minX + point.x * faceRect.width
            let y = faceRect.minY + (1 - point.y) * faceRect.height
            
            // ✅ VALIDATE each point is within image bounds
            guard x >= 0 && x <= imageWidth && y >= 0 && y <= imageHeight else {
                return nil
            }
            return CGPoint(x: x, y: y)
        }
        
        let allEyePoints = leftEyePoints + rightEyePoints
        
        print("👁️ Valid eye points: \(allEyePoints.count) (left: \(leftEyePoints.count), right: \(rightEyePoints.count))")
        
        // ✅ BETTER VALIDATION: Need at least 6 valid points
        guard allEyePoints.count >= 6 else {
            print("❌ Not enough valid eye points (\(allEyePoints.count)), using original image")
            return image
        }
        
        // Find bounding box of all eye points
        let minX = allEyePoints.map(\.x).min() ?? 0
        let maxX = allEyePoints.map(\.x).max() ?? imageWidth
        let minY = allEyePoints.map(\.y).min() ?? 0
        let maxY = allEyePoints.map(\.y).max() ?? imageHeight
        
        print("👁️ Eye bounds: (\(minX), \(minY)) to (\(maxX), \(maxY))")
        
        // ✅ STRICT VALIDATION: Ensure reasonable eye region
        guard maxX > minX + 20 && maxY > minY + 10 else {
            print("❌ Eye region too small: width=\(maxX-minX), height=\(maxY-minY)")
            return image
        }
        
        // Add padding around eyes
        let padding: CGFloat = 30
        let cropX = max(0, minX - padding)
        let cropY = max(0, minY - padding)
        let cropWidth = min(maxX - minX + 2 * padding, imageWidth - cropX)
        let cropHeight = min(maxY - minY + 2 * padding, imageHeight - cropY)
        
        // ✅ FINAL STRICT VALIDATION
        guard cropWidth > 50 && cropHeight > 20 &&
              cropX >= 0 && cropY >= 0 &&
              cropX + cropWidth <= imageWidth &&
              cropY + cropHeight <= imageHeight else {
            print("❌ Invalid crop dimensions: x=\(cropX), y=\(cropY), w=\(cropWidth), h=\(cropHeight)")
            print("   Image size: \(imageWidth) x \(imageHeight)")
            return image
        }
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        print("✅ Valid crop: \(cropRect)")
        
        // Crop the image
        if let croppedCGImage = cgImage.cropping(to: cropRect) {
            let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)
            print("✅ Successfully cropped image: \(croppedImage.size)")
            return croppedImage
        }
        
        print("❌ Failed to crop CGImage, using original")
        return image
    }
    
    // MARK: - Fixed finishCrop with proper completion handling
    private func finishCrop(_ cropped: UIImage, at index: Int) {
        print("✅ Finishing crop for index: \(index)")
        
        DispatchQueue.main.async {
            // Store the cropped image
            self.croppedEyeImages[index] = cropped
            
            // ✅ CRITICAL: Reset processing state
            self.isProcessing = false
            
            // ✅ Clear redo mode states
            if self.isInRedoMode {
                self.isInRedoMode = false
                self.redoIndex = nil
                print("✅ Redo mode completed for index: \(index)")
            }
            
            print("✅ Crop completed for index: \(index). Total captured: \(self.getTotalCaptured())")
            
            // Check if all 9 images are captured
            if self.getTotalCaptured() == 9 {
                print("🎉 All 9 images captured, showing results")
                self.isShowingResults = true
            }
        }
    }
    
    // MARK: - Reset
    private func resetCapture() {
        capturedImages = Array(repeating: UIImage(), count: 9)
        croppedEyeImages = Array(repeating: UIImage(), count: 9)
        captureStatus = Array(repeating: false, count: 9)
        capturedFaceData = Array(repeating: (yaw: 0, pitch: 0, roll: 0), count: 9)
        
        currentCaptureIndex = 0
        
        baselineYaw = 0.0
        baselinePitch = 0.0
        baselineRoll = 0.0
        hasBaseline = false
        
        isProcessing = false
        isShowingResults = false
        
        // ✅ Clear redo mode states
        redoIndex = nil
        isInRedoMode = false
        
        yaw = Double.nan
        pitch = Double.nan
        roll = Double.nan
        rawYaw = Double.nan
        rawPitch = Double.nan
        rawRoll = Double.nan
        
        yawFilter = LowPassFilter(samples: 5)
        pitchFilter = LowPassFilter(samples: 5)
        rollFilter = LowPassFilter(samples: 5)
        
        if isLogging {
            stopFaceTrackingLogger()
        }
    }
    
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermissionStatus = status
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermissionStatus = granted ? .authorized : .denied
                    if !granted {
                        showingPermissionAlert = true
                    }
                }
            }
        case .authorized:
            break
        case .denied, .restricted:
            showingPermissionAlert = true
        @unknown default: break
        }
    }
}

// MARK: - UIImage Extensions
extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

extension CGImage {
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32ARGB,
                                         attrs,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess else { return nil }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
                                space: rgbColorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
}
