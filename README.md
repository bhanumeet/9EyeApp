# 9eye Capture - Standardized Ophthalmological Gaze Documentation

A professional iOS application designed for ophthalmologists to capture standardized 9-position gaze images with real-time head pose detection and angle guidance.

<img width="1536" height="1024" alt="Eye Exam with Smartphone Photography-2-2" src="https://github.com/user-attachments/assets/478ddf41-b89d-4049-90fe-07f24f95644d" />

## Overview

In ophthalmology, the 9-gaze test is crucial for diagnosing various eye movement disorders, cranial nerve palsies, and extraocular muscle dysfunctions. Traditional methods rely on subjective visual estimation of gaze directions, leading to inconsistent documentation. **9eye Capture** revolutionizes this process by providing real-time head pose detection with precise angle guidance, ensuring standardized and reproducible gaze documentation.

## Key Features

### 🎯 **Real-Time Head Pose Detection**
- Advanced TensorFlow Lite integration for precise head tracking
- Real-time yaw, pitch, and roll angle detection
- Smooth filtering system to reduce noise and jitter
- Visual feedback with colored guidance indicators

### 📐 **Standardized Angle Guidance**
- Pre-defined angle ranges for each of the 9 gaze positions
- Visual and textual guidance for optimal positioning
- Baseline calibration system for personalized accuracy
- Target angle ranges displayed in real-time

### 📸 **Intelligent Capture System**
- Automatic eye region detection and cropping
- Volume button capture, Selfie stick button support for hands-free operation
- Sequential capture following standard ophthalmological protocol
- Redo functionality for individual positions

### 💾 **Professional Documentation**
- High-resolution image export with metadata
- Grid layout compilation for medical records
- Individual images with angle annotations
- Photo library integration with proper naming conventions

### 🔍 **Advanced Face Tracking**
- Vision framework integration for robust face detection
- Real-time face bounding box visualization
- Queue system for processing optimization
- No-face detection warnings

### 📊 **Data Logging & Analysis**
- Optional face tracking data logging
- CSV export for research and analysis
- Timestamp-based data collection
- Shareable log files for documentation

## Technical Specifications

### System Requirements
- iOS 13.0 or later
- iPhone with front or rear camera
- TensorFlow Lite framework
- Vision framework support

### Architecture
- **SwiftUI** - Modern declarative UI framework
- **AVFoundation** - Camera and media processing
- **Vision** - Face detection and landmark recognition  
- **TensorFlow Lite** - Head pose estimation model
- **CoreMotion** - Device orientation handling

### Performance Optimizations
- Multi-threaded processing for real-time performance
- Efficient memory management for image processing
- Adaptive quality settings based on device capabilities
- Background processing queues for non-blocking UI

## Installation

### Prerequisites
Ensure you have Xcode 12.0 or later installed on your development machine.

### CocoaPods Setup

1. **Install CocoaPods** (if not already installed):
```bash
sudo gem install cocoapods
```

2. **Navigate to your project directory**:
```bash
cd /path/to/HeadPose
```

3. **Initialize Podfile** (if not exists):
```bash
pod init
```

4. **Configure Podfile**:
```ruby
# Podfile
platform :ios, '13.0'
use_frameworks!

target 'HeadPose' do
  # TensorFlow Lite for head pose detection
  pod 'TensorFlowLiteSwift', '~> 2.13.0'
  
  # Alternative: Use TensorFlowLiteObjC if needed
  # pod 'TensorFlowLiteObjC', '~> 2.13.0'
  
  # Core iOS frameworks (included by default, listed for reference)
  # - AVFoundation
  # - Vision  
  # - CoreMotion
  # - UIKit
  # - SwiftUI
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
```

5. **Install Dependencies**:
```bash
pod install
```

6. **Open Workspace**:
```bash
open HeadPose.xcworkspace
```

### Manual TensorFlow Lite Setup (Alternative)

If CocoaPods installation fails, you can manually integrate TensorFlow Lite:

1. Download TensorFlow Lite iOS framework from [official releases](https://github.com/tensorflow/tensorflow/releases)
2. Drag `TensorFlowLiteSwift.framework` into your Xcode project
3. Add to **Frameworks, Libraries, and Embedded Content**
4. Set **Embed & Sign** for the framework

### Model File Setup

1. **Add the TensorFlow Lite Model**:
   - Ensure `epoch_100_static_bs1.tflite` is included in your project bundle
   - Verify the model file is added to the target membership
   - Check the build phases include the model in "Copy Bundle Resources"

2. **Verify Model Path**:
```swift
guard let modelPath = Bundle.main.path(forResource: "epoch_100_static_bs1", ofType: "tflite") else {
    print("❌ Model file not found in bundle")
    return
}
```

### Info.plist Configuration

Add the following privacy usage descriptions to your `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access to capture standardized gaze images for ophthalmological documentation.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app saves captured gaze images to your photo library for medical documentation.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is used for volume button capture functionality.</string>
```

## Usage Guide

### Initial Setup
1. **Launch Application**: Open 9eye Capture on your iOS device
2. **Grant Permissions**: Allow camera and photo library access when prompted
3. **Orient Device**: Hold device in landscape orientation for optimal experience

### Capturing Process

#### Step 1: Position Patient
- Seat patient comfortably at appropriate distance (typically 60cm from device)
- Ensure good lighting conditions
- Position device camera facing the patient

#### Step 2: Baseline Calibration
1. **Start with Center Position (5)**: Patient looks directly at camera
2. **Capture Center Image**: This establishes baseline head position
3. **Calibration Complete**: System now provides relative angle guidance

#### Step 3: Sequential Capture
The app follows standard ophthalmological 9-gaze sequence:

| Position | Direction | Target Angles |
|----------|-----------|---------------|
| 1 | Upper Left | Yaw: -15°, Pitch: -15° |
| 2 | Up | Yaw: 0°, Pitch: -15° |  
| 3 | Upper Right | Yaw: +15°, Pitch: -15° |
| 4 | Left | Yaw: -15°, Pitch: 0° |
| 5 | Center | Yaw: 0°, Pitch: 0° |
| 6 | Right | Yaw: +15°, Pitch: 0° |
| 7 | Lower Left | Yaw: -15°, Pitch: +15° |
| 8 | Down | Yaw: 0°, Pitch: +15° |
| 9 | Lower Right | Yaw: +15°, Pitch: +15° |

#### Step 4: Real-time Guidance
- **Face Detection**: Green indicator confirms face is detected
- **Angle Display**: Live yaw, pitch, roll values shown
- **Guidance Text**: Directional instructions (Left, Right, Up, Down)
- **Perfect Indicator**: "PERFECT! 👍" when angles are within target range

#### Step 5: Image Capture
- **Tap Capture Button**: Large white circle at bottom of screen
- **Volume Button**: Use device volume buttons for hands-free capture
- **Auto-crop**: System automatically crops to eye region
- **Quality Check**: Review captured image in preview panel

#### Step 6: Review and Retake
- **Individual Retake**: Tap any image in grid to recapture specific position
- **Quality Assurance**: Ensure all 9 positions are clearly captured
- **Complete Set**: System automatically proceeds when all 9 images captured

### Advanced Features

#### Face Tracking Logger
- **Enable Logging**: Tap record button to start data collection
- **Real-time Data**: Captures yaw, pitch, roll values with timestamps
- **Export Data**: Generate CSV files for research or analysis
- **Share Logs**: Send data files via standard iOS sharing

#### Volume Button Capture
- **Automatic Setup**: Volume button capture enabled by default
- **Hands-free Operation**: Allows doctor to position patient while capturing
- **Feedback System**: Smart volume reset prevents audio disruption

#### Image Management
- **Auto-save**: All images automatically saved to photo library
- **Grid Compilation**: Complete 9-image grid saved as single file
- **Metadata Inclusion**: Each image tagged with angle measurements
- **High Resolution**: Full quality images maintained for medical accuracy

## Developer Notes

### Code Architecture

#### Core Classes
- **`ContentView`**: Main SwiftUI interface controller
- **`CameraManager`**: AVFoundation camera handling and face detection
- **`HeadPoseDetector`**: TensorFlow Lite model interface
- **`ImageView`**: Results display and grid management
- **`VolumeButtonManager`**: Hardware button capture system

#### Key Design Patterns
- **MVVM Architecture**: Clear separation of UI and business logic
- **Combine Framework**: Reactive programming for state management  
- **Delegation Pattern**: Camera and volume button event handling
- **Publisher-Subscriber**: Real-time data updates

#### Threading Strategy
```swift
// Model inference on background queue
private let modelQueue = DispatchQueue(label: "headPoseModelQueue", qos: .userInteractive)

// Video processing on dedicated queue
private let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)

// UI updates always on main queue
DispatchQueue.main.async {
    // Update UI elements
}
```

#### Memory Management
- **Image Compression**: Automatic compression for storage efficiency
- **Queue Limiting**: Maximum 20 processed heads in memory
- **Resource Cleanup**: Proper deallocation of camera resources
- **Background Processing**: Non-blocking image operations

### Model Integration

#### TensorFlow Lite Model Details
```swift
// Model specifications
private let inputSize = CGSize(width: 224, height: 224)
private let modelName = "epoch_100_static_bs1"

// 6D rotation to Euler conversion
private func convert6DToEuler(_ rotation6D: [Double]) -> (Double, Double, Double)
```

#### Preprocessing Pipeline
1. **Image Resize**: Scale to 224x224 model input
2. **Color Space**: Convert to RGB float32 array
3. **Normalization**: Pixel values normalized to [0,1]
4. **Format Conversion**: BGRA to RGB channel ordering

#### Post-processing
1. **6D Rotation Output**: Model outputs 6D rotation representation
2. **Euler Conversion**: Convert to yaw, pitch, roll angles
3. **Coordinate System**: Align with medical conventions
4. **Filtering**: Apply low-pass filtering for stability

### Vision Framework Integration

#### Face Detection Configuration
```swift
let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
    // Handle face detection results
}

// Orientation handling for landscape mode
let handler = VNImageRequestHandler(
    cvPixelBuffer: pixelBuffer,
    orientation: .downMirrored,
    options: [:]
)
```

#### Coordinate Transformations
- **Vision Coordinates**: Normalized [0,1] coordinate system
- **Image Coordinates**: Pixel-based absolute coordinates  
- **Preview Coordinates**: Screen-relative display coordinates
- **Crop Coordinates**: Region-specific for eye extraction

### Performance Optimizations

#### Processing Throttling
```swift
private let processingInterval: TimeInterval = 0.1
private var lastProcessTime: Date = Date()

// Limit processing frequency
guard now.timeIntervalSince(lastProcessTime) >= processingInterval else {
    return
}
```

#### Image Quality Management
- **Adaptive Compression**: Based on device capabilities
- **Progressive Loading**: Staged image processing
- **Memory Monitoring**: Automatic cleanup when memory pressure detected
- **Background Processing**: Non-blocking operations

## Troubleshooting

### Common Issues and Solutions

#### 1. Camera Permission Denied
**Symptom**: App shows permission denied screen
**Solution**: 
```swift
// Check current permission status
let status = AVCaptureDevice.authorizationStatus(for: .video)

// Guide user to settings
if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
    UIApplication.shared.open(settingsUrl)
}
```
**Manual Fix**: Settings → Privacy & Security → Camera → 9eye Capture → Enable

#### 2. TensorFlow Lite Model Not Loading
**Symptom**: Console shows "❌ Failed to find model file"
**Solution**:
1. Verify `epoch_100_static_bs1.tflite` is in project bundle
2. Check Build Phases → Copy Bundle Resources
3. Confirm model file target membership
4. Rebuild project clean (⌘+Shift+K, then ⌘+B)

#### 3. Face Detection Not Working
**Symptom**: "NO FACE" message persists despite visible face
**Diagnostic Steps**:
```swift
// Enable debug logging
print("Face detection request configuration:")
print("Orientation: \(handler.orientation)")
print("Input buffer size: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
```
**Solutions**:
- Ensure adequate lighting
- Position face within camera frame
- Check camera lens for obstruction
- Verify device orientation handling

#### 4. Volume Button Capture Not Responding
**Symptom**: Volume buttons don't trigger capture
**Debug Code**:
```swift
override func observeValue(forKeyPath keyPath: String?, of object: Any?, 
                          change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    print("Volume change detected: \(change)")
}
```
**Solutions**:
1. Check audio session configuration
2. Verify MPVolumeView setup
3. Ensure volume slider is found and configured
4. Check for iOS version compatibility

#### 5. Images Not Saving to Photo Library
**Symptom**: No images appear in Photos app after capture
**Diagnostic**:
```swift
let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
print("Photo library authorization: \(status)")
```
**Solutions**:
- Grant photo library permission in Settings
- Check Info.plist privacy descriptions
- Verify UIImageWriteToSavedPhotosAlbum callback

#### 6. App Crashes During Image Processing
**Common Causes**:
- Memory pressure from large images
- Threading issues with UI updates
- Invalid CGImage operations

**Prevention**:
```swift
// Always validate CGImage before processing
guard let cgImage = image.cgImage else {
    print("❌ Invalid CGImage")
    return
}

// Process on background queue
DispatchQueue.global(qos: .userInteractive).async {
    // Heavy processing
    
    DispatchQueue.main.async {
        // UI updates
    }
}
```

#### 7. Poor Head Pose Accuracy
**Symptoms**: Inconsistent or incorrect angle readings
**Optimization Steps**:
1. **Lighting Conditions**: Ensure even, adequate lighting
2. **Distance**: Maintain 60-90cm from camera
3. **Stability**: Minimize camera shake
4. **Calibration**: Always capture center position first

**Filter Adjustment**:
```swift
// Increase filter samples for more stability
@State private var yawFilter = LowPassFilter(samples: 10)
@State private var pitchFilter = LowPassFilter(samples: 10) 
@State private var rollFilter = LowPassFilter(samples: 10)
```

#### 8. Orientation Issues
**Symptom**: Interface appears rotated or misaligned
**Solution**: Check AppDelegate orientation lock:
```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait // or .landscape
}
```

#### 9. Build Errors with CocoaPods
**Common Issues**:
```bash
# Clean pod cache
pod deintegrate
pod clean
rm Podfile.lock
pod install

# Update CocoaPods
sudo gem update cocoapods

# Check iOS deployment target consistency
# Ensure all targets use same minimum iOS version
```

### Performance Issues

#### Memory Management
```swift
// Monitor memory usage
func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    // Clear image caches
    croppedHeads.removeAll()
    // Release unnecessary resources
}
```

#### Processing Optimization
```swift
// Reduce processing frequency if performance issues
private let processingInterval: TimeInterval = 0.2 // Increase interval

// Lower image resolution for processing
private let inputSize = CGSize(width: 112, height: 112) // Reduce if needed
```

### Debug Logging

Enable comprehensive logging for troubleshooting:

```swift
// Add to ContentView.swift
private func enableDebugLogging() {
    print("🔧 Debug mode enabled")
    
    // Camera setup logging
    cameraManager.debugMode = true
    
    // Head pose detection logging  
    headPoseDetector.verboseLogging = true
    
    // Face tracking data logging
    startFaceTrackingLogger()
}
```

### Development Setup
```bash
# Clone repository
git clone [repository-url]
cd 9eye-capture

# Install dependencies
pod install

# Open workspace
open HeadPose.xcworkspace
```
