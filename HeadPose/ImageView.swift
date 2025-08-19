//
//  ImageView.swift
//  HeadPose
//
//  Created by Luo Lab on 7/18/25.
//


// ImageView.swift - Updated for clockwise capture sequence starting from center (5)
// Displays a grid of images with tap-to-redo and long-press quick-view

import SwiftUI
import Photos

struct ImageView: View {
    let images: [UIImage]
    let faceData: [(yaw: Double, pitch: Double, roll: Double)]
    let onRedo: (Int) -> Void
    let onBack: () -> Void

    @State private var selectedImage: UIImage?
    @State private var isShowingQuickView = false
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    @State private var showingPermissionAlert = false
    
    // Map display index to actual grid position for clockwise sequence: 5, 2, 3, 6, 9, 8, 7, 4, 1
    private let displayToGridMap: [Int: Int] = [
        0: 4,  // First captured (center 5) goes to grid position 5 (index 4)
        1: 1,  // Second captured (2) goes to grid position 2 (index 1)
        2: 2,  // Third captured (3) goes to grid position 3 (index 2)
        3: 5,  // Fourth captured (6) goes to grid position 6 (index 5)
        4: 8,  // Fifth captured (9) goes to grid position 9 (index 8)
        5: 7,  // Sixth captured (8) goes to grid position 8 (index 7)
        6: 6,  // Seventh captured (7) goes to grid position 7 (index 6)
        7: 3,  // Eighth captured (4) goes to grid position 4 (index 3)
        8: 0   // Ninth captured (1) goes to grid position 1 (index 0)
    ]
    
    // Map grid position back to display index for redo functionality
    private let gridToDisplayMap: [Int: Int] = [
        0: 0,  // Grid position 1 maps to display index 8
        1: 1,  // Grid position 2 maps to display index 1
        2: 2,  // Grid position 3 maps to display index 2
        3: 3,  // Grid position 4 maps to display index 7
        4: 4,  // Grid position 5 (center) maps to display index 0
        5: 5,  // Grid position 6 maps to display index 3
        6: 6,  // Grid position 7 maps to display index 6
        7: 7,  // Grid position 8 maps to display index 5
        8: 8   // Grid position 9 maps to display index 4
    ]

    var body: some View {
        GeometryReader { geometry in
            // Calculate proper dimensions for landscape
            let screenHeight = geometry.size.width  // Rotated: width becomes height
            let screenWidth = geometry.size.height   // Rotated: height becomes width
            let padding: CGFloat = 12
            let spacing: CGFloat = 6
            let buttonHeight: CGFloat = 44 // Minimum touch target
            let titleHeight: CGFloat = 60
            
            // Calculate grid dimensions to fit without scrolling
            let availableHeight = screenHeight - titleHeight - (padding * 3) - 20 // Extra margin
            let availableWidth = screenWidth - (padding * 2)
            
            // Grid sizing - ensure 3x3 fits perfectly
            let gridSpacing = spacing * 2 // Total spacing between 3 items
            let itemWidth = (availableWidth - gridSpacing) / 3
            let itemHeight = min(itemWidth * 0.6, (availableHeight - gridSpacing) / 3) // Limit height to fit
            
            VStack(spacing: 0) {
                // Top Navigation Bar - Larger touch targets
                HStack(spacing: 0) {
                    // Back button - Larger touch area
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                            Text("Back")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .frame(minWidth: 80, minHeight: buttonHeight)
                        .contentShape(Rectangle()) // Make entire area tappable
                    }
                    .buttonStyle(PlainButtonStyle()) // Prevent default button styling
                    
                    Spacer()
                    
                    // Title
                    Text("Eye Images (\(images.count)/9)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Save button - Larger touch area
                    Button(action: saveImagesAndGrid) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                            Text("Save")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .frame(minWidth: 80, minHeight: buttonHeight)
                        .contentShape(Rectangle()) // Make entire area tappable
                    }
                    .buttonStyle(PlainButtonStyle()) // Prevent default button styling
                }
                .frame(height: titleHeight)
                .padding(.horizontal, padding)
                .background(Color(UIColor.systemBackground))
                
                // 3x3 Grid - Arranged in proper grid order
                let gridColumns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: 3)
                
                LazyVGrid(columns: gridColumns, spacing: spacing) {
                    ForEach(0..<9, id: \.self) { gridPosition in
                        VStack(spacing: 2) {
                            // Index label - Grid position (1-9)
                            Text("\(gridPosition + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            // Get the image for this grid position
                            if let displayIndex = gridToDisplayMap[gridPosition], displayIndex < images.count {
                                let img = images[displayIndex]
                                
                                // Scaled thumbnail to show full cropped image
                                let thumbnailImage = Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit) // Changed to .fit to show full image
                                    .frame(width: itemWidth, height: itemHeight)
                                    .clipped()
                                
                                thumbnailImage
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .onTapGesture {
                                        if let displayIndex = gridToDisplayMap[gridPosition] {
                                            print("🔄 Going back to retake image at position \(gridPosition + 1) (display index: \(displayIndex))")
                                            onRedo(displayIndex) // This should return to camera UI, not auto-capture
                                        }
                                    }
                                    .onLongPressGesture {
                                        selectedImage = img
                                        isShowingQuickView = true
                                    }
                                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 0.5)
                            } else {
                                // Empty placeholder
                                let placeholderRect = RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.05))
                                    .frame(width: itemWidth, height: itemHeight)
                                
                                let dashedBorder = RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                
                                let cameraIcon = Image(systemName: "camera.fill")
                                    .font(.title3)
                                    .foregroundColor(.gray.opacity(0.4))
                                
                                placeholderRect
                                    .overlay(dashedBorder)
                                    .overlay(cameraIcon)
                            }
                        }
                    }
                }
                .padding(.horizontal, padding)
                .padding(.top, padding)
                
                Spacer(minLength: 0)
            }
            .frame(width: screenWidth, height: screenHeight)
            .rotationEffect(.degrees(90)) // Rotate entire view 90 degrees
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // Sheet for quick-view (also rotated)
        .sheet(isPresented: $isShowingQuickView) {
            if let full = selectedImage {
                if #available(iOS 16.0, *) {
                    NavigationView {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            
                            Image(uiImage: full)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .ignoresSafeArea(.container, edges: .bottom)
                                .rotationEffect(.degrees(90)) // Rotate the image in quick view
                        }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    isShowingQuickView = false
                                }
                                .foregroundColor(.white)
                            }
                        }
                    }
                    .rotationEffect(.degrees(90)) // Rotate the entire sheet
                    .presentationDetents([.large])
                } else {
                    // Fallback on earlier versions
                    NavigationView {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            
                            Image(uiImage: full)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .rotationEffect(.degrees(90))
                        }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    isShowingQuickView = false
                                }
                                .foregroundColor(.white)
                            }
                        }
                    }
                    .rotationEffect(.degrees(90))
                }
            }
        }
        .alert("Grid Saved", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveMessage)
        }
        .alert("Photos Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please allow photo library access in Settings to save images.")
        }
    }
    
    // MARK: - Save Functions
    private func saveImagesAndGrid() {
        // Check Photos permission first
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            // Permission granted, proceed with saving
            performSave()
        case .notDetermined:
            // Request permission
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self.performSave()
                    } else {
                        self.showingPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            // Permission denied
            showingPermissionAlert = true
        @unknown default:
            showingPermissionAlert = true
        }
    }
    
    private func performSave() {
        // Create grid-ordered images and face data for saving
        let gridOrderedImages = createGridOrderedArrays()
        
        // Save individual images in grid order (1-9) - FULL SIZE (not scaled)
        for (index, image) in gridOrderedImages.images.enumerated() {
            let faceInfo = index < gridOrderedImages.faceData.count ? gridOrderedImages.faceData[index] : (yaw: 0.0, pitch: 0.0, roll: 0.0)
            saveIndividualImage(image, index: index + 1, faceData: faceInfo)
        }
        
        // Save the CLEAN grid chart (no numbers, no white space)
        let gridImage = createCleanGridImage()
        UIImageWriteToSavedPhotosAlbum(gridImage, nil, nil, nil)
        
        saveMessage = "Saved \(gridOrderedImages.images.count) individual images + 1 clean grid chart to Photos!"
        showingSaveAlert = true
    }
    
    private func createGridOrderedArrays() -> (images: [UIImage], faceData: [(yaw: Double, pitch: Double, roll: Double)]) {
        var gridOrderedImages: [UIImage] = []
        var gridOrderedFaceData: [(yaw: Double, pitch: Double, roll: Double)] = []
        
        print("🔄 Creating grid-ordered arrays from \(images.count) images")
        
        // Create arrays in grid order (positions 1-9)
        for gridPosition in 0..<9 {
            if let displayIndex = gridToDisplayMap[gridPosition], displayIndex < images.count {
                gridOrderedImages.append(images[displayIndex])
                print("✅ Grid position \(gridPosition + 1) -> Display index \(displayIndex)")
                if displayIndex < faceData.count {
                    gridOrderedFaceData.append(faceData[displayIndex])
                } else {
                    gridOrderedFaceData.append((yaw: 0.0, pitch: 0.0, roll: 0.0))
                }
            }
        }
        
        print("📊 Final grid has \(gridOrderedImages.count) images")
        return (images: gridOrderedImages, faceData: gridOrderedFaceData)
    }
    
    private func saveIndividualImage(_ image: UIImage, index: Int, faceData: (yaw: Double, pitch: Double, roll: Double)) {
        // Create a labeled version of each image with face tracking data
        // IMPORTANT: Save FULL SIZE original image, not scaled
        let labeledImage = addLabelToImage(
            image, // Use original full-size image
            label: "9eye - Image \(index)",
            faceData: faceData
        )
        UIImageWriteToSavedPhotosAlbum(labeledImage, nil, nil, nil)
    }
    
    private func addLabelToImage(_ image: UIImage, label: String, faceData: (yaw: Double, pitch: Double, roll: Double)) -> UIImage {
        let padding: CGFloat = 20
        let labelHeight: CGFloat = 80 // Increased height for face data
        let newSize = CGSize(
            width: image.size.width, // Use original image dimensions
            height: image.size.height + labelHeight + padding
        )
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // White background
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: newSize))
            
            // Draw the FULL SIZE image
            image.draw(at: CGPoint(x: 0, y: labelHeight + padding))
            
            // Draw the main label
            let labelFont = UIFont.boldSystemFont(ofSize: 18)
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: UIColor.black
            ]
            let labelSize = label.size(withAttributes: labelAttributes)
            let labelX = (newSize.width - labelSize.width) / 2
            let labelY: CGFloat = 10
            
            label.draw(at: CGPoint(x: labelX, y: labelY), withAttributes: labelAttributes)
            
            // Draw face tracking data
            let faceDataText = String(format: "Yaw: %.1f°  Pitch: %.1f°  Roll: %.1f°",
                                    faceData.yaw, faceData.pitch, faceData.roll)
            let faceDataFont = UIFont.systemFont(ofSize: 14)
            let faceDataAttributes: [NSAttributedString.Key: Any] = [
                .font: faceDataFont,
                .foregroundColor: UIColor.darkGray
            ]
            let faceDataSize = faceDataText.size(withAttributes: faceDataAttributes)
            let faceDataX = (newSize.width - faceDataSize.width) / 2
            let faceDataY: CGFloat = 40
            
            faceDataText.draw(at: CGPoint(x: faceDataX, y: faceDataY), withAttributes: faceDataAttributes)
        }
    }
    
    // MARK: - DYNAMIC GRID IMAGE - Replace in ImageView.swift
    private func createCleanGridImage() -> UIImage {
        guard !images.isEmpty else { return UIImage() }
        
        // Create grid-ordered images
        let gridOrderedImages = createGridOrderedArrays().images
        
        // ✅ Find the actual dimensions of the cropped images (no forcing to squares)
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        for image in gridOrderedImages {
            maxWidth = max(maxWidth, image.size.width)
            maxHeight = max(maxHeight, image.size.height)
        }
        
        // ✅ Use actual image dimensions, not fixed square cells
        let cellWidth = maxWidth
        let cellHeight = maxHeight
        
        // Minimal spacing between images
        let spacing: CGFloat = 2
        
        // Calculate total canvas size for 3x3 grid using actual image dimensions
        let canvasWidth = (cellWidth * 3) + (spacing * 2)
        let canvasHeight = (cellHeight * 3) + (spacing * 2)
        
        print("Creating dynamic grid: \(canvasWidth) x \(canvasHeight)")
        print("Cell size: \(cellWidth) x \(cellHeight) (actual image dimensions)")
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasWidth, height: canvasHeight))
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // White background
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
            
            // Draw 3x3 grid with images at their natural size
            for row in 0..<3 {
                for col in 0..<3 {
                    let gridPosition = row * 3 + col
                    
                    if gridPosition < gridOrderedImages.count {
                        let x = CGFloat(col) * (cellWidth + spacing)
                        let y = CGFloat(row) * (cellHeight + spacing)
                        
                        // Get the image for this grid position
                        let originalImage = gridOrderedImages[gridPosition]
                        
                        // ✅ Draw image at its natural size, centered in the cell
                        let imageWidth = originalImage.size.width
                        let imageHeight = originalImage.size.height
                        
                        let centeredX = x + (cellWidth - imageWidth) / 2
                        let centeredY = y + (cellHeight - imageHeight) / 2
                        
                        let imageRect = CGRect(
                            x: centeredX,
                            y: centeredY,
                            width: imageWidth,
                            height: imageHeight
                        )
                        
                        // Draw the original image without scaling
                        originalImage.draw(in: imageRect)
                        
                        print("Drew image \(gridPosition + 1): \(imageWidth) x \(imageHeight) at natural size")
                    } else {
                        // Empty slot placeholder (rarely needed since you have 9 images)
                        let x = CGFloat(col) * (cellWidth + spacing)
                        let y = CGFloat(row) * (cellHeight + spacing)
                        let placeholderRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
                        
                        cgContext.setFillColor(UIColor.systemGray6.cgColor)
                        cgContext.fill(placeholderRect)
                        
                        cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
                        cgContext.setLineWidth(1)
                        cgContext.stroke(placeholderRect)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper method to rotate image 90 degrees counterclockwise (kept for reference but not used in clean grid)
    private func rotateImageCounterclockwise(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        // Create a new image rotated 90 degrees counterclockwise
        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)
        
        let renderer = UIGraphicsImageRenderer(size: rotatedSize)
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Move to center, rotate, then move back
            cgContext.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            cgContext.rotate(by: -CGFloat.pi / 2) // Rotate 90 degrees counterclockwise
            cgContext.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
            
            // Draw the original image
            cgContext.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
        }
    }
}
