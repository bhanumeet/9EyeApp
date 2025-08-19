////
////  HPbckup.swift
////  HeadPose
////
////  Created by Luo Lab on 7/29/25.
////
//
//import SwiftUI
//import AVFoundation
//import UIKit
//import TensorFlowLite
//import CoreImage
//import Accelerate
//import MediaPlayer
//import Vision
//import Photos
//import CoreMotion
//
//
//// MARK: - Low Pass Filter Class
//class LowPassFilter {
//    private var values: [Double] = []
//    private let maxSamples: Int
//    
//    init(samples: Int = 10) {
//        self.maxSamples = samples
//    }
//    
//    func addValue(_ value: Double) -> Double {
//        values.append(value)
//        
//        // Keep only the last N samples
//        if values.count > maxSamples {
//            values.removeFirst()
//        }
//        
//        // Return the average of all samples
//        return values.reduce(0, +) / Double(values.count)
//    }
//    
//    func reset() {
//        values.removeAll()
//    }
//}
//
//// MARK: - Share Sheet for iOS
//struct ActivityViewController: UIViewControllerRepresentable {
//    let activityItems: [Any]
//    
//    func makeUIViewController(context: Context) -> UIActivityViewController {
//        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
//        return controller
//    }
//    
//    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
//}
//
//// MARK: - Main Content View
//struct ContentView: View {
//    @StateObject private var cameraManager = CameraManager()
//    @StateObject private var volumeButtonManager = VolumeButtonManager()
//    @State private var capturedImages: [UIImage] = Array(repeating: UIImage(), count: 9)
//    @State private var croppedEyeImages: [UIImage] = Array(repeating: UIImage(), count: 9)
//    @State private var captureStatus: [Bool] = Array(repeating: false, count: 9)
//    @State private var captureSequence: [Int] = [4, 1, 2, 5, 8, 7, 6, 3, 0]
//    @State private var currentCaptureIndex = 0
//    @State private var isShowingResults = false
//    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
//    @State private var showingPermissionAlert = false
//    @State private var isProcessing = false
//    @State private var redoIndex: Int? = nil
//    
//    // STABLE Face tracking states with improved filtering
//    @State private var yaw: Double = 0
//    @State private var pitch: Double = 0
//    @State private var roll: Double = 0
//    @State private var showFaceTracking = true
//    @State private var isFaceDetected = false
//    
//    // Raw values (before filtering)
//    @State private var rawYaw: Double = 0
//    @State private var rawPitch: Double = 0
//    @State private var rawRoll: Double = 0
//    
//    // IMPROVED Low pass filters - increased for stability without lag
//    @State private var yawFilter = LowPassFilter(samples: 8)
//    @State private var pitchFilter = LowPassFilter(samples: 8)
//    @State private var rollFilter = LowPassFilter(samples: 8)
//    
//    // Store face tracking data for each captured image
//    @State private var capturedFaceData: [(yaw: Double, pitch: Double, roll: Double)] = Array(repeating: (yaw: 0, pitch: 0, roll: 0), count: 9)
//    
//    // MARK: - Baseline offset system for personalized guidance
//    @State private var baselineYaw: Double = 0.0
//    @State private var baselinePitch: Double = 0.0
//    @State private var baselineRoll: Double = 0.0
//    @State private var hasBaseline = false
//    
//    // MARK: - Face tracking logging states
//    @State private var isLogging = false
//    @State private var logStartTime: Date = Date()
//    @State private var faceTrackingLogs: [(timestamp: TimeInterval, yaw: Double, pitch: Double, roll: Double)] = []
//    @State private var showingLogAlert = false
//    @State private var logFileName = ""
//    @State private var showingShareSheet = false
//    @State private var logFileURL: URL?
//    
//    // MARK: - IMPROVED Deduplication with larger threshold for stability
//    @State private var lastLoggedYaw: Double = 999
//    @State private var lastLoggedPitch: Double = 999
//    @State private var lastLoggedRoll: Double = 999
//
//    var body: some View {
//        GeometryReader { geometry in
//            if cameraPermissionStatus == .denied {
//                permissionDeniedView
//            } else if isShowingResults {
//                ImageView(
//                    images: getFilledImages(),
//                    faceData: getFilledFaceData(),
//                    onRedo: { idx in
//                        isShowingResults = false
//                        capturePhoto(replaceAt: idx)
//                    },
//                    onBack: {
//                        resetCapture()
//                    }
//                )
//            } else {
//                cameraView(geometry: geometry)
//            }
//        }
//        .onAppear {
//            checkCameraPermission()
//            setupVolumeButtonCapture()
//        }
//        .onDisappear {
//            volumeButtonManager.stopListening()
//        }
//        .alert("Camera Permission Required", isPresented: $showingPermissionAlert) {
//            Button("Settings") {
//                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
//            }
//            Button("Cancel", role: .cancel) { }
//        } message: {
//            Text("Please allow camera access in Settings to use this app.")
//        }
//        .alert("Face Tracking Log Generated", isPresented: $showingLogAlert) {
//            Button("Save File") {
//                showingShareSheet = true
//            }
//            Button("Back") { }
//        } message: {
//            Text("Log file '\(logFileName)' has been generated with \(faceTrackingLogs.count) data points. Tap 'Share File' to save or send it.")
//        }
//        .sheet(isPresented: $showingShareSheet) {
//            if let url = logFileURL {
//                ActivityViewController(activityItems: [url])
//            }
//        }
//        .preferredColorScheme(.dark)
//        .onChange(of: yaw) { _ in logFaceTrackingData() }
//        .onChange(of: pitch) { _ in logFaceTrackingData() }
//        .onChange(of: roll) { _ in logFaceTrackingData() }
//    }
//    
//    // MARK: - Helper functions for the sequence system
//    private func getFilledImages() -> [UIImage] {
//        return croppedEyeImages.enumerated().compactMap { index, image in
//            captureStatus[index] ? image : nil
//        }
//    }
//    
//    private func getFilledFaceData() -> [(yaw: Double, pitch: Double, roll: Double)] {
//        return capturedFaceData.enumerated().compactMap { index, data in
//            captureStatus[index] ? data : nil
//        }
//    }
//    
//    private func getCurrentPhotoNumber() -> Int {
//        if let redoIndex = redoIndex {
//            return redoIndex + 1
//        }
//        
//        if currentCaptureIndex < captureSequence.count {
//            return captureSequence[currentCaptureIndex] + 1
//        }
//        return 1
//    }
//    
//    private func getTotalCaptured() -> Int {
//        return captureStatus.filter { $0 }.count
//    }
//    
//    // MARK: Permission-denied placeholder
//    private var permissionDeniedView: some View {
//        VStack(spacing: 20) {
//            Image(systemName: "camera.fill")
//                .font(.system(size: 60))
//                .foregroundColor(.gray)
//            Text("Camera Access Required")
//                .font(.title2).bold()
//            Text("Please enable camera access in Settings to capture photos.")
//                .multilineTextAlignment(.center)
//                .foregroundColor(.secondary)
//            Button("Open Settings") {
//                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
//            }
//            .buttonStyle(.borderedProminent)
//        }
//        .padding()
//    }
//    
//    private func cameraView(geometry: GeometryProxy) -> some View {
//        ZStack {
//            // Background - Camera Preview with Bounding Box
//            CameraPreview(
//                cameraManager: cameraManager,
//                rawYaw: $rawYaw,
//                rawPitch: $rawPitch,
//                rawRoll: $rawRoll,
//                yawFilter: $yawFilter,
//                pitchFilter: $pitchFilter,
//                rollFilter: $rollFilter,
//                filteredYaw: $yaw,
//                filteredPitch: $pitch,
//                filteredRoll: $roll,
//                isFaceDetected: $isFaceDetected
//            )
//            .ignoresSafeArea()
//            .onAppear { cameraManager.setupCamera() }
//            
//            // RESPONSIVE: Camera Button - Centered X, Bottom Position
//            Button(action: { capturePhoto(replaceAt: nil) }) {
//                ZStack {
//                    Circle()
//                        .fill(Color.white)
//                        .frame(width: 80, height: 80)
//                    Circle()
//                        .stroke(Color.white, lineWidth: 3)
//                        .frame(width: 90, height: 90)
//                    if isProcessing {
//                        ProgressView()
//                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
//                    }
//                }
//            }
//            .disabled(isProcessing || getTotalCaptured() >= 9)
//            .position(
//                x: geometry.size.width * 0.5,
//                y: geometry.size.height * 0.88
//            )
//            
//            // RESPONSIVE: Face Tracking Panel
//            HStack(spacing: 12) {
//                faceTrackingPanel(geometry: geometry)
//            }
//            .position(
//                x: geometry.size.width * 0.15,
//                y: geometry.size.height * 0.25
//            )
//            
//            // RESPONSIVE: Photo Preview Panel
//            HStack(spacing: 12) {
//                photoPreviewPanel(geometry: geometry)
//            }
//            .position(
//                x: geometry.size.width * 0.15,
//                y: geometry.size.height * 0.51
//            )
//            
//            // RESPONSIVE: Yaw Guidance Panel
//            HStack(spacing: 12) {
//                yawGuidanceView(geometry: geometry)
//            }
//            .position(
//                x: geometry.size.width * 0.15,
//                y: geometry.size.height * 0.74
//            )
//            
//            // Face Tracking Logger Button
//            HStack(spacing: 12) {
//                faceTrackingLoggerButton(geometry: geometry)
//            }
//            .position(
//                x: geometry.size.width * 0.85,
//                y: geometry.size.height * 0.25
//            )
//            
//            // MARK: - CENTER GUIDE BOX
//            RoundedRectangle(cornerRadius: 8)
//                .stroke(Color.green, lineWidth: 3)
//                .background(Color.clear)
//                .frame(width: 150, height: 150)
//                .position(
//                    x: geometry.size.width * 0.5,
//                    y: geometry.size.height * 0.5
//                )
//        }
//    }
//    
//    // MARK: - Face Tracking Logger Button
//    private func faceTrackingLoggerButton(geometry: GeometryProxy) -> some View {
//        Button(action: toggleFaceTrackingLogger) {
//            VStack(spacing: 8) {
//                Image(systemName: isLogging ? "stop.circle.fill" : "record.circle")
//                    .font(.system(size: max(30, geometry.size.width * 0.04)))
//                    .foregroundColor(isLogging ? .red : .white)
//                
//                Text(isLogging ? "STOP" : "LOG")
//                    .font(.caption).bold()
//                    .foregroundColor(isLogging ? .red : .white)
//                
//                if isLogging {
//                    Text("\(faceTrackingLogs.count)")
//                        .font(.caption2)
//                        .foregroundColor(.red)
//                }
//            }
//            .padding(12)
//            .background(
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(isLogging ? Color.black.opacity(0.8) : Color.white.opacity(0.2))
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 12)
//                            .stroke(isLogging ? Color.red : Color.white, lineWidth: 2)
//                    )
//                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
//            )
//        }
//        .rotationEffect(.degrees(90))
//        .frame(
//            minWidth: max(80, geometry.size.width * 0.1),
//            minHeight: max(100, geometry.size.height * 0.12)
//        )
//    }
//    
//    // MARK: - Face Tracking Logger Functions
//    // MARK: - Log ALL Values Face Tracking Logger Functions
//    private func toggleFaceTrackingLogger() {
//        if isLogging {
//            stopFaceTrackingLogger()
//        } else {
//            startFaceTrackingLogger()
//        }
//    }
//
//    
//    private func startFaceTrackingLogger() {
//        isLogging = true
//        logStartTime = Date()
//        faceTrackingLogs.removeAll()
//        
//        print("🔴 Started logging ALL face tracking values")
//    }
//
//    
//    private func stopFaceTrackingLogger() {
//        isLogging = false
//        print("⏹️ Stopped logging with \(faceTrackingLogs.count) total data points")
//        
//        if !faceTrackingLogs.isEmpty {
//            generateLogFile()
//        }
//    }
//    
//    private func logFaceTrackingData() {
//        guard isLogging else { return }
//        
//        let timestamp = Date().timeIntervalSince(logStartTime)
//        
//        // Log every single value - no deduplication, no filtering
//        let logEntry = (
//            timestamp: timestamp,
//            yaw: yaw,
//            pitch: pitch,
//            roll: roll
//        )
//        
//        faceTrackingLogs.append(logEntry)
//        
//        // Progress indicator every 300 entries (~10 seconds at 30fps)
//        if faceTrackingLogs.count % 300 == 0 {
//            print("📊 Logged \(faceTrackingLogs.count) entries")
//        }
//        
//        // Prevent memory overflow - keep last 15,000 entries (~8 minutes at 30fps)
//        if faceTrackingLogs.count > 15000 {
//            faceTrackingLogs.removeFirst(1000) // Remove oldest 1000 entries
//        }
//    }
//    
//    private func generateLogFile() {
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
//        let timestamp = dateFormatter.string(from: logStartTime)
//        let fileName = "face_tracking_all_values_\(timestamp).txt"
//        
//        // Simple CSV header
//        var logContent = "Timestamp,Yaw,Pitch,Roll\n"
//        
//        // Write all entries
//        for entry in faceTrackingLogs {
//            logContent += String(format: "%.3f,%.2f,%.2f,%.2f\n",
//                               entry.timestamp,
//                               entry.yaw,
//                               entry.pitch,
//                               entry.roll)
//        }
//        
//        let tempDirectory = FileManager.default.temporaryDirectory
//        let fileURL = tempDirectory.appendingPathComponent(fileName)
//        
//        do {
//            try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
//            
//            let duration = faceTrackingLogs.last?.timestamp ?? 0
//            let sampleRate = Double(faceTrackingLogs.count) / max(duration, 0.1)
//            
//            print("✅ ALL VALUES CSV created: \(fileName)")
//            print("📊 Total entries: \(faceTrackingLogs.count)")
//            print("⏱️ Duration: \(String(format: "%.1f", duration)) seconds")
//            print("📈 Average sample rate: \(String(format: "%.1f", sampleRate)) Hz")
//            
//            logFileURL = fileURL
//            logFileName = fileName
//            showingLogAlert = true
//            
//        } catch {
//            print("❌ Error creating log file: \(error)")
//        }
//    }
//    
//    // MARK: - UPDATED Face Tracking Panel (removed TFLite indicator)
//    private func faceTrackingPanel(geometry: GeometryProxy) -> some View {
//        HStack(spacing: 14) {
//            VStack(spacing: 4) {
//                // Eye toggle
//                Image(systemName: showFaceTracking ? "eye.fill" : "eye.slash.fill")
//                    .font(.title3)
//                    .foregroundColor(.black)
//                    .onTapGesture { showFaceTracking.toggle() }
//                
//                // Simple face detected indicator
//                HStack(spacing: 2) {
//                    Circle()
//                        .fill(isFaceDetected ? Color.green : Color.gray)
//                        .frame(width: 6, height: 6)
//                    Text("FACE")
//                        .font(.caption2)
//                        .foregroundColor(.black)
//                }
//            }
//
//            if showFaceTracking {
//                HStack(spacing: 15) {
//                    VStack(spacing: 2) {
//                        Image(systemName: "arrow.left.and.right")
//                            .font(.caption)
//                        Text("YAW")
//                            .font(.caption2).bold()
//                        Text(String(format: "%.0f°", hasBaseline ? yaw - baselineYaw : yaw))
//                            .font(.caption).bold()
//                    }
//                    .foregroundColor(.red)
//                    .frame(minWidth: max(40, geometry.size.width * 0.05))
//
//                    VStack(spacing: 2) {
//                        Image(systemName: "arrow.up.and.down")
//                            .font(.caption)
//                        Text("PITCH")
//                            .font(.caption2).bold()
//                        Text(String(format: "%.0f°", hasBaseline ? pitch - baselinePitch : pitch))
//                            .font(.caption).bold()
//                    }
//                    .foregroundColor(.blue)
//                    .frame(minWidth: max(45, geometry.size.width * 0.055))
//
//                    VStack(spacing: 2) {
//                        Image(systemName: "rotate.3d")
//                            .font(.caption)
//                        Text("ROLL")
//                            .font(.caption2).bold()
//                        Text(String(format: "%.0f°", hasBaseline ? roll - baselineRoll : roll))
//                            .font(.caption).bold()
//                    }
//                    .foregroundColor(.green)
//                    .frame(minWidth: max(40, geometry.size.width * 0.05))
//                }
//            }
//        }
//        .padding(12)
//        .background(
//            RoundedRectangle(cornerRadius: 10)
//                .fill(Color.white.opacity(0.85))
//                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
//        )
//        .rotationEffect(.degrees(90))
//        .scaleEffect(1.0)
//        .frame(
//            minWidth: max(200, geometry.size.width * 0.25),
//            minHeight: max(80, geometry.size.height * 0.095)
//        )
//    }
//    
//    // MARK: - Photo Preview Panel
//    private func photoPreviewPanel(geometry: GeometryProxy) -> some View {
//        HStack(spacing: 8) {
//            let currentPhotoNumber = getCurrentPhotoNumber()
//            let name = "image\(currentPhotoNumber)"
//
//            if let img = UIImage(named: name) {
//                Image(uiImage: img)
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//                    .frame(
//                        width: max(60, geometry.size.width * 0.075),
//                        height: max(60, geometry.size.width * 0.075)
//                    )
//                    .clipped()
//                    .cornerRadius(8)
//            } else {
//                Image(systemName: "photo")
//                    .font(.system(size: max(40, geometry.size.width * 0.05)))
//                    .foregroundColor(.black)
//                    .frame(
//                        width: max(60, geometry.size.width * 0.075),
//                        height: max(60, geometry.size.width * 0.075)
//                    )
//            }
//
//            Text("\(currentPhotoNumber)/9")
//                .font(.title3).bold()
//                .foregroundColor(.black)
//        }
//        .padding(10)
//        .background(
//            RoundedRectangle(cornerRadius: 10)
//                .fill(Color.white.opacity(0.85))
//                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
//        )
//        .rotationEffect(.degrees(90))
//        .scaleEffect(1.0)
//        .frame(
//            minWidth: max(120, geometry.size.width * 0.15),
//            minHeight: max(80, geometry.size.height * 0.095)
//        )
//    }
//
//    // MARK: - Yaw Guidance View
//    private func yawGuidanceView(geometry: GeometryProxy) -> some View {
//        VStack(spacing: 8) {
//            Text(getYawGuidanceMessage())
//                .font(.title2)
//                .fontWeight(.heavy)
//                .foregroundColor(getYawGuidanceColor())
//                .multilineTextAlignment(.center)
//                .lineLimit(2)
//            
//            Text(getTargetYawRange())
//                .font(.caption)
//                .foregroundColor(.white.opacity(0.9))
//                .lineLimit(2)
//            
//            if hasBaseline {
//                Text("📍 Baseline Set")
//                    .font(.caption2)
//                    .foregroundColor(.cyan)
//            } else {
//                Text("📸 Capture Center First")
//                    .font(.caption2)
//                    .foregroundColor(.yellow)
//            }
//        }
//        .padding(.horizontal, max(20, geometry.size.width * 0.025))
//        .padding(.vertical, 12)
//        .background(
//            RoundedRectangle(cornerRadius: 15)
//                .fill(Color.black.opacity(0.7))
//                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
//        )
//        .rotationEffect(.degrees(90))
//        .scaleEffect(1.0)
//        .frame(
//            minWidth: max(180, geometry.size.width * 0.225),
//            minHeight: max(100, geometry.size.height * 0.12)
//        )
//    }
//    
//    // MARK: - Guidance Logic
//    private func getYawGuidanceMessage() -> String {
//        let currentPhotoNumber = getCurrentPhotoNumber()
//        
//        let offsetYaw = hasBaseline ? yaw - baselineYaw : yaw
//        let offsetPitch = hasBaseline ? pitch - baselinePitch : pitch
//        
//        let yawGood = isYawInRange(offsetYaw, photoNumber: currentPhotoNumber)
//        let pitchGood = isPitchInRange(offsetPitch, photoNumber: currentPhotoNumber)
//        
//        if yawGood && pitchGood {
//            return "PERFECT! 👍"
//        }
//        
//        var guidance: [String] = []
//        
//        if !yawGood {
//            switch currentPhotoNumber {
//            case 1, 4, 7:
//                if offsetYaw > -15 {
//                    guidance.append("Left")
//                }
//            case 2, 5, 8:
//                if offsetYaw < -5 {
//                    guidance.append("Right")
//                } else if offsetYaw > 5 {
//                    guidance.append("Left")
//                }
//            case 3, 6, 9:
//                if offsetYaw < 15 {
//                    guidance.append("Right")
//                }
//            default:
//                break
//            }
//        }
//        
//        if !pitchGood {
//            switch currentPhotoNumber {
//            case 1, 2, 3:
//                if offsetPitch < -10 {
//                    guidance.append("Up")
//                }
//            case 4, 5, 6:
//                if offsetPitch < -5 {
//                    guidance.append("Up")
//                } else if offsetPitch > 5 {
//                    guidance.append("Down")
//                }
//            case 7, 8, 9:
//                if offsetPitch > 10 {
//                    guidance.append("Down")
//                }
//            default:
//                break
//            }
//        }
//        
//        if guidance.isEmpty {
//            return "NO FACE"
//        } else if guidance.count == 1 {
//            return guidance[0]
//        } else {
//            return guidance.joined(separator: " & ")
//        }
//    }
//    
//    private func isYawInRange(_ yaw: Double, photoNumber: Int) -> Bool {
//        switch photoNumber {
//        case 1, 4, 7:
//            return yaw >= 15
//        case 2, 5, 8:
//            return yaw >= -5 && yaw <= 5
//        case 3, 6, 9:
//            return yaw <= -15
//        default:
//            return yaw >= -5 && yaw <= 5
//        }
//    }
//
//    private func isPitchInRange(_ pitch: Double, photoNumber: Int) -> Bool {
//        switch photoNumber {
//        case 1, 2, 3:
//            return pitch <= -10
//        case 4, 5, 6:
//            return pitch >= -5 && pitch <= 5
//        case 7, 8, 9:
//            return pitch >= 10
//        default:
//            return pitch >= -5 && pitch <= 5
//        }
//    }
//
//    private func getYawGuidanceColor() -> Color {
//        let message = getYawGuidanceMessage()
//        
//        if message.contains("PERFECT") {
//            return .green
//        } else if message.contains("GOOD") {
//            return .yellow
//        } else {
//            return .orange
//        }
//    }
//    
//    private func getTargetYawRange() -> String {
//        let currentPhotoNumber = getCurrentPhotoNumber()
//        
//        let yawText: String
//        let pitchText: String
//        
//        switch currentPhotoNumber {
//        case 1, 4, 7:
//            yawText = "Yaw: -15° and lower"
//        case 2, 5, 8:
//            yawText = "Yaw: -5° to 5°"
//        case 3, 6, 9:
//            yawText = "Yaw: 15° and higher"
//        default:
//            yawText = "Yaw: -5° to 5°"
//        }
//        
//        switch currentPhotoNumber {
//        case 1, 2, 3:
//            pitchText = "Pitch: 10° and higher"
//        case 4, 5, 6:
//            pitchText = "Pitch: -5° to 5°"
//        case 7, 8, 9:
//            pitchText = "Pitch: -10° and lower"
//        default:
//            pitchText = "Pitch: -5° to 5°"
//        }
//        
//        return "\(yawText)\n\(pitchText)"
//    }
//    
//    // MARK: Setup Volume Button Capture
//    private func setupVolumeButtonCapture() {
//        print("Setting up volume button capture...")
//        volumeButtonManager.onVolumeButtonPressed = {
//            print("Volume button callback triggered!")
//            if !self.isShowingResults && !self.isProcessing && self.getTotalCaptured() < 9 {
//                print("Capturing photo via volume button...")
//                self.capturePhoto(replaceAt: nil)
//            } else {
//                print("Volume button ignored - isShowingResults: \(self.isShowingResults), isProcessing: \(self.isProcessing), count: \(self.getTotalCaptured())")
//            }
//        }
//        volumeButtonManager.startListening()
//    }
//    
//    // MARK: - Rotate image before processing
//    private func rotateImageForLandscape(_ image: UIImage) -> UIImage {
//        guard let cgImage = image.cgImage else { return image }
//        
//        let rotatedOrientation: UIImage.Orientation
//        switch image.imageOrientation {
//        case .up:
//            rotatedOrientation = .left
//        case .down:
//            rotatedOrientation = .right
//        case .left:
//            rotatedOrientation = .down
//        case .right:
//            rotatedOrientation = .up
//        case .upMirrored:
//            rotatedOrientation = .leftMirrored
//        case .downMirrored:
//            rotatedOrientation = .rightMirrored
//        case .leftMirrored:
//            rotatedOrientation = .downMirrored
//        case .rightMirrored:
//            rotatedOrientation = .upMirrored
//        @unknown default:
//            rotatedOrientation = .left
//        }
//        
//        return UIImage(cgImage: cgImage, scale: image.scale, orientation: rotatedOrientation)
//    }
//    
//    // MARK: - Capture Photo
//    private func capturePhoto(replaceAt index: Int?) {
//        guard !isProcessing else { return }
//        isProcessing = true
//        redoIndex = index
//        
//        cameraManager.capturePhoto { image in
//            DispatchQueue.main.async {
//                guard let img = image else {
//                    isProcessing = false
//                    return
//                }
//                
//                let rotatedImage = self.rotateImageForLandscape(img)
//                
//                let targetIndex: Int
//                if let idx = index {
//                    targetIndex = idx
//                } else {
//                    if currentCaptureIndex < captureSequence.count {
//                        targetIndex = captureSequence[currentCaptureIndex]
//                        currentCaptureIndex += 1
//                    } else {
//                        isProcessing = false
//                        return
//                    }
//                }
//                
//                capturedImages[targetIndex] = rotatedImage
//                captureStatus[targetIndex] = true
//                
//                capturedFaceData[targetIndex] = (yaw: yaw, pitch: pitch, roll: roll)
//                
//                if targetIndex == 4 && !hasBaseline {
//                    baselineYaw = yaw
//                    baselinePitch = pitch
//                    baselineRoll = roll
//                    hasBaseline = true
//                    print("🎯 Baseline set from center image: Yaw=\(String(format: "%.1f", baselineYaw))°, Pitch=\(String(format: "%.1f", baselinePitch))°, Roll=\(String(format: "%.1f", baselineRoll))°")
//                }
//                
//                processImageForEyeDetection(rotatedImage, at: targetIndex)
//                print("🔄 Processing image for eye detection at index \(targetIndex)")
//                isProcessing = false
//                redoIndex = nil
//            }
//        }
//    }
//    
//    // MARK: - Process Image for Eye Detection
//    private func processImageForEyeDetection(_ image: UIImage, at index: Int) {
//        print("🔍 Starting eye detection for image at index \(index)")
//        
//        let cropped = cropToEyeRegionHighQuality(image)
//        finishCrop(cropped, at: index)
//    }
//    
//    private func cropToEyeRegionHighQuality(_ image: UIImage) -> UIImage {
//        guard let cgImage = image.cgImage else { return image }
//        
//        let originalWidth = CGFloat(cgImage.width)
//        let originalHeight = CGFloat(cgImage.height)
//        
//        let cropHeight = originalHeight * 0.15
//        let cropWidth = originalWidth * 0.25
//        
//        let finalCropWidth = min(cropWidth, originalWidth)
//        let finalCropHeight = min(cropHeight, originalHeight)
//        
//        let cropX = max(0, (originalWidth - finalCropWidth) / 2)
//        let eyeRegionY = originalHeight * 0.40
//        let cropY = max(0, min(eyeRegionY, originalHeight - finalCropHeight))
//        
//        let cropRect = CGRect(
//            x: cropX,
//            y: cropY,
//            width: finalCropWidth,
//            height: finalCropHeight
//        )
//        
//        if let croppedCGImage = cgImage.cropping(to: cropRect) {
//            return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
//        }
//        
//        return image
//    }
//    
//    private func finishCrop(_ cropped: UIImage, at index: Int) {
//        DispatchQueue.main.async {
//            croppedEyeImages[index] = cropped
//            print("✅ Cropped image stored at index \(index), size: \(cropped.size)")
//            
//            if getTotalCaptured() == 9 {
//                isShowingResults = true
//            }
//        }
//    }
//    
//    // MARK: - UPDATED Reset with improved filter reset
//    private func resetCapture() {
//        print("🔄 Resetting app - clearing all captured data, filters, and baseline")
//        
//        capturedImages = Array(repeating: UIImage(), count: 9)
//        croppedEyeImages = Array(repeating: UIImage(), count: 9)
//        captureStatus = Array(repeating: false, count: 9)
//        capturedFaceData = Array(repeating: (yaw: 0, pitch: 0, roll: 0), count: 9)
//        
//        currentCaptureIndex = 0
//        
//        baselineYaw = 0.0
//        baselinePitch = 0.0
//        baselineRoll = 0.0
//        hasBaseline = false
//        
//        isProcessing = false
//        isShowingResults = false
//        redoIndex = nil
//        
//        yaw = 0
//        pitch = 0
//        roll = 0
//        rawYaw = 0
//        rawPitch = 0
//        rawRoll = 0
//        
//        yawFilter = LowPassFilter(samples: 5)
//        pitchFilter = LowPassFilter(samples: 5)
//        rollFilter = LowPassFilter(samples: 5)
//        
//        if isLogging {
//            stopFaceTrackingLogger()
//        }
//        
//        lastLoggedYaw = 999
//        lastLoggedPitch = 999
//        lastLoggedRoll = 999
//        
//        print("✅ App reset complete with improved stability settings")
//    }
//    
//    private func checkCameraPermission() {
//        let status = AVCaptureDevice.authorizationStatus(for: .video)
//        cameraPermissionStatus = status
//        switch status {
//        case .notDetermined:
//            AVCaptureDevice.requestAccess(for: .video) { granted in
//                DispatchQueue.main.async {
//                    cameraPermissionStatus = granted ? .authorized : .denied
//                    if !granted {
//                        showingPermissionAlert = true
//                    }
//                }
//            }
//        case .authorized:
//            break
//        case .denied, .restricted:
//            showingPermissionAlert = true
//        @unknown default: break
//        }
//    }
//}
//
//// MARK: — OPTIMIZED Camera Manager with TensorFlow Lite + Face Bounding Box
//class CameraManager: NSObject, ObservableObject {
//    let session = AVCaptureSession()
//    private let photoOutput = AVCapturePhotoOutput()
//    private let videoOutput = AVCaptureVideoDataOutput()
//    private var completion: ((UIImage?) -> Void)?
//    private var isConfigured = false
//    
//    // TensorFlow Lite models
//    private var faceDetectionInterpreter: Interpreter?
//    private var headPoseInterpreter: Interpreter?
//    private let faceDetectionModelName = "dms_face_hand"
//    private let headPoseModelName = "epoch_100_static_bs1"
//    private var faceInputSize = CGSize(width: 192, height: 192)
//    private var poseInputSize = CGSize(width: 224, height: 224)
//    
//    // BALANCED FRAME RATE CONTROL - Process every 2nd frame (15fps) for stability
//    private var frameCounter = 0
//    private let frameSkip = 0 // Process every other frame (30fps → 15fps)
//    
//    // FACE TRACKING STATE with stabilization
//    private var lastValidFaceRect: CGRect?
//    private var consecutiveNoFaceFrames = 0
//    private let maxNoFaceFrames = 5
//    
//    // FACE BOUNDING BOX STABILIZATION
//    private var faceRectHistory: [CGRect] = []
//    private let maxFaceRectHistory = 3
//    
//    // BOUNDING BOX STATE
//    @Published var currentFaceBoundingBox: CGRect?
//    @Published var previewSize: CGSize = .zero
//    
//    var onFaceTrackingUpdate: ((Double, Double, Double) -> Void)?
//    var onBoundingBoxUpdate: ((CGRect?, CGSize) -> Void)?
//    
//    override init() {
//        super.init()
//        loadTensorFlowLiteModels()
//    }
//    
//    private func loadTensorFlowLiteModels() {
//        DispatchQueue.global(qos: .background).async { [weak self] in
//            guard let self = self else { return }
//            
//            guard let faceModelPath = Bundle.main.path(forResource: self.faceDetectionModelName, ofType: "tflite"),
//                  let poseModelPath = Bundle.main.path(forResource: self.headPoseModelName, ofType: "tflite") else {
//                print("❌ Could not find TensorFlow Lite model files")
//                return
//            }
//            
//            do {
//                var options = Interpreter.Options()
//                options.threadCount = 2
//                
//                self.faceDetectionInterpreter = try Interpreter(modelPath: faceModelPath, options: options)
//                try self.faceDetectionInterpreter?.allocateTensors()
//                print("✅ Face detection model loaded")
//                
//                self.headPoseInterpreter = try Interpreter(modelPath: poseModelPath, options: options)
//                try self.headPoseInterpreter?.allocateTensors()
//                print("✅ Head pose model loaded")
//                
//            } catch {
//                print("❌ Error loading TensorFlow Lite models: \(error)")
//            }
//        }
//    }
//    
//    func setupCamera() {
//        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
//        
//        guard !isConfigured else {
//            if !session.isRunning {
//                DispatchQueue.global(qos: .userInitiated).async {
//                    self.session.startRunning()
//                }
//            }
//            return
//        }
//        
//        session.beginConfiguration()
//        
//        session.inputs.forEach { session.removeInput($0) }
//        session.outputs.forEach { session.removeOutput($0) }
//        
//        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
//           let input = try? AVCaptureDeviceInput(device: device),
//           session.canAddInput(input) {
//            session.addInput(input)
//        }
//        
//        if session.canAddOutput(photoOutput) {
//            session.addOutput(photoOutput)
//        }
//        
//        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoQ", qos: .userInitiated))
//        
//        if session.canAddOutput(videoOutput) {
//            session.addOutput(videoOutput)
//            
//            if let connection = videoOutput.connection(with: .video) {
//                if connection.isVideoOrientationSupported {
//                    connection.videoOrientation = .portrait
//                }
//            }
//        }
//        
//        // Set frame rate on the device for smooth performance
//        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
//            do {
//                try device.lockForConfiguration()
//                
//                // Set to 30fps for smooth real-time processing
//                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
//                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
//                
//                // Enable stabilization if available
//                if device.activeFormat.isVideoStabilizationModeSupported(.cinematic) {
//                    // Note: Video stabilization is set on connection, not device
//                }
//                
//                device.unlockForConfiguration()
//            } catch {
//                print("Failed to configure device: \(error)")
//            }
//        }
//        
//        // Configure video connection for quality
//        if let connection = videoOutput.connection(with: .video) {
//            if connection.isVideoOrientationSupported {
//                connection.videoOrientation = .portrait
//            }
//            
//            // Enable video stabilization for better quality (updated API)
//            if connection.isVideoStabilizationSupported {
//                connection.preferredVideoStabilizationMode = .auto
//            }
//        }
//        
//        if session.canSetSessionPreset(.high) {
//            session.sessionPreset = .high
//        }
//        
//        session.commitConfiguration()
//        isConfigured = true
//        
//        DispatchQueue.global(qos: .userInitiated).async {
//            self.session.startRunning()
//        }
//    }
//    
//    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
//        self.completion = completion
//        let settings = AVCapturePhotoSettings()
//        settings.flashMode = .auto
//        photoOutput.capturePhoto(with: settings, delegate: self)
//    }
//    
//    // BALANCED FRAME PROCESSING - 15fps for optimal stability/responsiveness balance
//    private func processFrameWithTensorFlowLite(image: UIImage, imageSize: CGSize) {
//        // Store current image size for bounding box scaling
//        DispatchQueue.main.async {
//            self.previewSize = imageSize
//        }
//        
////        // BALANCED PROCESSING - Every other frame (15fps)
////        frameCounter += 1
////        if frameCounter % (frameSkip + 1) != 0 {
////            return
////        }
////
//        // STEP 1: Detect face first
//        guard let faceDetection = detectFaceWithTFLite(image: image) else {
//            handleNoFaceDetected()
//            return
//        }
//        
//        if !faceDetection.detected {
//            handleNoFaceDetected()
//            return
//        }
//        
//        // STEP 2: Update bounding box on main thread
//        if let faceRect = faceDetection.boundingBox {
//            DispatchQueue.main.async {
//                self.currentFaceBoundingBox = faceRect
//            }
//        }
//        
//        // STEP 3: Stabilize and crop to face region for pose estimation
//        let faceImage: UIImage
//        if let faceRect = faceDetection.boundingBox {
//            // Stabilize the face bounding box
//            let stabilizedRect = stabilizeFaceRect(faceRect)
//            faceImage = cropImageToFace(image, faceRect: stabilizedRect)
//            lastValidFaceRect = stabilizedRect
//            consecutiveNoFaceFrames = 0
//        } else {
//            if let lastRect = lastValidFaceRect {
//                faceImage = cropImageToFace(image, faceRect: lastRect)
//            } else {
//                handleNoFaceDetected()
//                return
//            }
//        }
//        
//        // STEP 4: Run pose estimation on cropped face
//        guard let poseAngles = estimatePoseWithTFLite(image: faceImage) else {
//            handleNoFaceDetected()
//            return
//        }
//        
//        // SUCCESS - Send valid pose data
//        DispatchQueue.main.async {
//            self.onFaceTrackingUpdate?(poseAngles.yaw, poseAngles.pitch, poseAngles.roll)
//        }
//    }
//    
//    private func handleNoFaceDetected() {
//        consecutiveNoFaceFrames += 1
//        
//        if consecutiveNoFaceFrames >= maxNoFaceFrames {
//            lastValidFaceRect = nil
//            DispatchQueue.main.async {
//                self.currentFaceBoundingBox = nil
//                self.onFaceTrackingUpdate?(0.0, 0.0, 0.0)
//            }
//        }
//    }
//    
//    // STABILIZE FACE BOUNDING BOX to reduce crop variations
//    private func stabilizeFaceRect(_ newRect: CGRect) -> CGRect {
//        // Add to history
//        faceRectHistory.append(newRect)
//        
//        // Keep only recent history
//        if faceRectHistory.count > maxFaceRectHistory {
//            faceRectHistory.removeFirst()
//        }
//        
//        // If we don't have enough history, return the new rect
//        guard faceRectHistory.count >= 2 else {
//            return newRect
//        }
//        
//        // Average the recent face rectangles for stability
//        let avgX = faceRectHistory.map { $0.origin.x }.reduce(0, +) / CGFloat(faceRectHistory.count)
//        let avgY = faceRectHistory.map { $0.origin.y }.reduce(0, +) / CGFloat(faceRectHistory.count)
//        let avgWidth = faceRectHistory.map { $0.size.width }.reduce(0, +) / CGFloat(faceRectHistory.count)
//        let avgHeight = faceRectHistory.map { $0.size.height }.reduce(0, +) / CGFloat(faceRectHistory.count)
//        
//        return CGRect(x: avgX, y: avgY, width: avgWidth, height: avgHeight)
//    }
//    
//    // CROP IMAGE TO FACE REGION
//    private func cropImageToFace(_ image: UIImage, faceRect: CGRect) -> UIImage {
//        guard let cgImage = image.cgImage else { return image }
//        
//        // Expand face rect slightly for better pose estimation context
//        let expandedRect = CGRect(
//            x: max(0, faceRect.minX - faceRect.width * 0.2),
//            y: max(0, faceRect.minY - faceRect.height * 0.3),
//            width: min(CGFloat(cgImage.width) - faceRect.minX, faceRect.width * 1.4),
//            height: min(CGFloat(cgImage.height) - faceRect.minY, faceRect.height * 1.6)
//        )
//        
//        if let croppedCGImage = cgImage.cropping(to: expandedRect) {
//            return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
//        }
//        
//        return image
//    }
//    
//    private func detectFaceWithTFLite(image: UIImage) -> (detected: Bool, boundingBox: CGRect?)? {
//        guard let interpreter = faceDetectionInterpreter else { return nil }
//        
//        do {
//            guard let resizedImage = resizeImage(image, to: faceInputSize),
//                  let inputData = preprocessImageForFaceDetection(resizedImage) else {
//                return nil
//            }
//            
//            // SAVE THE 192x192 LETTERBOXED IMAGE - Fixed call
//            //saveCroppedImageToPhotos(resizedImage, index: savedCropCount + 1)
//            
//            try interpreter.copy(inputData, toInputAt: 0)
//            try interpreter.invoke()
//            
//            let scoresOutput = try interpreter.output(at: 0)
//            let boxesOutput = try interpreter.output(at: 1)
//            
//            let scores = scoresOutput.data.withUnsafeBytes { bytes in
//                Array(bytes.bindMemory(to: Float32.self))
//            }
//            
//            let boxes = boxesOutput.data.withUnsafeBytes { bytes in
//                Array(bytes.bindMemory(to: Float32.self))
//            }
//            
//            let bestBox = processFaceDetectionResults(scores: scores, boxes: boxes, originalImageSize: image.size)
//            
//            if let faceBox = bestBox {
//                let detected = faceBox.confidence > 0.5
//                return (detected: detected, boundingBox: detected ? faceBox.rect : nil)
//            }
//            
//            return (detected: false, boundingBox: nil)
//            
//        } catch {
//            print("❌ Error in face detection: \(error)")
//            return nil
//        }
//    }
//    
//    private func estimatePoseWithTFLite(image: UIImage) -> (yaw: Double, pitch: Double, roll: Double)? {
//        guard let interpreter = headPoseInterpreter else { return nil }
//        
//        do {
//            guard let preprocessedImage = preprocessImageForPoseEstimation(image),
//                  let inputData = imageToInputData(preprocessedImage) else {
//                return nil
//            }
//            
//            // SAVE THE CROPPED FACE IMAGE (this is what the model actually sees)
//            //saveCroppedImageToPhotos(preprocessedImage, index: savedCropCount)
//            
//            try interpreter.copy(inputData, toInputAt: 0)
//            try interpreter.invoke()
//            
//            let outputTensor = try interpreter.output(at: 0)
//            let results = outputTensor.data.withUnsafeBytes { bytes in
//                Array(bytes.bindMemory(to: Float32.self))
//            }
//            
//            if results.count == 6 {
//                let rotation6D = results.map { Double($0) }
//                let angles = convert6DToEuler(rotation6D)
//                
//                let clampedYaw = max(-180, min(180, angles.0))
//                let clampedPitch = max(-90, min(90, angles.1))
//                let clampedRoll = max(-180, min(180, angles.2))
//                
//                return (yaw: clampedYaw, pitch: clampedPitch, roll: clampedRoll)
//            }
//            
//            return nil
//            
//        } catch {
//            print("❌ Error in pose estimation: \(error)")
//            return nil
//        }
//    }
//
//    
//    // CONSISTENT IMAGE PREPROCESSING
//    private func preprocessImageForPoseEstimation(_ image: UIImage) -> UIImage? {
//        return resizeAndCenterCrop(image, targetSize: Int(poseInputSize.width))
//    }
//    
//    // MARK: - Updated resizeImage function with 90° left rotation and letterboxing
//    // MARK: - Updated resizeImage function with stretching instead of letterboxing
//    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
//        let targetWidth = size.width
//        let targetHeight = size.height
//        
//        // Create the target size image context
//        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
//        
//        // Fill with black background (just in case)
//        UIColor.black.setFill()
//        UIRectFill(CGRect(origin: .zero, size: size))
//        
//        // Draw the image stretched to fill the entire target size
//        // This will stretch/distort the image to fit exactly 192x192
//        image.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
//        
//        let stretchedImage = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        
//        return stretchedImage
//    }
//    ///SAVE HEAD CROP FRAMES -
//    // Add these properties to CameraManager class
//    // Add these properties to CameraManager class
//    private var savedCropCount = 0
//    private let maxCropsToSave = 10
//
//    // Add this function to CameraManager class
//    // MARK: - Fixed Save Function with Proper Logging
//    private func saveCroppedImageToPhotos(_ image: UIImage, index: Int) {
//        // Check if we've already saved enough images
//        guard savedCropCount < maxCropsToSave else {
//            print("🛑 Already saved \(maxCropsToSave) images, skipping save #\(savedCropCount + 1)")
//            return
//        }
//        
//        print("📸 Attempting to save 192x192 letterboxed image #\(savedCropCount + 1)/\(maxCropsToSave)")
//        print("   Image size: \(image.size)")
//        
//        // Check current photo library authorization status
//        let authStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
//        print("   Current photo library auth status: \(authStatus.rawValue)")
//        
//        switch authStatus {
//        case .authorized, .limited:
//            // Already authorized, save directly
//            print("   ✅ Already authorized, saving image...")
//            performImageSave(image)
//            
//        case .denied, .restricted:
//            print("   ❌ Photo library access denied or restricted")
//            return
//            
//        case .notDetermined:
//            print("   🔄 Requesting photo library authorization...")
//            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
//                print("   📋 Authorization result: \(status.rawValue)")
//                
//                DispatchQueue.main.async {
//                    switch status {
//                    case .authorized, .limited:
//                        print("   ✅ Authorization granted, saving image...")
//                        self?.performImageSave(image)
//                    case .denied, .restricted:
//                        print("   ❌ Authorization denied")
//                    @unknown default:
//                        print("   ⚠️ Unknown authorization status: \(status.rawValue)")
//                    }
//                }
//            }
//            
//        @unknown default:
//            print("   ⚠️ Unknown authorization status: \(authStatus.rawValue)")
//            return
//        }
//    }
//    
//    // MARK: - Helper function to actually perform the save
//    private func performImageSave(_ image: UIImage) {
//        PHPhotoLibrary.shared().performChanges({
//            let creationRequest = PHAssetCreationRequest.forAsset()
//            creationRequest.addResource(with: .photo, data: image.jpegData(compressionQuality: 0.9)!, options: nil)
//        }) { [weak self] success, error in
//            DispatchQueue.main.async {
//                guard let self = self else { return }
//                
//                if success {
//                    self.savedCropCount += 1
//                    print("💾 ✅ Successfully saved 192x192 letterboxed image #\(self.savedCropCount) to Photos")
//                    
//                    if self.savedCropCount >= self.maxCropsToSave {
//                        print("🎉 ✅ Finished saving all \(self.maxCropsToSave) letterboxed images to Photos")
//                    }
//                } else {
//                    print("💾 ❌ Failed to save image to Photos: \(error?.localizedDescription ?? "Unknown error")")
//                }
//            }
//        }
//    }
//    
//    private func preprocessImageForFaceDetection(_ image: UIImage) -> Data? {
//        guard let cgImage = image.cgImage else { return nil }
//        
//        let width = Int(faceInputSize.width)
//        let height = Int(faceInputSize.height)
//        
//        guard let pixelBuffer = createPixelBuffer(from: cgImage, width: width, height: height),
//              let floatArray = pixelBufferToFloatArray(pixelBuffer, width: width, height: height) else {
//            return nil
//        }
//        
//        return Data(bytes: floatArray, count: floatArray.count * MemoryLayout<Float32>.size)
//    }
//    
//    private func imageToInputData(_ image: UIImage) -> Data? {
//        guard let cgImage = image.cgImage else { return nil }
//        
//        let width = Int(poseInputSize.width)
//        let height = Int(poseInputSize.height)
//        
//        guard let pixelBuffer = createPixelBuffer(from: cgImage, width: width, height: height),
//              let floatArray = pixelBufferToFloatArray(pixelBuffer, width: width, height: height) else {
//            return nil
//        }
//        
//        return Data(bytes: floatArray, count: floatArray.count * MemoryLayout<Float32>.size)
//    }
//    
//    // a single, shared motion manager
//    private let motionManager = CMMotionManager()
//
//    /// Resizes to fill, center‑crops a square of side `targetSize`,
//    /// and—if the device is physically in landscape—rotates 90° left.
//    private func resizeAndCenterCrop(_ image: UIImage, targetSize: Int) -> UIImage? {
//        // 1️⃣ Start deviceMotion if needed
//        if !motionManager.isDeviceMotionActive {
//            motionManager.deviceMotionUpdateInterval = 0.05
//            motionManager.startDeviceMotionUpdates()
//        }
//
//        // 2️⃣ Read gravity to decide landscape vs portrait
//        var isLandscape = false
//        if let g = motionManager.deviceMotion?.gravity {
//            // landscape when horizontal component exceeds vertical
//            isLandscape = abs(g.x) > abs(g.y)
//        }
//
//        // 3️⃣ Compute scale to aspect‑fill
//        let origSize = image.size
//        let aspect = origSize.width / origSize.height
//        let scale: CGFloat
//        if aspect > 1 {
//            scale = CGFloat(targetSize) / origSize.height
//        } else {
//            scale = CGFloat(targetSize) / origSize.width
//        }
//        let resizedSize = CGSize(width: origSize.width * scale,
//                                 height: origSize.height * scale)
//
//        // 4️⃣ Draw resized image
//        UIGraphicsBeginImageContextWithOptions(resizedSize, false, 1.0)
//        image.draw(in: CGRect(origin: .zero, size: resizedSize))
//        guard let resized = UIGraphicsGetImageFromCurrentImageContext() else {
//            UIGraphicsEndImageContext()
//            return nil
//        }
//        UIGraphicsEndImageContext()
//
//        // 5️⃣ Center‑crop rect
//        let cropRect = CGRect(
//            x: (resizedSize.width  - CGFloat(targetSize)) / 2,
//            y: (resizedSize.height - CGFloat(targetSize)) / 2,
//            width: CGFloat(targetSize),
//            height: CGFloat(targetSize)
//        )
//        let cropSize = CGSize(width: CGFloat(targetSize), height: CGFloat(targetSize))
//
//        // 6️⃣ Draw final—rotated if landscape
//        UIGraphicsBeginImageContextWithOptions(cropSize, false, 1.0)
//        guard let ctx = UIGraphicsGetCurrentContext() else {
//            UIGraphicsEndImageContext()
//            return nil
//        }
//
//        if isLandscape {
//            // rotate 90° CCW about center
//            ctx.translateBy(x: cropSize.width/2, y: cropSize.height/2)
//            ctx.rotate(by: -CGFloat.pi/2)
//            ctx.translateBy(x: -cropSize.height/2, y: -cropSize.width/2)
//            // after rotation, width/height swap, so draw with swapped offsets
//            resized.draw(
//                in: CGRect(
//                    x: -cropRect.origin.y,
//                    y: -cropRect.origin.x,
//                    width: resizedSize.width,
//                    height: resizedSize.height
//                )
//            )
//        } else {
//            // portrait: no rotation
//            resized.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
//        }
//
//        let final = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        return final
//    }
//
//    
//    private func createPixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
//        var pixelBuffer: CVPixelBuffer?
//        
//        let attributes: [String: Any] = [
//            kCVPixelBufferCGImageCompatibilityKey as String: true,
//            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
//        ]
//        
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            width,
//            height,
//            kCVPixelFormatType_32ARGB,
//            attributes as CFDictionary,
//            &pixelBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
//            return nil
//        }
//        
//        CVPixelBufferLockBaseAddress(buffer, [])
//        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
//        
//        let pixelData = CVPixelBufferGetBaseAddress(buffer)
//        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
//        
//        guard let context = CGContext(
//            data: pixelData,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
//            space: rgbColorSpace,
//            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
//        ) else {
//            return nil
//        }
//        
//        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
//        
//        return buffer
//    }
//    
//    private func pixelBufferToFloatArray(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Float32]? {
//        CVPixelBufferLockBaseAddress(pixelBuffer, [])
//        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
//        
//        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
//            return nil
//        }
//        
//        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
//        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
//        
//        var floatArray: [Float32] = []
//        floatArray.reserveCapacity(width * height * 3)
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let pixelIndex = y * bytesPerRow + x * 4
//                
//                let r = Float32(buffer[pixelIndex + 1]) / 255.0
//                let g = Float32(buffer[pixelIndex + 2]) / 255.0
//                let b = Float32(buffer[pixelIndex + 3]) / 255.0
//                
//                floatArray.append(r)
//                floatArray.append(g)
//                floatArray.append(b)
//            }
//        }
//        
//        return floatArray
//    }
//    
//    private func processFaceDetectionResults(scores: [Float32], boxes: [Float32], originalImageSize: CGSize) -> (rect: CGRect, confidence: Float32)? {
//        let numAnchors = 756
//        let numClasses = 3
//        
//        let anchorPoints = generateAnchorPoints()
//        let strides = generateStrides()
//        
//        let sigmoidScores = scores.map { 1.0 / (1.0 + exp(-$0)) }
//        
//        var bestDetection: (rect: CGRect, confidence: Float32)? = nil
//        var maxConfidence: Float32 = 0.0
//        
//        for i in 0..<numAnchors {
//            for classIdx in 1..<numClasses {
//                let scoreIndex = i * numClasses + classIdx
//                if scoreIndex < sigmoidScores.count {
//                    let confidence = sigmoidScores[scoreIndex]
//                    
//                    if confidence > maxConfidence && confidence > 0.3 {
//                        let boxIndex = i * 4
//                        if boxIndex + 3 < boxes.count {
//                            let anchorX = anchorPoints[i].x
//                            let anchorY = anchorPoints[i].y
//                            let stride = strides[i]
//                            
//                            let x1 = anchorX - boxes[boxIndex] * stride
//                            let y1 = anchorY - boxes[boxIndex + 1] * stride
//                            let x2 = anchorX + boxes[boxIndex + 2] * stride
//                            let y2 = anchorY + boxes[boxIndex + 3] * stride
//                            
//                            let scaleX = Float32(originalImageSize.width) / 192.0
//                            let scaleY = Float32(originalImageSize.height) / 192.0
//                            
//                            let scaledX1 = x1 * scaleX
//                            let scaledY1 = y1 * scaleY
//                            let scaledX2 = x2 * scaleX
//                            let scaledY2 = y2 * scaleY
//                            
//                            let minX = min(scaledX1, scaledX2)
//                            let maxX = max(scaledX1, scaledX2)
//                            let minY = min(scaledY1, scaledY2)
//                            let maxY = max(scaledY1, scaledY2)
//                            
//                            let rect = CGRect(
//                                x: CGFloat(max(0, minX)),
//                                y: CGFloat(max(0, minY)),
//                                width: CGFloat(maxX - minX),
//                                height: CGFloat(maxY - minY)
//                            )
//                            
//                            if rect.width > 20 && rect.height > 20 &&
//                               rect.maxX <= originalImageSize.width &&
//                               rect.maxY <= originalImageSize.height {
//                                maxConfidence = confidence
//                                bestDetection = (rect: rect, confidence: confidence)
//                            }
//                        }
//                    }
//                }
//            }
//        }
//        
//        return bestDetection
//    }
//    
//    private func generateAnchorPoints() -> [(x: Float32, y: Float32)] {
//        var anchorPoints: [(x: Float32, y: Float32)] = []
//        
//        let featureMapSizes = [(24, 24), (12, 12), (6, 6)]
//        let strides: [Float32] = [8, 16, 32]
//        
//        for (levelIdx, (featH, featW)) in featureMapSizes.enumerated() {
//            let stride = strides[levelIdx]
//            
//            for y in 0..<featH {
//                for x in 0..<featW {
//                    let anchorX = (Float32(x) + 0.5) * stride
//                    let anchorY = (Float32(y) + 0.5) * stride
//                    anchorPoints.append((x: anchorX, y: anchorY))
//                }
//            }
//        }
//        
//        return anchorPoints
//    }
//    
//    private func generateStrides() -> [Float32] {
//        var strides: [Float32] = []
//        
//        let featureMapSizes = [(24, 24), (12, 12), (6, 6)]
//        let strideValues: [Float32] = [8, 16, 32]
//        
//        for (levelIdx, (featH, featW)) in featureMapSizes.enumerated() {
//            let stride = strideValues[levelIdx]
//            for _ in 0..<(featH * featW) {
//                strides.append(stride)
//            }
//        }
//        
//        return strides
//    }
//    
//    private func convert6DToEuler(_ rotation6D: [Double]) -> (Double, Double, Double) {
//        let x_raw = [rotation6D[0], rotation6D[1], rotation6D[2]]
//        let y_raw = [rotation6D[3], rotation6D[4], rotation6D[5]]
//        
//        let x_norm = sqrt(x_raw[0]*x_raw[0] + x_raw[1]*x_raw[1] + x_raw[2]*x_raw[2])
//        guard x_norm > 1e-8 else { return (0, 0, 0) }
//        let x = x_raw.map { $0 / x_norm }
//        
//        let dot = y_raw[0]*x[0] + y_raw[1]*x[1] + y_raw[2]*x[2]
//        
//        let y_ortho = [
//            y_raw[0] - dot * x[0],
//            y_raw[1] - dot * x[1],
//            y_raw[2] - dot * x[2]
//        ]
//        
//        let y_norm = sqrt(y_ortho[0]*y_ortho[0] + y_ortho[1]*y_ortho[1] + y_ortho[2]*y_ortho[2])
//        guard y_norm > 1e-8 else { return (0, 0, 0) }
//        let y = y_ortho.map { $0 / y_norm }
//        
//        let z = [
//            x[1]*y[2] - x[2]*y[1],
//            x[2]*y[0] - x[0]*y[2],
//            x[0]*y[1] - x[1]*y[0]
//        ]
//        
//        let R = [
//            [x[0], y[0], z[0]],
//            [x[1], y[1], z[1]],
//            [x[2], y[2], z[2]]
//        ]
//        
//        let (pitch, yaw, roll) = rotationMatrixToEulerXYZ(R)
//        
//        return (yaw, pitch, roll)
//    }
//    
//    private func rotationMatrixToEulerXYZ(_ R: [[Double]]) -> (Double, Double, Double) {
//        let sy = sqrt(R[0][0]*R[0][0] + R[1][0]*R[1][0])
//        let singular = sy < 1e-6
//        
//        let x, y, z: Double
//        
//        if !singular {
//            x = atan2(R[2][1], R[2][2])
//            y = atan2(-R[2][0], sy)
//            z = atan2(R[1][0], R[0][0])
//        } else {
//            x = atan2(-R[1][2], R[1][1])
//            y = atan2(-R[2][0], sy)
//            z = 0
//        }
//        
//        return (x * 180.0 / .pi, y * 180.0 / .pi, z * 180.0 / .pi)
//    }
//}
//
//// MARK: Photo Capture Delegate
//extension CameraManager: AVCapturePhotoCaptureDelegate {
//    func photoOutput(
//        _ output: AVCapturePhotoOutput,
//        didFinishProcessingPhoto photo: AVCapturePhoto,
//        error: Error?
//    ) {
//        guard let data = photo.fileDataRepresentation(),
//              let img = UIImage(data: data) else {
//            completion?(nil)
//            return
//        }
//        completion?(img)
//        completion = nil
//    }
//}
//
//// MARK: - Video Data Output Delegate
//extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
//    func captureOutput(_ output: AVCaptureOutput,
//                       didOutput sb: CMSampleBuffer,
//                       from _: AVCaptureConnection) {
//        guard let buf = CMSampleBufferGetImageBuffer(sb) else { return }
//        
//        let ciImage = CIImage(cvPixelBuffer: buf)
//        let context = CIContext()
//        
//        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
//        let image = UIImage(cgImage: cgImage)
//        
//        let imageSize = image.size
//        
//        processFrameWithTensorFlowLite(image: image, imageSize: imageSize)
//    }
//}
//
//// MARK: - Enhanced Volume Button Manager
//class VolumeButtonManager: NSObject, ObservableObject {
//    private var volumeView: MPVolumeView?
//    private var audioSession = AVAudioSession.sharedInstance()
//    private var isListening = false
//    private var volumeSlider: UISlider?
//    
//    private let targetVolume: Float = 0.5
//    private let volumeBuffer: Float = 0.1
//    
//    private var isResettingVolume = false
//    private var lastResetTime: Date = Date()
//    private let resetCooldown: TimeInterval = 0.5
//    
//    var onVolumeButtonPressed: (() -> Void)?
//    
//    override init() {
//        super.init()
//        setupAudioSession()
//    }
//    
//    private func setupAudioSession() {
//        do {
//            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
//            try audioSession.setActive(true)
//        } catch {
//            print("Failed to setup audio session: \(error)")
//        }
//    }
//    
//    private func setupVolumeView() {
//        DispatchQueue.main.async {
//            self.volumeView?.removeFromSuperview()
//            
//            self.volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
//            self.volumeView?.clipsToBounds = true
//            self.volumeView?.isUserInteractionEnabled = false
//            self.volumeView?.alpha = 0.0001
//            self.volumeView?.showsVolumeSlider = true
//            
//            if #available(iOS 13.0, *) {
//                self.volumeView?.showsRouteButton = false
//            }
//            
//            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//               let keyWindow = windowScene.windows.first(where: \.isKeyWindow) {
//                keyWindow.addSubview(self.volumeView!)
//                keyWindow.sendSubviewToBack(self.volumeView!)
//                
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                    self.findVolumeSlider()
//                }
//            }
//        }
//    }
//    
//    private func findVolumeSlider() {
//        guard let volumeView = volumeView else { return }
//        
//        for subview in volumeView.subviews {
//            if let slider = subview as? UISlider {
//                volumeSlider = slider
//                print("Found volume slider")
//                self.setVolumeToTarget()
//                break
//            }
//        }
//    }
//    
//    private func setVolumeToTarget() {
//        guard let slider = volumeSlider else { return }
//        
//        let currentVolume = audioSession.outputVolume
//        
//        if currentVolume <= volumeBuffer || currentVolume >= (1.0 - volumeBuffer) {
//            print("Volume at extreme (\(currentVolume)), setting to target (\(targetVolume))")
//            isResettingVolume = true
//            lastResetTime = Date()
//            slider.value = targetVolume
//            
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                self.isResettingVolume = false
//            }
//        } else {
//            print("Volume is acceptable (\(currentVolume)), keeping current level")
//        }
//    }
//    
//    func startListening() {
//        guard !isListening else { return }
//        
//        print("Starting volume button listening...")
//        isListening = true
//        
//        setupVolumeView()
//        audioSession.addObserver(self, forKeyPath: "outputVolume", options: [.new, .old], context: nil)
//        
//        print("Volume button listening started")
//    }
//    
//    func stopListening() {
//        guard isListening else { return }
//        
//        print("Stopping volume button listening...")
//        isListening = false
//        
//        audioSession.removeObserver(self, forKeyPath: "outputVolume")
//        
//        DispatchQueue.main.async {
//            self.volumeView?.removeFromSuperview()
//            self.volumeView = nil
//            self.volumeSlider = nil
//        }
//        
//        print("Volume button listening stopped")
//    }
//    
//    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
//        if keyPath == "outputVolume" && isListening {
//            guard let change = change,
//                  let newValue = change[.newKey] as? Float,
//                  let oldValue = change[.oldKey] as? Float else {
//                return
//            }
//            
//            if isResettingVolume {
//                print("Ignoring volume change - we're resetting it ourselves")
//                return
//            }
//            
//            let timeSinceReset = Date().timeIntervalSince(lastResetTime)
//            if timeSinceReset < resetCooldown {
//                print("Ignoring volume change - too soon after reset (\(timeSinceReset)s)")
//                return
//            }
//            
//            let volumeDifference = abs(newValue - oldValue)
//            if volumeDifference > 0.001 {
//                print("REAL volume button detected! Old: \(oldValue), New: \(newValue), Diff: \(volumeDifference)")
//                
//                DispatchQueue.main.async {
//                    self.onVolumeButtonPressed?()
//                    self.smartVolumeReset(oldValue: oldValue, newValue: newValue)
//                }
//            }
//        }
//    }
//    
//    private func smartVolumeReset(oldValue: Float, newValue: Float) {
//        guard let slider = volumeSlider else { return }
//        
//        let volumeWentUp = newValue > oldValue
//        let resetVolume: Float
//        
//        if newValue <= volumeBuffer {
//            resetVolume = targetVolume
//            print("Volume too low (\(newValue)), resetting to \(resetVolume)")
//        } else if newValue >= (1.0 - volumeBuffer) {
//            resetVolume = targetVolume
//            print("Volume too high (\(newValue)), resetting to \(resetVolume)")
//        } else {
//            if volumeWentUp {
//                resetVolume = max(volumeBuffer, newValue - 0.1)
//            } else {
//                resetVolume = min(1.0 - volumeBuffer, newValue + 0.1)
//            }
//            print("Smart reset: Volume went \(volumeWentUp ? "up" : "down"), resetting to \(resetVolume)")
//        }
//        
//        isResettingVolume = true
//        lastResetTime = Date()
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            slider.value = resetVolume
//            print("Volume reset to: \(resetVolume)")
//            
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                self.isResettingVolume = false
//            }
//        }
//    }
//    
//    deinit {
//        stopListening()
//    }
//}
//
//// MARK: - Camera Preview View with Bounding Box
//class CameraPreviewView: UIView {
//    var session: AVCaptureSession? {
//        didSet { previewLayer.session = session }
//    }
//    
//    // BOUNDING BOX PROPERTIES
//    var faceBoundingBox: CGRect? {
//        didSet {
//            DispatchQueue.main.async {
//                self.updateBoundingBox()
//            }
//        }
//    }
//    
//    var originalImageSize: CGSize = .zero {
//        didSet {
//            DispatchQueue.main.async {
//                self.updateBoundingBox()
//            }
//        }
//    }
//    
//    private var boundingBoxLayer: CAShapeLayer?
//    
//    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
//    
//    private var previewLayer: AVCaptureVideoPreviewLayer {
//        layer as! AVCaptureVideoPreviewLayer
//    }
//    
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        setupLayer()
//        setupBoundingBoxLayer()
//    }
//    
//    required init?(coder: NSCoder) {
//        super.init(coder: coder)
//        setupLayer()
//        setupBoundingBoxLayer()
//    }
//    
//    private func setupLayer() {
//        previewLayer.videoGravity = .resizeAspectFill
//    }
//    
//    private func setupBoundingBoxLayer() {
//        boundingBoxLayer = CAShapeLayer()
//        boundingBoxLayer?.fillColor = UIColor.clear.cgColor
//        boundingBoxLayer?.strokeColor = UIColor.red.cgColor
//        boundingBoxLayer?.lineWidth = 3.0
//        // Removed lineDashPattern for solid line
//        
//        if let boundingBoxLayer = boundingBoxLayer {
//            layer.addSublayer(boundingBoxLayer)
//        }
//    }
//    
//    override func layoutSubviews() {
//        super.layoutSubviews()
//        previewLayer.frame = bounds
//        updateBoundingBox()
//    }
//    
//    private func updateBoundingBox() {
//        guard let faceBoundingBox = faceBoundingBox,
//              originalImageSize != .zero,
//              bounds.size != .zero else {
//            boundingBoxLayer?.path = nil
//            return
//        }
//        
//        // Convert the face bounding box from image coordinates to preview coordinates
//        let convertedRect = convertRectFromImageToPreview(faceBoundingBox)
//        
//        // Create the bounding box path
//        let path = UIBezierPath(roundedRect: convertedRect, cornerRadius: 8)
//        boundingBoxLayer?.path = path.cgPath
//        
//        // Add animation for smooth appearance
//        let animation = CABasicAnimation(keyPath: "opacity")
//        animation.duration = 0.2
//        animation.fromValue = 0.0
//        animation.toValue = 1.0
//        boundingBoxLayer?.add(animation, forKey: "fadeIn")
//    }
//    
//    private func convertRectFromImageToPreview(_ imageRect: CGRect) -> CGRect {
//        let previewSize = bounds.size
//        let imageSize = originalImageSize
//        
//        guard previewSize != .zero && imageSize != .zero else {
//            return .zero
//        }
//        
//        // Calculate the scale factor for resizeAspectFill
//        let scaleX = previewSize.width / imageSize.width
//        let scaleY = previewSize.height / imageSize.height
//        let scale = max(scaleX, scaleY) // Use max for aspect fill
//        
//        // Calculate the actual displayed image size
//        let scaledImageSize = CGSize(
//            width: imageSize.width * scale,
//            height: imageSize.height * scale
//        )
//        
//        // Calculate the offset to center the scaled image
//        let offsetX = (previewSize.width - scaledImageSize.width) / 2
//        let offsetY = (previewSize.height - scaledImageSize.height) / 2
//        
//        // Convert the face rect from image coordinates to preview coordinates
//        let convertedRect = CGRect(
//            x: imageRect.minX * scale + offsetX,
//            y: imageRect.minY * scale + offsetY,
//            width: imageRect.width * scale,
//            height: imageRect.height * scale
//        )
//        
//        return convertedRect
//    }
//}
//
//// MARK: - Updated Camera Preview with Bounding Box Integration
//struct CameraPreview: UIViewRepresentable {
//    let cameraManager: CameraManager
//    @Binding var rawYaw: Double
//    @Binding var rawPitch: Double
//    @Binding var rawRoll: Double
//    @Binding var yawFilter: LowPassFilter
//    @Binding var pitchFilter: LowPassFilter
//    @Binding var rollFilter: LowPassFilter
//    @Binding var filteredYaw: Double
//    @Binding var filteredPitch: Double
//    @Binding var filteredRoll: Double
//    @Binding var isFaceDetected: Bool
//    
//    func makeUIView(context: Context) -> CameraPreviewView {
//        let view = CameraPreviewView()
//        view.session = cameraManager.session
//        
//        // IMPROVED face tracking callback with better filtering logic
//        cameraManager.onFaceTrackingUpdate = { yaw, pitch, roll in
//            // Store raw values for potential debugging
//            self.rawYaw = yaw
//            self.rawPitch = pitch
//            self.rawRoll = roll
//            
//            // Handle no face detected case (all values are zero)
//            if yaw == 0.0 && pitch == 0.0 && roll == 0.0 {
//                // DON'T reset filters immediately - this prevents jumpiness
//                self.isFaceDetected = false
//                
//                // Keep last filtered values to avoid sudden jumps
//                // Only reset to zero if we've been getting zeros for a while
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//                    // Check if we're still getting zeros after 1 second
//                    if self.rawYaw == 0.0 && self.rawPitch == 0.0 && self.rawRoll == 0.0 {
//                        // Reset filters and values after sustained no-face period
//                        self.yawFilter.reset()
//                        self.pitchFilter.reset()
//                        self.rollFilter.reset()
//                        
//                        self.filteredYaw = 0.0
//                        self.filteredPitch = 0.0
//                        self.filteredRoll = 0.0
//                    }
//                }
//            } else {
//                // Valid face data received
//                self.isFaceDetected = true
//                
//                // Apply filtering for smooth values
//                self.filteredYaw = yawFilter.addValue(yaw)
//                self.filteredPitch = pitchFilter.addValue(pitch)
//                self.filteredRoll = rollFilter.addValue(roll)
//            }
//        }
//        
//        return view
//    }
//    
//    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
//        // Update bounding box when it changes
//        uiView.faceBoundingBox = cameraManager.currentFaceBoundingBox
//        uiView.originalImageSize = cameraManager.previewSize
//    }
//}


///APV + HEADPOSE BACKUP STARTS HERE -
//import SwiftUI
//import AVFoundation
//import UIKit
//import TensorFlowLite
//import CoreImage
//import Accelerate
//import MediaPlayer
//import Photos
//import CoreMotion
//import Vision
//
//// MARK: - Head Pose Results
//struct HeadPoseResult {
//    let yaw: Double
//    let pitch: Double
//    let roll: Double
//    let timestamp: Date
//}
//
//// MARK: - Low Pass Filter Class
//class LowPassFilter {
//    private var values: [Double] = []
//    private let maxSamples: Int
//    
//    init(samples: Int = 10) {
//        self.maxSamples = samples
//    }
//    
//    func addValue(_ value: Double) -> Double {
//        values.append(value)
//        
//        // Keep only the last N samples
//        if values.count > maxSamples {
//            values.removeFirst()
//        }
//        
//        // Return the average of all samples
//        return values.reduce(0, +) / Double(values.count)
//    }
//    
//    func reset() {
//        values.removeAll()
//    }
//}
//
//// MARK: - Share Sheet for iOS
//struct ActivityViewController: UIViewControllerRepresentable {
//    let activityItems: [Any]
//    
//    func makeUIViewController(context: Context) -> UIActivityViewController {
//        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
//        return controller
//    }
//    
//    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
//}
//
//// MARK: - TensorFlow Lite Head Pose Detector
//class HeadPoseDetector {
//    private var interpreter: Interpreter?
//    private let modelQueue = DispatchQueue(label: "headPoseModelQueue", qos: .userInteractive)
//    private let inputSize = CGSize(width: 224, height: 224)
//    
//    init() {
//        loadModel()
//    }
//    
//    private func loadModel() {
//        guard let modelPath = Bundle.main.path(forResource: "epoch_100_static_bs1", ofType: "tflite") else {
//            print("❌ Failed to find model file")
//            return
//        }
//        
//        do {
//            var options = Interpreter.Options()
//            options.threadCount = 3
//            interpreter = try Interpreter(modelPath: modelPath, options: options)
//            try interpreter?.allocateTensors()
//            print("✅ TensorFlow Lite model loaded successfully")
//        } catch {
//            print("❌ Failed to load TensorFlow Lite model: \(error)")
//        }
//    }
//    
//    func detectHeadPose(from image: UIImage, completion: @escaping (HeadPoseResult?) -> Void) {
//        modelQueue.async { [weak self] in
//            guard let self = self,
//                  let interpreter = self.interpreter else {
//                DispatchQueue.main.async {
//                    completion(nil)
//                }
//                return
//            }
//            
//            do {
//                // Preprocess the image
//                guard let inputData = self.preprocessImage(image) else {
//                    DispatchQueue.main.async {
//                        completion(nil)
//                    }
//                    return
//                }
//                
//                // Run inference
//                try interpreter.copy(inputData, toInputAt: 0)
//                try interpreter.invoke()
//                
//                // Get output tensor
//                let outputTensor = try interpreter.output(at: 0)
//                let results = outputTensor.data.withUnsafeBytes { bytes in
//                    Array(bytes.bindMemory(to: Float32.self))
//                }
//                
//                guard results.count == 6 else {
//                    DispatchQueue.main.async {
//                        completion(nil)
//                    }
//                    return
//                }
//                
//                // Convert 6D rotation to Euler angles
//                let rotation6D = results.map { Double($0) }
//                let angles = self.convert6DToEuler(rotation6D)
//                
//                let headPose = HeadPoseResult(
//                    yaw: angles.0,
//                    pitch: angles.1,
//                    roll: angles.2,
//                    timestamp: Date()
//                )
//                
//                DispatchQueue.main.async {
//                    completion(headPose)
//                }
//                
//            } catch {
//                print("❌ Head pose detection error: \(error)")
//                DispatchQueue.main.async {
//                    completion(nil)
//                }
//            }
//        }
//    }
//    
//    private func preprocessImage(_ image: UIImage) -> Data? {
//        // Resize image to model input size
//        guard let resizedImage = resizeImage(image, to: inputSize),
//              let cgImage = resizedImage.cgImage else {
//            return nil
//        }
//        
//        // Convert to pixel buffer
//        guard let pixelBuffer = cgImage.toPixelBuffer(
//            width: Int(inputSize.width),
//            height: Int(inputSize.height)
//        ) else {
//            return nil
//        }
//        
//        // Convert pixel buffer to normalized float array
//        let imageData = pixelBufferToFloatArray(
//            pixelBuffer: pixelBuffer,
//            width: Int(inputSize.width),
//            height: Int(inputSize.height)
//        )
//        
//        return Data(bytes: imageData, count: imageData.count * MemoryLayout<Float32>.size)
//    }
//    
//    private func pixelBufferToFloatArray(pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Float32] {
//        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
//        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0)) }
//        
//        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
//            return []
//        }
//        
//        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
//        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
//        
//        var floatArray: [Float32] = []
//        floatArray.reserveCapacity(width * height * 3)
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let pixelIndex = y * bytesPerRow + x * 4 // BGRA format
//                
//                let r = Float32(buffer[pixelIndex + 1]) / 255.0
//                let g = Float32(buffer[pixelIndex + 2]) / 255.0
//                let b = Float32(buffer[pixelIndex + 3]) / 255.0
//                
//                floatArray.append(r)
//                floatArray.append(g)
//                floatArray.append(b)
//            }
//        }
//        
//        return floatArray
//    }
//    
//    // ✅ 6D TO EULER CONVERSION
//    private func convert6DToEuler(_ rotation6D: [Double]) -> (Double, Double, Double) {
//        let x_raw = [rotation6D[0], rotation6D[1], rotation6D[2]]
//        let y_raw = [rotation6D[3], rotation6D[4], rotation6D[5]]
//        
//        let x_norm = sqrt(x_raw[0]*x_raw[0] + x_raw[1]*x_raw[1] + x_raw[2]*x_raw[2])
//        guard x_norm > 1e-8 else { return (0, 0, 0) }
//        let x = x_raw.map { $0 / x_norm }
//        
//        let dot = y_raw[0]*x[0] + y_raw[1]*x[1] + y_raw[2]*x[2]
//        
//        let y_ortho = [
//            y_raw[0] - dot * x[0],
//            y_raw[1] - dot * x[1],
//            y_raw[2] - dot * x[2]
//        ]
//        
//        let y_norm = sqrt(y_ortho[0]*y_ortho[0] + y_ortho[1]*y_ortho[1] + y_ortho[2]*y_ortho[2])
//        guard y_norm > 1e-8 else { return (0, 0, 0) }
//        let y = y_ortho.map { $0 / y_norm }
//        
//        let z = [
//            x[1]*y[2] - x[2]*y[1],
//            x[2]*y[0] - x[0]*y[2],
//            x[0]*y[1] - x[1]*y[0]
//        ]
//        
//        let R = [
//            [x[0], y[0], z[0]],
//            [x[1], y[1], z[1]],
//            [x[2], y[2], z[2]]
//        ]
//        
//        let (pitch, yaw, roll) = rotationMatrixToEulerXYZ(R)
//        return (yaw, pitch, roll)
//    }
//    
//    private func rotationMatrixToEulerXYZ(_ R: [[Double]]) -> (Double, Double, Double) {
//        let sy = sqrt(R[0][0]*R[0][0] + R[1][0]*R[1][0])
//        let singular = sy < 1e-6
//        
//        let x, y, z: Double
//        
//        if !singular {
//            x = atan2(R[2][1], R[2][2])
//            y = atan2(-R[2][0], sy)
//            z = atan2(R[1][0], R[0][0])
//        } else {
//            x = atan2(-R[1][2], R[1][1])
//            y = atan2(-R[2][0], sy)
//            z = 0
//        }
//        
//        return (x * 180.0 / .pi, y * 180.0 / .pi, z * 180.0 / .pi)
//    }
//    
//    // Helper method to resize UIImage
//    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
//        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
//        defer { UIGraphicsEndImageContext() }
//        image.draw(in: CGRect(origin: .zero, size: size))
//        return UIGraphicsGetImageFromCurrentImageContext()
//    }
//}
//
//// MARK: - ✅ FIXED Camera Manager with Proper Orientation Alignment
//class CameraManager: NSObject, ObservableObject {
//    let session = AVCaptureSession()
//    private let photoOutput = AVCapturePhotoOutput()
//    private let videoOutput = AVCaptureVideoDataOutput()
//    private var completion: ((UIImage?) -> Void)?
//    private var isConfigured = false
//    
//    // ✅ Published properties for UI binding
//    @Published var faceBoxes: [CGRect] = []
//    @Published private(set) var croppedHeads: [UIImage] = []
//    
//    // ✅ Head pose detector
//    private let headPoseDetector = HeadPoseDetector()
//    
//    // ✅ Maximum number of heads to keep in queue
//    let maxQueueSize = 20
//    
//    // ✅ Processing throttle to avoid overwhelming the model
//    private var lastProcessTime: Date = Date()
//    private let processingInterval: TimeInterval = 0.1
//    
//    // ✅ Video processing queue
//    private let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
//    
//    // ✅ Preview layer & current view size
//    var previewLayer: AVCaptureVideoPreviewLayer?
//    private var currentViewSize: CGSize = .zero
//    
//    // ✅ Head pose callback
//    var onHeadPoseUpdate: ((HeadPoseResult) -> Void)?
//    
//    override init() {
//        super.init()
//        setupCamera()
//        
//        // Keep orientation notifications for reference but don't auto-change
//        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(deviceOrientationDidChange),
//            name: UIDevice.orientationDidChangeNotification,
//            object: nil
//        )
//    }
//
//    deinit {
//        NotificationCenter.default.removeObserver(self)
//        UIDevice.current.endGeneratingDeviceOrientationNotifications()
//    }
//    
//    // ✅ FIXED: Camera setup with aligned orientations
//    func setupCamera() {
//        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
//        
//        guard !isConfigured else {
//            if !session.isRunning {
//                DispatchQueue.global(qos: .userInitiated).async {
//                    self.session.startRunning()
//                }
//            }
//            return
//        }
//        
//        session.beginConfiguration()
//        
//        session.inputs.forEach { session.removeInput($0) }
//        session.outputs.forEach { session.removeOutput($0) }
//        
//        // ✅ Use back camera
//        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
//           let input = try? AVCaptureDeviceInput(device: device),
//           session.canAddInput(input) {
//            session.addInput(input)
//        }
//        
//        // ✅ Add photo output
//        if session.canAddOutput(photoOutput) {
//            session.addOutput(photoOutput)
//        }
//        
//        // ✅ Configure video output with fixed orientation to match Vision (.down)
//        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
//        videoOutput.videoSettings = [
//            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
//        ]
//        
//        if session.canAddOutput(videoOutput) {
//            session.addOutput(videoOutput)
//            
//            // ✅ CRITICAL: Set video connection to match Vision orientation (.down = 180°)
//            if let connection = videoOutput.connection(with: .video) {
//                if #available(iOS 17.0, *) {
//                    if connection.isVideoRotationAngleSupported(0) {
//                        connection.videoRotationAngle = 0
//                    }
//                } else {
//                    if connection.isVideoOrientationSupported {
//                        connection.videoOrientation = .portraitUpsideDown
//                    }
//                }
//                connection.isVideoMirrored = false
//            }
//        }
//        
//        if session.canSetSessionPreset(.high) {
//            session.sessionPreset = .high
//        }
//        
//        session.commitConfiguration()
//        isConfigured = true
//        
//        DispatchQueue.global(qos: .userInitiated).async {
//            self.session.startRunning()
//        }
//    }
//    
//    // ✅ FIXED: Preview setup with aligned orientation
//    func setupPreview(in view: UIView, viewSize: CGSize) {
//        let layer = AVCaptureVideoPreviewLayer(session: session)
//        layer.videoGravity = .resizeAspectFill
//        layer.frame = CGRect(origin: .zero, size: viewSize)
//        
//        // ✅ CRITICAL: Set preview layer to match Vision orientation (.down = 180°)
//        if let connection = layer.connection {
//            if #available(iOS 17.0, *) {
//                if connection.isVideoRotationAngleSupported(90) {
//                    connection.videoRotationAngle = 90
//                }
//            } else {
//                if connection.isVideoOrientationSupported {
//                    connection.videoOrientation = .portraitUpsideDown
//                }
//            }
//        }
//        
//        view.layer.sublayers?.removeAll()
//        view.layer.addSublayer(layer)
//        previewLayer = layer
//        currentViewSize = viewSize
//        
//        print("✅ Preview layer orientation set to match Vision (.down/180°)")
//    }
//    
//    func updateViewSize(_ size: CGSize) {
//        currentViewSize = size
//        previewLayer?.frame = CGRect(origin: .zero, size: size)
//    }
//    
//    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
//        self.completion = completion
//        let settings = AVCapturePhotoSettings()
//        settings.flashMode = .auto
//        photoOutput.capturePhoto(with: settings, delegate: self)
//    }
//    
//    // ✅ FIXED: Vision detection with .down orientation (works correctly for tracking)
//    private func detectFaces(in pixelBuffer: CVPixelBuffer) {
//        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
//            guard let self = self,
//                  let faces = req.results as? [VNFaceObservation]
//            else { return }
//            self.handleDetections(faces, from: pixelBuffer)
//        }
//
//        // Keep .down orientation since tracking works correctly
//        let handler = VNImageRequestHandler(
//            cvPixelBuffer: pixelBuffer,
//            orientation: .downMirrored,
//            options: [:]
//        )
//        try? handler.perform([request])
//    }
//    
//    // ✅ FIXED: Handle detections with proper coordinate transformation
//    private func handleDetections(
//        _ faces: [VNFaceObservation],
//        from pixelBuffer: CVPixelBuffer
//    ) {
//        guard let preview = previewLayer,
//              currentViewSize != .zero
//        else { return }
//
//        let ci = CIImage(cvPixelBuffer: pixelBuffer)
//        let ctx = CIContext()
//        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
//        let fullImage = UIImage(cgImage: cg)
//
//        var boxes: [CGRect] = []
//        var crops: [UIImage] = []
//
//        for (index, face) in faces.enumerated() {
//            let visionRect = face.boundingBox
//            
//            // ✅ Use built-in coordinate transformation (handles orientation automatically)
//            let previewRect = preview.layerRectConverted(fromMetadataOutputRect: visionRect)
//            
//            // Debug logging for first face only
//            if index == 0 {
////                print("=== Face \(index) ===")
////                print("Vision rect: \(visionRect)")
////                print("Preview rect: \(previewRect)")
////                print("Preview layer bounds: \(preview.bounds)")
////                print("Current view size: \(currentViewSize)")
////                print("Preview layer frame: \(preview.frame)")
////                print("==================")
//            }
//            
//            boxes.append(previewRect)
//
//            if let head = cropHeadImage(from: fullImage, boundingBox: visionRect) {
//                crops.append(head)
//            }
//        }
//
//        DispatchQueue.main.async {
//            self.faceBoxes = boxes
//            self.croppedHeads.append(contentsOf: crops)
//            if self.croppedHeads.count > self.maxQueueSize {
//                self.croppedHeads.removeFirst(
//                    self.croppedHeads.count - self.maxQueueSize
//                )
//            }
//            self.processLatestCropForHeadPose()
//        }
//    }
//    
//    private func processLatestCropForHeadPose() {
//        let now = Date()
//        guard now.timeIntervalSince(lastProcessTime) >= processingInterval,
//              let latestCrop = croppedHeads.last else {
//            return
//        }
//        
//        lastProcessTime = now
//        
//        headPoseDetector.detectHeadPose(from: latestCrop) { [weak self] result in
//            if let result = result {
//                self?.onHeadPoseUpdate?(result)
//            }
//        }
//    }
//    
//    private func cropHeadImage(
//        from image: UIImage,
//        boundingBox box: CGRect
//    ) -> UIImage? {
//        guard let cgImage = image.cgImage else { return nil }
//        
//        let padding: CGFloat = 0.3
//        let imageWidth = CGFloat(cgImage.width)
//        let imageHeight = CGFloat(cgImage.height)
//        
//        let paddedBox = CGRect(
//            x: max(0, box.minX - padding * box.width),
//            y: max(0, box.minY - padding * box.height),
//            width: min(1, box.maxX + padding * box.width) - max(0, box.minX - padding * box.width),
//            height: min(1, box.maxY + padding * box.height) - max(0, box.minY - padding * box.height)
//        )
//        
//        // For cropping, Vision coordinates work directly
//        let cropRect = CGRect(
//            x: paddedBox.minX * imageWidth,
//            y: (1 - paddedBox.maxY) * imageHeight,
//            width: paddedBox.width * imageWidth,
//            height: paddedBox.height * imageHeight
//        )
//        
//        let clampedRect = CGRect(
//            x: max(0, min(cropRect.minX, imageWidth - 1)),
//            y: max(0, min(cropRect.minY, imageHeight - 1)),
//            width: min(cropRect.width, imageWidth - max(0, cropRect.minX)),
//            height: min(cropRect.height, imageHeight - max(0, cropRect.minY))
//        )
//        
//        guard let cgCrop = cgImage.cropping(to: clampedRect) else {
//            return nil
//        }
//        
//        return UIImage(cgImage: cgCrop, scale: image.scale, orientation: image.imageOrientation)
//    }
//    
//    // ✅ Don't automatically change orientation - keep it fixed for landscape use
//    @objc private func deviceOrientationDidChange() {
//        //print("Device orientation changed but keeping camera orientation fixed for landscape use")
//    }
//}
//
//// ✅ Photo Capture Delegate
//extension CameraManager: AVCapturePhotoCaptureDelegate {
//    func photoOutput(
//        _ output: AVCapturePhotoOutput,
//        didFinishProcessingPhoto photo: AVCapturePhoto,
//        error: Error?
//    ) {
//        guard let data = photo.fileDataRepresentation(),
//              let img = UIImage(data: data) else {
//            completion?(nil)
//            return
//        }
//        completion?(img)
//        completion = nil
//    }
//}
//
//// MARK: - ✅ AVCaptureVideoDataOutputSampleBufferDelegate
//extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
//    func captureOutput(
//        _ output: AVCaptureOutput,
//        didOutput sampleBuffer: CMSampleBuffer,
//        from connection: AVCaptureConnection
//    ) {
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//            return
//        }
//        detectFaces(in: pixelBuffer)
//    }
//}
//
//// MARK: - Enhanced Volume Button Manager with iOS 13+ compatibility
//class VolumeButtonManager: NSObject, ObservableObject {
//    private var volumeView: MPVolumeView?
//    private var audioSession = AVAudioSession.sharedInstance()
//    private var isListening = false
//    private var volumeSlider: UISlider?
//    
//    private let targetVolume: Float = 0.5
//    private let volumeBuffer: Float = 0.1
//    
//    private var isResettingVolume = false
//    private var lastResetTime: Date = Date()
//    private let resetCooldown: TimeInterval = 0.5
//    
//    var onVolumeButtonPressed: (() -> Void)?
//    
//    override init() {
//        super.init()
//        setupAudioSession()
//    }
//    
//    private func setupAudioSession() {
//        do {
//            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
//            try audioSession.setActive(true)
//        } catch {
//            print("Failed to setup audio session: \(error)")
//        }
//    }
//    
//    private func setupVolumeView() {
//        DispatchQueue.main.async {
//            self.volumeView?.removeFromSuperview()
//            
//            self.volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
//            self.volumeView?.clipsToBounds = true
//            self.volumeView?.isUserInteractionEnabled = false
//            self.volumeView?.alpha = 0.0001
//            self.volumeView?.showsVolumeSlider = true
//            
//            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//               let keyWindow = windowScene.windows.first(where: \.isKeyWindow) {
//                keyWindow.addSubview(self.volumeView!)
//                keyWindow.sendSubviewToBack(self.volumeView!)
//                
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                    self.findVolumeSlider()
//                }
//            }
//        }
//    }
//    
//    private func findVolumeSlider() {
//        guard let volumeView = volumeView else { return }
//        
//        for subview in volumeView.subviews {
//            if let slider = subview as? UISlider {
//                volumeSlider = slider
//                self.setVolumeToTarget()
//                break
//            }
//        }
//    }
//    
//    private func setVolumeToTarget() {
//        guard let slider = volumeSlider else { return }
//        
//        let currentVolume = audioSession.outputVolume
//        
//        if currentVolume <= volumeBuffer || currentVolume >= (1.0 - volumeBuffer) {
//            isResettingVolume = true
//            lastResetTime = Date()
//            slider.value = targetVolume
//            
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                self.isResettingVolume = false
//            }
//        }
//    }
//    
//    func startListening() {
//        guard !isListening else { return }
//        
//        isListening = true
//        setupVolumeView()
//        audioSession.addObserver(self, forKeyPath: "outputVolume", options: [.new, .old], context: nil)
//    }
//    
//    func stopListening() {
//        guard isListening else { return }
//        
//        isListening = false
//        audioSession.removeObserver(self, forKeyPath: "outputVolume")
//        
//        DispatchQueue.main.async {
//            self.volumeView?.removeFromSuperview()
//            self.volumeView = nil
//            self.volumeSlider = nil
//        }
//    }
//    
//    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
//        if keyPath == "outputVolume" && isListening {
//            guard let change = change,
//                  let newValue = change[.newKey] as? Float,
//                  let oldValue = change[.oldKey] as? Float else {
//                return
//            }
//            
//            if isResettingVolume {
//                return
//            }
//            
//            let timeSinceReset = Date().timeIntervalSince(lastResetTime)
//            if timeSinceReset < resetCooldown {
//                return
//            }
//            
//            let volumeDifference = abs(newValue - oldValue)
//            if volumeDifference > 0.001 {
//                DispatchQueue.main.async {
//                    self.onVolumeButtonPressed?()
//                    self.smartVolumeReset(oldValue: oldValue, newValue: newValue)
//                }
//            }
//        }
//    }
//    
//    private func smartVolumeReset(oldValue: Float, newValue: Float) {
//        guard let slider = volumeSlider else { return }
//        
//        let volumeWentUp = newValue > oldValue
//        let resetVolume: Float
//        
//        if newValue <= volumeBuffer {
//            resetVolume = targetVolume
//        } else if newValue >= (1.0 - volumeBuffer) {
//            resetVolume = targetVolume
//        } else {
//            if volumeWentUp {
//                resetVolume = max(volumeBuffer, newValue - 0.1)
//            } else {
//                resetVolume = min(1.0 - volumeBuffer, newValue + 0.1)
//            }
//        }
//        
//        isResettingVolume = true
//        lastResetTime = Date()
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            slider.value = resetVolume
//            
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                self.isResettingVolume = false
//            }
//        }
//    }
//    
//    deinit {
//        stopListening()
//    }
//}
//
//// MARK: - Camera Preview SwiftUI Integration
//struct CameraPreview: UIViewRepresentable {
//    let cameraManager: CameraManager
//    let viewSize: CGSize
//    
//    func makeUIView(context: Context) -> UIView {
//        let view = UIView(frame: .zero)
//        cameraManager.setupPreview(in: view, viewSize: viewSize)
//        return view
//    }
//    
//    func updateUIView(_ uiView: UIView, context: Context) {
//        cameraManager.updateViewSize(viewSize)
//    }
//}
//
//// MARK: - ImageView is imported from separate file
//
//// MARK: - ✅ FIXED Main Content View - NO BLACK BAR
//struct ContentView: View {
//    @StateObject private var cameraManager = CameraManager()
//    @StateObject private var volumeButtonManager = VolumeButtonManager()
//    @State private var capturedImages: [UIImage] = Array(repeating: UIImage(), count: 9)
//    @State private var croppedEyeImages: [UIImage] = Array(repeating: UIImage(), count: 9)
//    @State private var captureStatus: [Bool] = Array(repeating: false, count: 9)
//    @State private var captureSequence: [Int] = [4, 1, 2, 5, 8, 7, 6, 3, 0]
//    @State private var currentCaptureIndex = 0
//    @State private var isShowingResults = false
//    @State private var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
//    @State private var showingPermissionAlert = false
//    @State private var isProcessing = false
//    @State private var redoIndex: Int? = nil
//    @State private var isInRedoMode = false
//    
//    // STABLE Face tracking states with improved filtering
//    @State private var yaw: Double = 0
//    @State private var pitch: Double = 0
//    @State private var roll: Double = 0
//    @State private var showFaceTracking = true
//    @State private var isFaceDetected = false
//    
//    // Raw values (before filtering)
//    @State private var rawYaw: Double = 0
//    @State private var rawPitch: Double = 0
//    @State private var rawRoll: Double = 0
//    
//    // IMPROVED Low pass filters - increased for stability without lag
//    @State private var yawFilter = LowPassFilter(samples: 8)
//    @State private var pitchFilter = LowPassFilter(samples: 8)
//    @State private var rollFilter = LowPassFilter(samples: 8)
//    
//    // Store face tracking data for each captured image
//    @State private var capturedFaceData: [(yaw: Double, pitch: Double, roll: Double)] = Array(repeating: (yaw: 0, pitch: 0, roll: 0), count: 9)
//    
//    // MARK: - Baseline offset system for personalized guidance
//    @State private var baselineYaw: Double = 0.0
//    @State private var baselinePitch: Double = 0.0
//    @State private var baselineRoll: Double = 0.0
//    @State private var hasBaseline = false
//    
//    // MARK: - Face tracking logging states
//    @State private var isLogging = false
//    @State private var logStartTime: Date = Date()
//    @State private var faceTrackingLogs: [(timestamp: TimeInterval, yaw: Double, pitch: Double, roll: Double)] = []
//    @State private var showingLogAlert = false
//    @State private var logFileName = ""
//    @State private var showingShareSheet = false
//    @State private var logFileURL: URL?
//
//    var body: some View {
//        // ✅ FIXED: TRUE FULLSCREEN - No black bars
//        GeometryReader { geometry in
//            if cameraPermissionStatus == .denied {
//                permissionDeniedView
//            } else if isShowingResults {
//                ImageView(
//                    images: getFilledImages(),
//                    faceData: getFilledFaceData(),
//                    onRedo: { displayIndex in
//                        print("🔄 Going back to camera to manually retake image at display index: \(displayIndex)")
//                        isShowingResults = false  // Go back to camera UI
//                        redoIndex = displayIndex  // Set which image to replace
//                        isInRedoMode = true      // ✅ NEW: Set redo mode flag
//                        isProcessing = false     // Make sure camera button is enabled
//                    },
//                    onBack: {
//                        resetCapture()
//                    }
//                )
//
//            } else {
//                cameraView(geometry: geometry)
//            }
//        }
//        .ignoresSafeArea(.all) // ✅ CRITICAL: Ignore ALL safe areas for true fullscreen
//        .statusBarHidden(true) // ✅ CRITICAL: Hide status bar completely
//        .onAppear {
//            checkCameraPermission()
//            setupVolumeButtonCapture()
//            setupFaceTrackingCallback()
//        }
//        .onDisappear {
//            volumeButtonManager.stopListening()
//        }
//        .alert("Camera Permission Required", isPresented: $showingPermissionAlert) {
//            Button("Settings") {
//                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
//            }
//            Button("Cancel", role: .cancel) { }
//        } message: {
//            Text("Please allow camera access in Settings to use this app.")
//        }
//        .alert("Face Tracking Log Generated", isPresented: $showingLogAlert) {
//            Button("Save File") {
//                showingShareSheet = true
//            }
//            Button("Back") { }
//        } message: {
//            Text("Log file '\(logFileName)' has been generated with \(faceTrackingLogs.count) data points. Tap 'Share File' to save or send it.")
//        }
//        .sheet(isPresented: $showingShareSheet) {
//            if let url = logFileURL {
//                ActivityViewController(activityItems: [url])
//            }
//        }
//        .preferredColorScheme(.dark)
//        .onChange(of: yaw) { _, _ in logFaceTrackingData() }
//        .onChange(of: pitch) { _, _ in logFaceTrackingData() }
//        .onChange(of: roll) { _, _ in logFaceTrackingData() }
//    }
//    
//    // MARK: - Setup Face Tracking Callback
//    private func setupFaceTrackingCallback() {
//        cameraManager.onHeadPoseUpdate = { [self] result in
//            self.rawYaw = result.yaw
//            self.rawPitch = result.pitch
//            self.rawRoll = result.roll
//            
//            if result.yaw == 0.0 && result.pitch == 0.0 && result.roll == 0.0 {
//                self.isFaceDetected = false
//                
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//                    if self.rawYaw == 0.0 && self.rawPitch == 0.0 && self.rawRoll == 0.0 {
//                        self.yawFilter.reset()
//                        self.pitchFilter.reset()
//                        self.rollFilter.reset()
//                        
//                        // ✅ Set to NaN when no face detected
//                        self.yaw = Double.nan
//                        self.pitch = Double.nan
//                        self.roll = Double.nan
//                    }
//                }
//            } else {
//                self.isFaceDetected = true
//                
//                self.yaw = yawFilter.addValue(result.yaw)
//                self.pitch = pitchFilter.addValue(result.pitch)
//                self.roll = rollFilter.addValue(result.roll)
//            }
//        }
//    }
//    
//    // MARK: - Helper functions for the sequence system
//    private func getFilledImages() -> [UIImage] {
//        return croppedEyeImages.enumerated().compactMap { index, image in
//            captureStatus[index] ? image : nil
//        }
//    }
//    
//    private func getFilledFaceData() -> [(yaw: Double, pitch: Double, roll: Double)] {
//        return capturedFaceData.enumerated().compactMap { index, data in
//            captureStatus[index] ? data : nil
//        }
//    }
//    
//    private func getCurrentPhotoNumber() -> Int {
//        if let redoIndex = redoIndex {
//            return redoIndex + 1  // ✅ Show which photo is being retaken
//        }
//        
//        if currentCaptureIndex < captureSequence.count {
//            return captureSequence[currentCaptureIndex] + 1
//        }
//        return 1
//    }
//    
//    private func getTotalCaptured() -> Int {
//        return captureStatus.filter { $0 }.count
//    }
//    
//    // MARK: Permission-denied placeholder
//    private var permissionDeniedView: some View {
//        VStack(spacing: 20) {
//            Image(systemName: "camera.fill")
//                .font(.system(size: 60))
//                .foregroundColor(.gray)
//            Text("Camera Access Required")
//                .font(.title2).bold()
//            Text("Please enable camera access in Settings to capture photos.")
//                .multilineTextAlignment(.center)
//                .foregroundColor(.secondary)
//            Button("Open Settings") {
//                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
//            }
//            .buttonStyle(.borderedProminent)
//        }
//        .padding()
//    }
//    
//    // ✅ FIXED: Camera view with proper fullscreen positioning
//    private func cameraView(geometry: GeometryProxy) -> some View {
//        let screenBounds = UIScreen.main.bounds
//        let safeArea = UIApplication.shared.windows.first?.safeAreaInsets ?? UIEdgeInsets.zero
//        
//        return ZStack {
//            // ✅ FIXED: Camera Preview - TRUE FULLSCREEN
//            CameraPreview(cameraManager: cameraManager, viewSize: screenBounds.size)
//                .ignoresSafeArea(.all)
//                .onAppear { cameraManager.setupCamera() }
//            
//            // ✅ Vision Face Bounding Boxes
//            ForEach(cameraManager.faceBoxes.indices, id: \.self) { i in
//                let rect = cameraManager.faceBoxes[i]
//                Rectangle()
//                    .stroke(Color.red, lineWidth: 2)
//                    .frame(width: rect.width, height: rect.height)
//                    .position(x: rect.midX, y: rect.midY)
//            }
//            
//            // ✅ FIXED: Camera Button - Properly positioned from bottom
//            // MARK: - Updated camera button with redo mode support
//            Button(action: {
//                if isInRedoMode {
//                    capturePhoto(replaceAt: redoIndex) // ✅ Pass the redoIndex explicitly
//                } else {
//                    capturePhoto(replaceAt: nil) // ✅ Normal capture
//                }
//            }) {
//                ZStack {
//                    Circle()
//                        .fill(Color.white)
//                        .frame(width: 80, height: 80)
//                    Circle()
//                        .stroke(Color.white, lineWidth: 3)
//                        .frame(width: 90, height: 90)
//                    if isProcessing {
//                        ProgressView()
//                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
//                    }
//                }
//            }
//            .disabled(isProcessing || (getTotalCaptured() >= 9 && !isInRedoMode)) // ✅ Allow captures in redo mode
//
//
//            .position(
//                x: screenBounds.width * 0.5,
//                y: screenBounds.height - safeArea.bottom - 100
//            )
//            
//            // ✅ FIXED: Face Tracking Panel - Account for notch/dynamic island
//            HStack(spacing: 12) {
//                faceTrackingPanel(geometry: geometry)
//            }
//            .position(
//                x: screenBounds.width * 0.15,
//                y: safeArea.top + 120
//            )
//            
//            // ✅ FIXED: Photo Preview Panel
//            HStack(spacing: 12) {
//                photoPreviewPanel(geometry: geometry)
//            }
//            .position(
//                x: screenBounds.width * 0.15,
//                y: screenBounds.height * 0.51
//            )
//            
//            // ✅ FIXED: Yaw Guidance Panel
//            HStack(spacing: 12) {
//                yawGuidanceView(geometry: geometry)
//            }
//            .position(
//                x: screenBounds.width * 0.15,
//                y: screenBounds.height * 0.74
//            )
//            
//            // ✅ FIXED: Face Tracking Logger Button
//            HStack(spacing: 12) {
//                faceTrackingLoggerButton(geometry: geometry)
//            }
//            .position(
//                x: screenBounds.width * 0.85,
//                y: safeArea.top + 120
//            )
//            
//            // ✅ CENTER GUIDE BOX
//            RoundedRectangle(cornerRadius: 8)
//                .stroke(Color.green, lineWidth: 3)
//                .background(Color.clear)
//                .frame(width: 150, height: 150)
//                .position(
//                    x: screenBounds.width * 0.5,
//                    y: screenBounds.height * 0.5
//                )
//        }
//    }
//    
//    // MARK: - Face Tracking Logger Button
//    private func faceTrackingLoggerButton(geometry: GeometryProxy) -> some View {
//        Button(action: toggleFaceTrackingLogger) {
//            VStack(spacing: 8) {
//                Image(systemName: isLogging ? "stop.circle.fill" : "record.circle")
//                    .font(.system(size: max(30, geometry.size.width * 0.04)))
//                    .foregroundColor(isLogging ? .red : .white)
//                
//                Text(isLogging ? "STOP" : "LOG")
//                    .font(.caption).bold()
//                    .foregroundColor(isLogging ? .red : .white)
//                
//                if isLogging {
//                    Text("\(faceTrackingLogs.count)")
//                        .font(.caption2)
//                        .foregroundColor(.red)
//                }
//            }
//            .padding(12)
//            .background(
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(isLogging ? Color.black.opacity(0.8) : Color.white.opacity(0.2))
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 12)
//                            .stroke(isLogging ? Color.red : Color.white, lineWidth: 2)
//                    )
//                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
//            )
//        }
//        .rotationEffect(.degrees(90))
//        .frame(
//            minWidth: max(80, geometry.size.width * 0.1),
//            minHeight: max(100, geometry.size.height * 0.12)
//        )
//    }
//    
//    // MARK: - Face Tracking Logger Functions
//    private func toggleFaceTrackingLogger() {
//        if isLogging {
//            stopFaceTrackingLogger()
//        } else {
//            startFaceTrackingLogger()
//        }
//    }
//
//    private func startFaceTrackingLogger() {
//        isLogging = true
//        logStartTime = Date()
//        faceTrackingLogs.removeAll()
//        
//        print("🔴 Started logging face tracking values")
//    }
//
//    private func stopFaceTrackingLogger() {
//        isLogging = false
//        print("⏹️ Stopped logging with \(faceTrackingLogs.count) total data points")
//        
//        if !faceTrackingLogs.isEmpty {
//            generateLogFile()
//        }
//    }
//    
//    private func logFaceTrackingData() {
//        guard isLogging else { return }
//        
//        let timestamp = Date().timeIntervalSince(logStartTime)
//        
//        let logEntry = (
//            timestamp: timestamp,
//            yaw: yaw,
//            pitch: pitch,
//            roll: roll
//        )
//        
//        faceTrackingLogs.append(logEntry)
//        
//        // Prevent memory overflow
//        if faceTrackingLogs.count > 15000 {
//            faceTrackingLogs.removeFirst(1000)
//        }
//    }
//    
//    private func generateLogFile() {
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
//        let timestamp = dateFormatter.string(from: logStartTime)
//        let fileName = "face_tracking_\(timestamp).txt"
//        
//        var logContent = "Timestamp,Yaw,Pitch,Roll\n"
//        
//        for entry in faceTrackingLogs {
//            logContent += String(format: "%.3f,%.2f,%.2f,%.2f\n",
//                               entry.timestamp,
//                               entry.yaw,
//                               entry.pitch,
//                               entry.roll)
//        }
//        
//        let tempDirectory = FileManager.default.temporaryDirectory
//        let fileURL = tempDirectory.appendingPathComponent(fileName)
//        
//        do {
//            try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
//            
//            logFileURL = fileURL
//            logFileName = fileName
//            showingLogAlert = true
//            
//        } catch {
//            print("❌ Error creating log file: \(error)")
//        }
//    }
//    
//    // MARK: - Face Tracking Panel
//    private func faceTrackingPanel(geometry: GeometryProxy) -> some View {
//        HStack(spacing: 14) {
//            VStack(spacing: 4) {
//                Image(systemName: showFaceTracking ? "eye.fill" : "eye.slash.fill")
//                    .font(.title3)
//                    .foregroundColor(.black)
//                    .onTapGesture { showFaceTracking.toggle() }
//                
//                HStack(spacing: 2) {
//                    Circle()
//                        .fill(isFaceDetected ? Color.green : Color.gray)
//                        .frame(width: 6, height: 6)
//                    Text("FACE")
//                        .font(.caption2)
//                        .foregroundColor(.black)
//                }
//                
//                Text("Q:\(cameraManager.croppedHeads.count)")
//                    .font(.caption2)
//                    .foregroundColor(.blue)
//            }
//
//            if showFaceTracking {
//                HStack(spacing: 15) {
//                    VStack(spacing: 2) {
//                        Image(systemName: "arrow.left.and.right")
//                            .font(.caption)
//                        Text("YAW")
//                            .font(.caption2).bold()
//                        Text(String(format: "%.0f°", (hasBaseline ? yaw - baselineYaw : yaw).isNaN ? 0 : (hasBaseline ? yaw - baselineYaw : yaw)))
//                            .font(.caption).bold()
//                    }
//                    .foregroundColor(.red)
//                    .frame(minWidth: max(40, geometry.size.width * 0.05))
//
//                    VStack(spacing: 2) {
//                        Image(systemName: "arrow.up.and.down")
//                            .font(.caption)
//                        Text("PITCH")
//                            .font(.caption2).bold()
//                        Text(String(format: "%.0f°", (hasBaseline ? pitch - baselinePitch : pitch).isNaN ? 0 : (hasBaseline ? pitch - baselinePitch : pitch)))
//                            .font(.caption).bold()
//                    }
//                    .foregroundColor(.blue)
//                    .frame(minWidth: max(45, geometry.size.width * 0.055))
//
//                    VStack(spacing: 2) {
//                        Image(systemName: "rotate.3d")
//                            .font(.caption)
//                        Text("ROLL")
//                            .font(.caption2).bold()
//                        Text(String(format: "%.0f°", (hasBaseline ? roll - baselineRoll : roll).isNaN ? 0 : (hasBaseline ? roll - baselineRoll : roll)))
//                            .font(.caption).bold()
//                    }
//                    .foregroundColor(.green)
//                    .frame(minWidth: max(40, geometry.size.width * 0.05))
//                }
//            }
//        }
//        .padding(12)
//        .background(
//            RoundedRectangle(cornerRadius: 10)
//                .fill(Color.white.opacity(0.85))
//                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
//        )
//        .rotationEffect(.degrees(90))
//        .scaleEffect(1.0)
//        .frame(
//            minWidth: max(200, geometry.size.width * 0.25),
//            minHeight: max(80, geometry.size.height * 0.095)
//        )
//    }
//    
//    // MARK: - Photo Preview Panel
//    private func photoPreviewPanel(geometry: GeometryProxy) -> some View {
//        HStack(spacing: 8) {
//            let currentPhotoNumber = getCurrentPhotoNumber()
//            let name = "image\(currentPhotoNumber)"
//
//            if let img = UIImage(named: name) {
//                Image(uiImage: img)
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//                    .frame(
//                        width: max(60, geometry.size.width * 0.075),
//                        height: max(60, geometry.size.width * 0.075)
//                    )
//                    .clipped()
//                    .cornerRadius(8)
//            } else {
//                Image(systemName: "photo")
//                    .font(.system(size: max(40, geometry.size.width * 0.05)))
//                    .foregroundColor(.black)
//                    .frame(
//                        width: max(60, geometry.size.width * 0.075),
//                        height: max(60, geometry.size.width * 0.075)
//                    )
//            }
//
//            Text("\(currentPhotoNumber)/9")
//                .font(.title3).bold()
//                .foregroundColor(.black)
//        }
//        .padding(10)
//        .background(
//            RoundedRectangle(cornerRadius: 10)
//                .fill(Color.white.opacity(0.85))
//                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
//        )
//        .rotationEffect(.degrees(90))
//        .scaleEffect(1.0)
//        .frame(
//            minWidth: max(120, geometry.size.width * 0.15),
//            minHeight: max(80, geometry.size.height * 0.095)
//        )
//    }
//
//    // MARK: - Yaw Guidance View
//    private func yawGuidanceView(geometry: GeometryProxy) -> some View {
//        VStack(spacing: 8) {
//            Text(getYawGuidanceMessage())
//                .font(.title2)
//                .fontWeight(.heavy)
//                .foregroundColor(getYawGuidanceColor())
//                .multilineTextAlignment(.center)
//                .lineLimit(2)
//            
//            Text(getTargetYawRange())
//                .font(.caption)
//                .foregroundColor(.white.opacity(0.9))
//                .lineLimit(2)
//            
//            if hasBaseline {
//                Text("📍 Baseline Set")
//                    .font(.caption2)
//                    .foregroundColor(.cyan)
//            } else {
//                Text("📸 Capture Center First")
//                    .font(.caption2)
//                    .foregroundColor(.yellow)
//            }
//        }
//        .padding(.horizontal, max(20, geometry.size.width * 0.025))
//        .padding(.vertical, 12)
//        .background(
//            RoundedRectangle(cornerRadius: 15)
//                .fill(Color.black.opacity(0.7))
//                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
//        )
//        .rotationEffect(.degrees(90))
//        .scaleEffect(1.0)
//        .frame(
//            minWidth: max(180, geometry.size.width * 0.225),
//            minHeight: max(100, geometry.size.height * 0.12)
//        )
//    }
//    
//    // MARK: - Guidance Logic
//    private func getYawGuidanceMessage() -> String {
//        let currentPhotoNumber = getCurrentPhotoNumber()
//        
//        let offsetYaw = hasBaseline ? yaw - baselineYaw : yaw
//        let offsetPitch = hasBaseline ? pitch - baselinePitch : pitch
//        
//        // ✅ Check for no face (NaN values)
//        if offsetYaw.isNaN || offsetPitch.isNaN {
//            return "NO FACE"
//        }
//        
//        let yawGood = isYawInRange(offsetYaw, photoNumber: currentPhotoNumber)
//        let pitchGood = isPitchInRange(offsetPitch, photoNumber: currentPhotoNumber)
//        
//        if yawGood && pitchGood {
//            return "PERFECT! 👍"
//        }
//        
//        var guidance: [String] = []
//        
//        // ✅ Simple yaw guidance
//        if !yawGood {
//            switch currentPhotoNumber {
//            case 1, 4, 7: // Target: -17 < yaw < -13
//                if offsetYaw > -13 {
//                    guidance.append("Left")
//                }
//            case 2, 5, 8: // Target: -2 < yaw < 2
//                if offsetYaw < -2 {
//                    guidance.append("Right")
//                } else if offsetYaw > 2 {
//                    guidance.append("Left")
//                }
//            case 3, 6, 9: // Target: 13 < yaw < 17
//                if offsetYaw < 13 {
//                    guidance.append("Right")
//                }
//            default:
//                break
//            }
//        }
//        
//        // ✅ Simple pitch guidance
//        if !pitchGood {
//            switch currentPhotoNumber {
//            case 1, 2, 3: // Target: -17 < pitch < -13
//                if offsetPitch > -13 {
//                    guidance.append("Up")
//                }
//            case 4, 5, 6: // Target: -2 < pitch < 2
//                if offsetPitch < -2 {
//                    guidance.append("Up")
//                } else if offsetPitch > 2 {
//                    guidance.append("Down")
//                }
//            case 7, 8, 9: // Target: 13 < pitch < 17
//                if offsetPitch < 13 {
//                    guidance.append("Down")
//                }
//            default:
//                break
//            }
//        }
//        
//        if guidance.isEmpty {
//            return "HOLD"
//        } else if guidance.count == 1 {
//            return guidance[0]
//        } else {
//            return guidance.joined(separator: " & ")
//        }
//    }
//    
//    private func isYawInRange(_ yaw: Double, photoNumber: Int) -> Bool {
//        if yaw.isNaN { return false }
//        
//        switch photoNumber {
//        case 1, 4, 7:
//            return -17 < yaw && yaw < -13
//        case 2, 5, 8:
//            return -2 < yaw && yaw < 2
//        case 3, 6, 9:
//            return 13 < yaw && yaw < 17
//        default:
//            return -2 < yaw && yaw < 2
//        }
//    }
//
//    private func isPitchInRange(_ pitch: Double, photoNumber: Int) -> Bool {
//        if pitch.isNaN { return false }
//        
//        switch photoNumber {
//        case 1, 2, 3:
//            return -17 < pitch && pitch < -13
//        case 4, 5, 6:
//            return -2 < pitch && pitch < 2
//        case 7, 8, 9:
//            return 13 < pitch && pitch < 17
//        default:
//            return -2 < pitch && pitch < 2
//        }
//    }
//
//    private func getYawGuidanceColor() -> Color {
//        let message = getYawGuidanceMessage()
//        
//        if message.contains("PERFECT") {
//            return .green
//        } else if message.contains("GOOD") {
//            return .yellow
//        } else {
//            return .orange
//        }
//    }
//    
//    private func getTargetYawRange() -> String {
//        let currentPhotoNumber = getCurrentPhotoNumber()
//        
//        let yawText: String
//        let pitchText: String
//        
//        switch currentPhotoNumber {
//        case 1, 4, 7:
//            yawText = "Yaw: -17 < y < -13"
//        case 2, 5, 8:
//            yawText = "Yaw: -2 < y < 2"
//        case 3, 6, 9:
//            yawText = "Yaw: 13 < y < 17"
//        default:
//            yawText = "Yaw: -2 < y < 2"
//        }
//        
//        switch currentPhotoNumber {
//        case 1, 2, 3:
//            pitchText = "Pitch: -17 < p < -13"
//        case 4, 5, 6:
//            pitchText = "Pitch: -2 < p < 2"
//        case 7, 8, 9:
//            pitchText = "Pitch: 13 < p < 17"
//        default:
//            pitchText = "Pitch: -2 < p < 2"
//        }
//        
//        return "\(yawText)\n\(pitchText)"
//    }
//    
//    // MARK: Setup Volume Button Capture
//    private func setupVolumeButtonCapture() {
//        volumeButtonManager.onVolumeButtonPressed = {
//            if !self.isShowingResults && !self.isProcessing && self.getTotalCaptured() < 9 {
//                self.capturePhoto(replaceAt: nil)
//            }
//        }
//        volumeButtonManager.startListening()
//    }
//    
//    // MARK: - Fixed capturePhoto function with better redo handling
//    // MARK: - Fixed capturePhoto function with better redo handling
//    private func capturePhoto(replaceAt index: Int?) {
//        guard !isProcessing else { return }
//        isProcessing = true
//        
//        // ✅ Use the stored redoIndex if we're in redo mode
//        let targetRedoIndex = index ?? (isInRedoMode ? redoIndex : nil)
//        
//        print("📸 Capturing photo - Redo mode: \(targetRedoIndex != nil), Index: \(targetRedoIndex ?? -1)")
//        
//        cameraManager.capturePhoto { image in
//            DispatchQueue.main.async {
//                guard let img = image else {
//                    print("❌ Failed to capture image")
//                    self.isProcessing = false
//                    return
//                }
//                
//                let targetIndex: Int
//                if let idx = targetRedoIndex {
//                    // ✅ REDO MODE: Replace specific image
//                    targetIndex = idx
//                    print("🔄 Replacing image at index: \(idx)")
//                } else {
//                    // ✅ NORMAL MODE: Next in sequence
//                    if self.currentCaptureIndex < self.captureSequence.count {
//                        targetIndex = self.captureSequence[self.currentCaptureIndex]
//                        self.currentCaptureIndex += 1
//                        print("📷 Normal capture at index: \(targetIndex)")
//                    } else {
//                        print("❌ No more captures allowed")
//                        self.isProcessing = false
//                        return
//                    }
//                }
//                
//                // Store the full captured image first
//                self.capturedImages[targetIndex] = img
//                self.captureStatus[targetIndex] = true
//                
//                // Store face tracking data
//                self.capturedFaceData[targetIndex] = (yaw: self.yaw, pitch: self.pitch, roll: self.roll)
//                
//                // ✅ Set baseline only for center image (index 4) and only if not already set
//                if targetIndex == 4 && !self.hasBaseline && targetRedoIndex == nil {
//                    self.baselineYaw = self.yaw
//                    self.baselinePitch = self.pitch
//                    self.baselineRoll = self.roll
//                    self.hasBaseline = true
//                    print("📍 Baseline set: yaw=\(self.yaw), pitch=\(self.pitch), roll=\(self.roll)")
//                }
//                
//                // ✅ CRITICAL: Process for eye detection with proper completion handling
//                print("🔍 Starting eye detection for index: \(targetIndex)")
//                self.processImageForEyeDetection(img, at: targetIndex)
//            }
//        }
//    }
//    
//    // MARK: - Fixed processImageForEyeDetection with better error handling
//    private func processImageForEyeDetection(_ image: UIImage, at index: Int) {
//        print("🔍 Processing image for eye detection at index: \(index)")
//        
//        guard let cgImage = image.cgImage else {
//            print("❌ No CGImage available, using original")
//            finishCrop(image, at: index)
//            return
//        }
//        
//        let request = VNDetectFaceLandmarksRequest { request, error in
//            if let error = error {
//                print("❌ Face landmarks detection error: \(error)")
//                DispatchQueue.main.async {
//                    finishCrop(image, at: index)
//                }
//                return
//            }
//            
//            var croppedImage = image // Default fallback
//            
//            // If we found face landmarks, crop around the eyes
//            if let results = request.results as? [VNFaceObservation],
//               let face = results.first,
//               let landmarks = face.landmarks,
//               let leftEye = landmarks.leftEye,
//               let rightEye = landmarks.rightEye {
//                
//                print("✅ Face landmarks detected, cropping around eyes")
//                croppedImage = cropAroundEyes(
//                    image: image,
//                    face: face,
//                    leftEye: leftEye,
//                    rightEye: rightEye
//                )
//            } else {
//                print("⚠️ No face landmarks found, using original image")
//            }
//            
//            DispatchQueue.main.async {
//                finishCrop(croppedImage, at: index)
//            }
//        }
//        
//        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
//        
//        DispatchQueue.global(qos: .userInteractive).async {
//            do {
//                try handler.perform([request])
//            } catch {
//                print("❌ Failed to perform face landmarks request: \(error)")
//                DispatchQueue.main.async {
//                    finishCrop(image, at: index)
//                }
//            }
//        }
//    }
//    
//    private func cropAroundEyes(image: UIImage, face: VNFaceObservation, leftEye: VNFaceLandmarkRegion2D, rightEye: VNFaceLandmarkRegion2D) -> UIImage {
//        guard let cgImage = image.cgImage else {
//            print("❌ No CGImage for cropping")
//            return image
//        }
//        
//        let imageWidth = CGFloat(cgImage.width)
//        let imageHeight = CGFloat(cgImage.height)
//        
//        print("🖼️ Original image size: \(imageWidth) x \(imageHeight)")
//        
//        // Convert face bounding box to image coordinates
//        let faceBox = face.boundingBox
//        let faceRect = CGRect(
//            x: faceBox.minX * imageWidth,
//            y: (1 - faceBox.maxY) * imageHeight,
//            width: faceBox.width * imageWidth,
//            height: faceBox.height * imageHeight
//        )
//        
//        print("👤 Face rect: \(faceRect)")
//        
//        // ✅ BETTER VALIDATION: Check if face is reasonable
//        guard faceRect.width > 50 && faceRect.height > 50 else {
//            print("❌ Face too small (\(faceRect.width) x \(faceRect.height)), using original image")
//            return image
//        }
//        
//        // Get all eye landmark points in image coordinates
//        let leftEyePoints = leftEye.normalizedPoints.compactMap { point -> CGPoint? in
//            let x = faceRect.minX + point.x * faceRect.width
//            let y = faceRect.minY + (1 - point.y) * faceRect.height
//            
//            // ✅ VALIDATE each point is within image bounds
//            guard x >= 0 && x <= imageWidth && y >= 0 && y <= imageHeight else {
//                return nil
//            }
//            return CGPoint(x: x, y: y)
//        }
//        
//        let rightEyePoints = rightEye.normalizedPoints.compactMap { point -> CGPoint? in
//            let x = faceRect.minX + point.x * faceRect.width
//            let y = faceRect.minY + (1 - point.y) * faceRect.height
//            
//            // ✅ VALIDATE each point is within image bounds
//            guard x >= 0 && x <= imageWidth && y >= 0 && y <= imageHeight else {
//                return nil
//            }
//            return CGPoint(x: x, y: y)
//        }
//        
//        let allEyePoints = leftEyePoints + rightEyePoints
//        
//        print("👁️ Valid eye points: \(allEyePoints.count) (left: \(leftEyePoints.count), right: \(rightEyePoints.count))")
//        
//        // ✅ BETTER VALIDATION: Need at least 6 valid points
//        guard allEyePoints.count >= 6 else {
//            print("❌ Not enough valid eye points (\(allEyePoints.count)), using original image")
//            return image
//        }
//        
//        // Find bounding box of all eye points
//        let minX = allEyePoints.map(\.x).min() ?? 0
//        let maxX = allEyePoints.map(\.x).max() ?? imageWidth
//        let minY = allEyePoints.map(\.y).min() ?? 0
//        let maxY = allEyePoints.map(\.y).max() ?? imageHeight
//        
//        print("👁️ Eye bounds: (\(minX), \(minY)) to (\(maxX), \(maxY))")
//        
//        // ✅ STRICT VALIDATION: Ensure reasonable eye region
//        guard maxX > minX + 20 && maxY > minY + 10 else {
//            print("❌ Eye region too small: width=\(maxX-minX), height=\(maxY-minY)")
//            return image
//        }
//        
//        // Add padding around eyes
//        let padding: CGFloat = 30
//        let cropX = max(0, minX - padding)
//        let cropY = max(0, minY - padding)
//        let cropWidth = min(maxX - minX + 2 * padding, imageWidth - cropX)
//        let cropHeight = min(maxY - minY + 2 * padding, imageHeight - cropY)
//        
//        // ✅ FINAL STRICT VALIDATION
//        guard cropWidth > 50 && cropHeight > 20 &&
//              cropX >= 0 && cropY >= 0 &&
//              cropX + cropWidth <= imageWidth &&
//              cropY + cropHeight <= imageHeight else {
//            print("❌ Invalid crop dimensions: x=\(cropX), y=\(cropY), w=\(cropWidth), h=\(cropHeight)")
//            print("   Image size: \(imageWidth) x \(imageHeight)")
//            return image
//        }
//        
//        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
//        
//        print("✅ Valid crop: \(cropRect)")
//        
//        // Crop the image
//        if let croppedCGImage = cgImage.cropping(to: cropRect) {
//            let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)
//            print("✅ Successfully cropped image: \(croppedImage.size)")
//            return croppedImage
//        }
//        
//        print("❌ Failed to crop CGImage, using original")
//        return image
//    }
//    
//    // MARK: - Fixed finishCrop with proper completion handling
//    private func finishCrop(_ cropped: UIImage, at index: Int) {
//        print("✅ Finishing crop for index: \(index)")
//        
//        DispatchQueue.main.async {
//            // Store the cropped image
//            self.croppedEyeImages[index] = cropped
//            
//            // ✅ CRITICAL: Reset processing state
//            self.isProcessing = false
//            
//            // ✅ Clear redo mode states
//            if self.isInRedoMode {
//                self.isInRedoMode = false
//                self.redoIndex = nil
//                print("✅ Redo mode completed for index: \(index)")
//            }
//            
//            print("✅ Crop completed for index: \(index). Total captured: \(self.getTotalCaptured())")
//            
//            // Check if all 9 images are captured
//            if self.getTotalCaptured() == 9 {
//                print("🎉 All 9 images captured, showing results")
//                self.isShowingResults = true
//            }
//        }
//    }
//    
//    // MARK: - Reset
//    private func resetCapture() {
//        capturedImages = Array(repeating: UIImage(), count: 9)
//        croppedEyeImages = Array(repeating: UIImage(), count: 9)
//        captureStatus = Array(repeating: false, count: 9)
//        capturedFaceData = Array(repeating: (yaw: 0, pitch: 0, roll: 0), count: 9)
//        
//        currentCaptureIndex = 0
//        
//        baselineYaw = 0.0
//        baselinePitch = 0.0
//        baselineRoll = 0.0
//        hasBaseline = false
//        
//        isProcessing = false
//        isShowingResults = false
//        
//        // ✅ Clear redo mode states
//        redoIndex = nil
//        isInRedoMode = false
//        
//        yaw = Double.nan
//        pitch = Double.nan
//        roll = Double.nan
//        rawYaw = Double.nan
//        rawPitch = Double.nan
//        rawRoll = Double.nan
//        
//        yawFilter = LowPassFilter(samples: 5)
//        pitchFilter = LowPassFilter(samples: 5)
//        rollFilter = LowPassFilter(samples: 5)
//        
//        if isLogging {
//            stopFaceTrackingLogger()
//        }
//    }
//    
//    private func checkCameraPermission() {
//        let status = AVCaptureDevice.authorizationStatus(for: .video)
//        cameraPermissionStatus = status
//        switch status {
//        case .notDetermined:
//            AVCaptureDevice.requestAccess(for: .video) { granted in
//                DispatchQueue.main.async {
//                    cameraPermissionStatus = granted ? .authorized : .denied
//                    if !granted {
//                        showingPermissionAlert = true
//                    }
//                }
//            }
//        case .authorized:
//            break
//        case .denied, .restricted:
//            showingPermissionAlert = true
//        @unknown default: break
//        }
//    }
//}
//
//// MARK: - UIImage Extensions
//extension UIImage {
//    func resized(to size: CGSize) -> UIImage? {
//        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
//        defer { UIGraphicsEndImageContext() }
//        draw(in: CGRect(origin: .zero, size: size))
//        return UIGraphicsGetImageFromCurrentImageContext()
//    }
//}
//
//extension CGImage {
//    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
//        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
//             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
//        var pixelBuffer: CVPixelBuffer?
//        let status = CVPixelBufferCreate(kCFAllocatorDefault,
//                                         width,
//                                         height,
//                                         kCVPixelFormatType_32ARGB,
//                                         attrs,
//                                         &pixelBuffer)
//        
//        guard status == kCVReturnSuccess else { return nil }
//        
//        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
//        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
//        
//        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
//        let context = CGContext(data: pixelData,
//                                width: width,
//                                height: height,
//                                bitsPerComponent: 8,
//                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
//                                space: rgbColorSpace,
//                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
//        
//        context?.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
//        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
//        
//        return pixelBuffer
//    }
//}

///MARK: ImageView
///
///
//
//  ImageView.swift
//  HeadPose
//
//  Created by Luo Lab on 7/18/25.
//


// ImageView.swift - Updated for clockwise capture sequence starting from center (5)
// Displays a grid of images with tap-to-redo and long-press quick-view
//
//import SwiftUI
//import Photos
//
//struct ImageView: View {
//    let images: [UIImage]
//    let faceData: [(yaw: Double, pitch: Double, roll: Double)]
//    let onRedo: (Int) -> Void
//    let onBack: () -> Void
//
//    @State private var selectedImage: UIImage?
//    @State private var isShowingQuickView = false
//    @State private var showingSaveAlert = false
//    @State private var saveMessage = ""
//    @State private var showingPermissionAlert = false
//    
//    // Map display index to actual grid position for clockwise sequence: 5, 2, 3, 6, 9, 8, 7, 4, 1
//    private let displayToGridMap: [Int: Int] = [
//        0: 4,  // First captured (center 5) goes to grid position 5 (index 4)
//        1: 1,  // Second captured (2) goes to grid position 2 (index 1)
//        2: 2,  // Third captured (3) goes to grid position 3 (index 2)
//        3: 5,  // Fourth captured (6) goes to grid position 6 (index 5)
//        4: 8,  // Fifth captured (9) goes to grid position 9 (index 8)
//        5: 7,  // Sixth captured (8) goes to grid position 8 (index 7)
//        6: 6,  // Seventh captured (7) goes to grid position 7 (index 6)
//        7: 3,  // Eighth captured (4) goes to grid position 4 (index 3)
//        8: 0   // Ninth captured (1) goes to grid position 1 (index 0)
//    ]
//    
//    // Map grid position back to display index for redo functionality
//    private let gridToDisplayMap: [Int: Int] = [
//        0: 8,  // Grid position 1 maps to display index 8
//        1: 1,  // Grid position 2 maps to display index 1
//        2: 2,  // Grid position 3 maps to display index 2
//        3: 7,  // Grid position 4 maps to display index 7
//        4: 0,  // Grid position 5 (center) maps to display index 0
//        5: 3,  // Grid position 6 maps to display index 3
//        6: 6,  // Grid position 7 maps to display index 6
//        7: 5,  // Grid position 8 maps to display index 5
//        8: 4   // Grid position 9 maps to display index 4
//    ]
//
//    var body: some View {
//        GeometryReader { geometry in
//            // Calculate proper dimensions for landscape
//            let screenHeight = geometry.size.width  // Rotated: width becomes height
//            let screenWidth = geometry.size.height   // Rotated: height becomes width
//            let padding: CGFloat = 12
//            let spacing: CGFloat = 6
//            let buttonHeight: CGFloat = 44 // Minimum touch target
//            let titleHeight: CGFloat = 60
//            
//            // Calculate grid dimensions to fit without scrolling
//            let availableHeight = screenHeight - titleHeight - (padding * 3) - 20 // Extra margin
//            let availableWidth = screenWidth - (padding * 2)
//            
//            // Grid sizing - ensure 3x3 fits perfectly
//            let gridSpacing = spacing * 2 // Total spacing between 3 items
//            let itemWidth = (availableWidth - gridSpacing) / 3
//            let itemHeight = min(itemWidth * 0.6, (availableHeight - gridSpacing) / 3) // Limit height to fit
//            
//            VStack(spacing: 0) {
//                // Top Navigation Bar - Larger touch targets
//                HStack(spacing: 0) {
//                    // Back button - Larger touch area
//                    Button(action: onBack) {
//                        HStack(spacing: 4) {
//                            Image(systemName: "chevron.left")
//                                .font(.title2)
//                            Text("Back")
//                                .font(.body)
//                                .fontWeight(.medium)
//                        }
//                        .foregroundColor(.blue)
//                        .frame(minWidth: 80, minHeight: buttonHeight)
//                        .contentShape(Rectangle()) // Make entire area tappable
//                    }
//                    .buttonStyle(PlainButtonStyle()) // Prevent default button styling
//                    
//                    Spacer()
//                    
//                    // Title
//                    Text("Eye Images (\(images.count)/9)")
//                        .font(.title3)
//                        .fontWeight(.bold)
//                        .lineLimit(1)
//                    
//                    Spacer()
//                    
//                    // Save button - Larger touch area
//                    Button(action: saveImagesAndGrid) {
//                        HStack(spacing: 4) {
//                            Image(systemName: "square.and.arrow.down")
//                                .font(.title2)
//                            Text("Save")
//                                .font(.body)
//                                .fontWeight(.medium)
//                        }
//                        .foregroundColor(.blue)
//                        .frame(minWidth: 80, minHeight: buttonHeight)
//                        .contentShape(Rectangle()) // Make entire area tappable
//                    }
//                    .buttonStyle(PlainButtonStyle()) // Prevent default button styling
//                }
//                .frame(height: titleHeight)
//                .padding(.horizontal, padding)
//                .background(Color(UIColor.systemBackground))
//                
//                // 3x3 Grid - Arranged in proper grid order
//                let gridColumns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: 3)
//                
//                LazyVGrid(columns: gridColumns, spacing: spacing) {
//                    ForEach(0..<9, id: \.self) { gridPosition in
//                        VStack(spacing: 2) {
//                            // Index label - Grid position (1-9)
//                            Text("\(gridPosition + 1)")
//                                .font(.caption2)
//                                .fontWeight(.bold)
//                                .foregroundColor(.primary)
//                            
//                            // Get the image for this grid position
//                            if let displayIndex = gridToDisplayMap[gridPosition], displayIndex < images.count {
//                                let img = images[displayIndex]
//                                
//                                // Scaled thumbnail to show full cropped image
//                                let thumbnailImage = Image(uiImage: img)
//                                    .resizable()
//                                    .aspectRatio(contentMode: .fit) // Changed to .fit to show full image
//                                    .frame(width: itemWidth, height: itemHeight)
//                                    .clipped()
//                                
//                                thumbnailImage
//                                    .background(Color.gray.opacity(0.05))
//                                    .cornerRadius(8)
//                                    .overlay(
//                                        RoundedRectangle(cornerRadius: 8)
//                                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
//                                    )
//                                    .onTapGesture {
//                                        if let displayIndex = gridToDisplayMap[gridPosition] {
//                                            print("🔄 Going back to retake image at position \(gridPosition + 1) (display index: \(displayIndex))")
//                                            onRedo(displayIndex) // This should return to camera UI, not auto-capture
//                                        }
//                                    }
//                                    .onLongPressGesture {
//                                        selectedImage = img
//                                        isShowingQuickView = true
//                                    }
//                                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 0.5)
//                            } else {
//                                // Empty placeholder
//                                let placeholderRect = RoundedRectangle(cornerRadius: 8)
//                                    .fill(Color.gray.opacity(0.05))
//                                    .frame(width: itemWidth, height: itemHeight)
//                                
//                                let dashedBorder = RoundedRectangle(cornerRadius: 8)
//                                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
//                                
//                                let cameraIcon = Image(systemName: "camera.fill")
//                                    .font(.title3)
//                                    .foregroundColor(.gray.opacity(0.4))
//                                
//                                placeholderRect
//                                    .overlay(dashedBorder)
//                                    .overlay(cameraIcon)
//                            }
//                        }
//                    }
//                }
//                .padding(.horizontal, padding)
//                .padding(.top, padding)
//                
//                Spacer(minLength: 0)
//            }
//            .frame(width: screenWidth, height: screenHeight)
//            .rotationEffect(.degrees(90)) // Rotate entire view 90 degrees
//            .frame(width: geometry.size.width, height: geometry.size.height)
//        }
//        // Sheet for quick-view (also rotated)
//        .sheet(isPresented: $isShowingQuickView) {
//            if let full = selectedImage {
//                if #available(iOS 16.0, *) {
//                    NavigationView {
//                        ZStack {
//                            Color.black.ignoresSafeArea()
//                            
//                            Image(uiImage: full)
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .ignoresSafeArea(.container, edges: .bottom)
//                                .rotationEffect(.degrees(90)) // Rotate the image in quick view
//                        }
//                        .navigationBarTitleDisplayMode(.inline)
//                        .toolbar {
//                            ToolbarItem(placement: .navigationBarTrailing) {
//                                Button("Done") {
//                                    isShowingQuickView = false
//                                }
//                                .foregroundColor(.white)
//                            }
//                        }
//                    }
//                    .rotationEffect(.degrees(90)) // Rotate the entire sheet
//                    .presentationDetents([.large])
//                } else {
//                    // Fallback on earlier versions
//                    NavigationView {
//                        ZStack {
//                            Color.black.ignoresSafeArea()
//                            
//                            Image(uiImage: full)
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .rotationEffect(.degrees(90))
//                        }
//                        .navigationBarTitleDisplayMode(.inline)
//                        .toolbar {
//                            ToolbarItem(placement: .navigationBarTrailing) {
//                                Button("Done") {
//                                    isShowingQuickView = false
//                                }
//                                .foregroundColor(.white)
//                            }
//                        }
//                    }
//                    .rotationEffect(.degrees(90))
//                }
//            }
//        }
//        .alert("Grid Saved", isPresented: $showingSaveAlert) {
//            Button("OK") { }
//        } message: {
//            Text(saveMessage)
//        }
//        .alert("Photos Permission Required", isPresented: $showingPermissionAlert) {
//            Button("Settings") {
//                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
//                    UIApplication.shared.open(settingsUrl)
//                }
//            }
//            Button("Cancel", role: .cancel) { }
//        } message: {
//            Text("Please allow photo library access in Settings to save images.")
//        }
//    }
//    
//    // MARK: - Save Functions
//    private func saveImagesAndGrid() {
//        // Check Photos permission first
//        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
//        
//        switch status {
//        case .authorized, .limited:
//            // Permission granted, proceed with saving
//            performSave()
//        case .notDetermined:
//            // Request permission
//            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
//                DispatchQueue.main.async {
//                    if newStatus == .authorized || newStatus == .limited {
//                        self.performSave()
//                    } else {
//                        self.showingPermissionAlert = true
//                    }
//                }
//            }
//        case .denied, .restricted:
//            // Permission denied
//            showingPermissionAlert = true
//        @unknown default:
//            showingPermissionAlert = true
//        }
//    }
//    
//    private func performSave() {
//        // Create grid-ordered images and face data for saving
//        let gridOrderedImages = createGridOrderedArrays()
//        
//        // Save individual images in grid order (1-9) - FULL SIZE (not scaled)
//        for (index, image) in gridOrderedImages.images.enumerated() {
//            let faceInfo = index < gridOrderedImages.faceData.count ? gridOrderedImages.faceData[index] : (yaw: 0.0, pitch: 0.0, roll: 0.0)
//            saveIndividualImage(image, index: index + 1, faceData: faceInfo)
//        }
//        
//        // Save the CLEAN grid chart (no numbers, no white space)
//        let gridImage = createCleanGridImage()
//        UIImageWriteToSavedPhotosAlbum(gridImage, nil, nil, nil)
//        
//        saveMessage = "Saved \(gridOrderedImages.images.count) individual images + 1 clean grid chart to Photos!"
//        showingSaveAlert = true
//    }
//    
//    private func createGridOrderedArrays() -> (images: [UIImage], faceData: [(yaw: Double, pitch: Double, roll: Double)]) {
//        var gridOrderedImages: [UIImage] = []
//        var gridOrderedFaceData: [(yaw: Double, pitch: Double, roll: Double)] = []
//        
//        print("🔄 Creating grid-ordered arrays from \(images.count) images")
//        
//        // Create arrays in grid order (positions 1-9)
//        for gridPosition in 0..<9 {
//            if let displayIndex = gridToDisplayMap[gridPosition], displayIndex < images.count {
//                gridOrderedImages.append(images[displayIndex])
//                print("✅ Grid position \(gridPosition + 1) -> Display index \(displayIndex)")
//                if displayIndex < faceData.count {
//                    gridOrderedFaceData.append(faceData[displayIndex])
//                } else {
//                    gridOrderedFaceData.append((yaw: 0.0, pitch: 0.0, roll: 0.0))
//                }
//            }
//        }
//        
//        print("📊 Final grid has \(gridOrderedImages.count) images")
//        return (images: gridOrderedImages, faceData: gridOrderedFaceData)
//    }
//    
//    private func saveIndividualImage(_ image: UIImage, index: Int, faceData: (yaw: Double, pitch: Double, roll: Double)) {
//        // Create a labeled version of each image with face tracking data
//        // IMPORTANT: Save FULL SIZE original image, not scaled
//        let labeledImage = addLabelToImage(
//            image, // Use original full-size image
//            label: "9eye - Image \(index)",
//            faceData: faceData
//        )
//        UIImageWriteToSavedPhotosAlbum(labeledImage, nil, nil, nil)
//    }
//    
//    private func addLabelToImage(_ image: UIImage, label: String, faceData: (yaw: Double, pitch: Double, roll: Double)) -> UIImage {
//        let padding: CGFloat = 20
//        let labelHeight: CGFloat = 80 // Increased height for face data
//        let newSize = CGSize(
//            width: image.size.width, // Use original image dimensions
//            height: image.size.height + labelHeight + padding
//        )
//        
//        let renderer = UIGraphicsImageRenderer(size: newSize)
//        return renderer.image { context in
//            let cgContext = context.cgContext
//            
//            // White background
//            cgContext.setFillColor(UIColor.white.cgColor)
//            cgContext.fill(CGRect(origin: .zero, size: newSize))
//            
//            // Draw the FULL SIZE image
//            image.draw(at: CGPoint(x: 0, y: labelHeight + padding))
//            
//            // Draw the main label
//            let labelFont = UIFont.boldSystemFont(ofSize: 18)
//            let labelAttributes: [NSAttributedString.Key: Any] = [
//                .font: labelFont,
//                .foregroundColor: UIColor.black
//            ]
//            let labelSize = label.size(withAttributes: labelAttributes)
//            let labelX = (newSize.width - labelSize.width) / 2
//            let labelY: CGFloat = 10
//            
//            label.draw(at: CGPoint(x: labelX, y: labelY), withAttributes: labelAttributes)
//            
//            // Draw face tracking data
//            let faceDataText = String(format: "Yaw: %.1f°  Pitch: %.1f°  Roll: %.1f°",
//                                    faceData.yaw, faceData.pitch, faceData.roll)
//            let faceDataFont = UIFont.systemFont(ofSize: 14)
//            let faceDataAttributes: [NSAttributedString.Key: Any] = [
//                .font: faceDataFont,
//                .foregroundColor: UIColor.darkGray
//            ]
//            let faceDataSize = faceDataText.size(withAttributes: faceDataAttributes)
//            let faceDataX = (newSize.width - faceDataSize.width) / 2
//            let faceDataY: CGFloat = 40
//            
//            faceDataText.draw(at: CGPoint(x: faceDataX, y: faceDataY), withAttributes: faceDataAttributes)
//        }
//    }
//    
//    // MARK: - DYNAMIC GRID IMAGE - Replace in ImageView.swift
//    private func createCleanGridImage() -> UIImage {
//        guard !images.isEmpty else { return UIImage() }
//        
//        // Create grid-ordered images
//        let gridOrderedImages = createGridOrderedArrays().images
//        
//        // ✅ Find the actual dimensions of the cropped images (no forcing to squares)
//        var maxWidth: CGFloat = 0
//        var maxHeight: CGFloat = 0
//        
//        for image in gridOrderedImages {
//            maxWidth = max(maxWidth, image.size.width)
//            maxHeight = max(maxHeight, image.size.height)
//        }
//        
//        // ✅ Use actual image dimensions, not fixed square cells
//        let cellWidth = maxWidth
//        let cellHeight = maxHeight
//        
//        // Minimal spacing between images
//        let spacing: CGFloat = 2
//        
//        // Calculate total canvas size for 3x3 grid using actual image dimensions
//        let canvasWidth = (cellWidth * 3) + (spacing * 2)
//        let canvasHeight = (cellHeight * 3) + (spacing * 2)
//        
//        print("Creating dynamic grid: \(canvasWidth) x \(canvasHeight)")
//        print("Cell size: \(cellWidth) x \(cellHeight) (actual image dimensions)")
//        
//        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasWidth, height: canvasHeight))
//        
//        return renderer.image { context in
//            let cgContext = context.cgContext
//            
//            // White background
//            cgContext.setFillColor(UIColor.white.cgColor)
//            cgContext.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
//            
//            // Draw 3x3 grid with images at their natural size
//            for row in 0..<3 {
//                for col in 0..<3 {
//                    let gridPosition = row * 3 + col
//                    
//                    if gridPosition < gridOrderedImages.count {
//                        let x = CGFloat(col) * (cellWidth + spacing)
//                        let y = CGFloat(row) * (cellHeight + spacing)
//                        
//                        // Get the image for this grid position
//                        let originalImage = gridOrderedImages[gridPosition]
//                        
//                        // ✅ Draw image at its natural size, centered in the cell
//                        let imageWidth = originalImage.size.width
//                        let imageHeight = originalImage.size.height
//                        
//                        let centeredX = x + (cellWidth - imageWidth) / 2
//                        let centeredY = y + (cellHeight - imageHeight) / 2
//                        
//                        let imageRect = CGRect(
//                            x: centeredX,
//                            y: centeredY,
//                            width: imageWidth,
//                            height: imageHeight
//                        )
//                        
//                        // Draw the original image without scaling
//                        originalImage.draw(in: imageRect)
//                        
//                        print("Drew image \(gridPosition + 1): \(imageWidth) x \(imageHeight) at natural size")
//                    } else {
//                        // Empty slot placeholder (rarely needed since you have 9 images)
//                        let x = CGFloat(col) * (cellWidth + spacing)
//                        let y = CGFloat(row) * (cellHeight + spacing)
//                        let placeholderRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
//                        
//                        cgContext.setFillColor(UIColor.systemGray6.cgColor)
//                        cgContext.fill(placeholderRect)
//                        
//                        cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
//                        cgContext.setLineWidth(1)
//                        cgContext.stroke(placeholderRect)
//                    }
//                }
//            }
//        }
//    }
//    
//    // MARK: - Helper method to rotate image 90 degrees counterclockwise (kept for reference but not used in clean grid)
//    private func rotateImageCounterclockwise(_ image: UIImage) -> UIImage {
//        guard let cgImage = image.cgImage else { return image }
//        
//        // Create a new image rotated 90 degrees counterclockwise
//        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)
//        
//        let renderer = UIGraphicsImageRenderer(size: rotatedSize)
//        return renderer.image { context in
//            let cgContext = context.cgContext
//            
//            // Move to center, rotate, then move back
//            cgContext.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
//            cgContext.rotate(by: -CGFloat.pi / 2) // Rotate 90 degrees counterclockwise
//            cgContext.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
//            
//            // Draw the original image
//            cgContext.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
//        }
//    }
//}
