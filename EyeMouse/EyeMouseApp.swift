import SwiftUI
import AVFoundation
import Vision

// MARK: - Face Landmarks View
struct FaceMeshView: NSViewRepresentable {
    var faceLandmarks: VNFaceObservation?
    
    func makeNSView(context: Context) -> NSView {
        let view = FaceMeshDrawingView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? FaceMeshDrawingView else { return }
        view.faceLandmarks = faceLandmarks
        view.needsDisplay = true
    }
}

// MARK: - Custom Drawing View
class FaceMeshDrawingView: NSView {
    var faceLandmarks: VNFaceObservation?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext,
              let landmarks = faceLandmarks?.landmarks else { return }
        
        // Convert normalized coordinates to view coordinates
        // Changed the y-coordinate conversion to match the correct orientation
        let convertPoint = { (point: CGPoint) -> CGPoint in
            return CGPoint(
                x: point.x * self.bounds.width,
                y: point.y * self.bounds.height  // Removed the 1 - point.y conversion
            )
        }
        
        // Helper function to draw closed shapes
        let drawClosedShape = { (points: [CGPoint], color: NSColor) in
            guard let first = points.first else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            let startPoint = convertPoint(first)
            context.move(to: startPoint)
            
            for point in points.dropFirst() {
                context.addLine(to: convertPoint(point))
            }
            context.addLine(to: startPoint)
            context.strokePath()
        }
        
        // Helper function to draw open shapes
        let drawOpenShape = { (points: [CGPoint], color: NSColor) in
            guard let first = points.first else { return }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            let startPoint = convertPoint(first)
            context.move(to: startPoint)
            
            for point in points.dropFirst() {
                context.addLine(to: convertPoint(point))
            }
            context.strokePath()
        }
        
        // Draw face outline
        if let faceContour = landmarks.faceContour?.normalizedPoints {
            drawOpenShape(faceContour, .init(red: 0.0, green: 0.8, blue: 0.3, alpha: 0.8))
        }
        
        // Draw eyes with detailed styling
        if let leftEye = landmarks.leftEye?.normalizedPoints {
            drawClosedShape(leftEye, .init(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.9))
            
            // Draw pupil center point
            if leftEye.count > 0 {
                let center = leftEye.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let avgPoint = CGPoint(x: center.x / CGFloat(leftEye.count), y: center.y / CGFloat(leftEye.count))
                let convertedCenter = convertPoint(avgPoint)
                
                context.setFillColor(NSColor.red.cgColor)
                context.fillEllipse(in: CGRect(x: convertedCenter.x - 2, y: convertedCenter.y - 2, width: 4, height: 4))
            }
        }
        
        if let rightEye = landmarks.rightEye?.normalizedPoints {
            drawClosedShape(rightEye, .init(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.9))
            
            // Draw pupil center point
            if rightEye.count > 0 {
                let center = rightEye.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                let avgPoint = CGPoint(x: center.x / CGFloat(rightEye.count), y: center.y / CGFloat(rightEye.count))
                let convertedCenter = convertPoint(avgPoint)
                
                context.setFillColor(NSColor.red.cgColor)
                context.fillEllipse(in: CGRect(x: convertedCenter.x - 2, y: convertedCenter.y - 2, width: 4, height: 4))
            }
        }
        
        // Draw eyebrows
        if let leftEyebrow = landmarks.leftEyebrow?.normalizedPoints {
            drawOpenShape(leftEyebrow, .init(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.8))
        }
        
        if let rightEyebrow = landmarks.rightEyebrow?.normalizedPoints {
            drawOpenShape(rightEyebrow, .init(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.8))
        }
        
        // Draw nose
        if let nose = landmarks.nose?.normalizedPoints {
            drawOpenShape(nose, .init(red: 1.0, green: 0.4, blue: 0.4, alpha: 0.8))
        }
        
        // Draw outer lips
        if let outerLips = landmarks.outerLips?.normalizedPoints {
            drawClosedShape(outerLips, .init(red: 1.0, green: 0.2, blue: 0.5, alpha: 0.8))
        }
        
        // Draw inner lips
        if let innerLips = landmarks.innerLips?.normalizedPoints {
            drawClosedShape(innerLips, .init(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.8))
        }
        
        // Draw median line
        if let medianLine = landmarks.medianLine?.normalizedPoints {
            drawOpenShape(medianLine, .init(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.6))
        }
    }
}
// MARK: - Eye Tracking Manager
class EyeTrackingManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isSetup = false
    @Published var cameraPermissionGranted = false
    @Published var eyePosition: CGFloat = 0.5
    @Published var lastMovementTime = Date()
    @Published var currentFace: VNFaceObservation?
    
    var captureSession: AVCaptureSession?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var lastEyeX: CGFloat = 0.5
    
    override init() {
        super.init()
        checkCameraPermission()
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.cameraPermissionGranted = true
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraPermissionGranted = granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }
        default:
            self.cameraPermissionGranted = false
        }
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let session = captureSession else { return }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Failed to get camera device")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.addInput(input)
            
            videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput?.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
            
            let videoQueue = DispatchQueue(label: "VideoQueue")
            videoDataOutput?.setSampleBufferDelegate(self, queue: videoQueue)
            
            session.addOutput(videoDataOutput!)
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                DispatchQueue.main.async {
                    self?.isSetup = true
                }
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    private func moveMouseToLeftDisplay() {
        let screens = NSScreen.screens
        if let leftScreen = screens.min(by: { $0.frame.origin.x < $1.frame.origin.x }) {
            let centerX = leftScreen.frame.origin.x + (leftScreen.frame.width / 2)
            let centerY = leftScreen.frame.origin.y + (leftScreen.frame.height / 2)
            CGWarpMouseCursorPosition(CGPoint(x: centerX, y: centerY))
            lastMovementTime = Date()
        }
    }
    
    private func moveMouseToRightDisplay() {
        let screens = NSScreen.screens
        if let rightScreen = screens.max(by: { $0.frame.origin.x < $1.frame.origin.x }) {
            let centerX = rightScreen.frame.origin.x + (rightScreen.frame.width / 2)
            let centerY = rightScreen.frame.origin.y + (rightScreen.frame.height / 2)
            CGWarpMouseCursorPosition(CGPoint(x: centerX, y: centerY))
            lastMovementTime = Date()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let faceDetectionRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let observations = request.results as? [VNFaceObservation],
                  let face = observations.first else { return }
            
            DispatchQueue.main.async {
                self?.currentFace = face
                
                if let leftEye = face.landmarks?.leftEye {
                    let eyeX = leftEye.normalizedPoints[0].x
                    self?.eyePosition = eyeX
                    
                    // Check if sufficient time has passed since last movement
                    guard let lastMove = self?.lastMovementTime,
                          Date().timeIntervalSince(lastMove) > 1.0 else { return }
                    
                    // Move to left display when looking left (eyeX > 0.6)
                    if eyeX > 0.6 && (self?.lastEyeX ?? 0) <= 0.6 {
                        self?.moveMouseToLeftDisplay()
                    }
                    // Move to right display when looking right (eyeX < 0.4)
                    else if eyeX < 0.4 && (self?.lastEyeX ?? 0) >= 0.4 {
                        self?.moveMouseToRightDisplay()
                    }
                    
                    self?.lastEyeX = eyeX
                }
            }
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
        try? imageRequestHandler.perform([faceDetectionRequest])
    }
}

class MouseTracker: ObservableObject {
    @Published var mousePosition: CGPoint = .zero
    private var displayLink: CVDisplayLink?
    
    init() {
        setupDisplayLink()
    }
    
    private let displayLinkOutputCallback: CVDisplayLinkOutputCallback = { displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext in
        
        let tracker = unsafeBitCast(displayLinkContext, to: MouseTracker.self)
        tracker.updateMousePosition()
        return kCVReturnSuccess
    }
    
    private func setupDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        if let displayLink = displayLink {
            let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkSetOutputCallback(displayLink, displayLinkOutputCallback, pointer)
            CVDisplayLinkStart(displayLink)
        }
    }
    
    private func updateMousePosition() {
        let mouseLocation = NSEvent.mouseLocation
        DispatchQueue.main.async {
            self.mousePosition = mouseLocation
        }
    }
    
    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}

struct MonitorLayoutView: NSViewRepresentable {
    @ObservedObject var mouseTracker: MouseTracker
    
    func makeNSView(context: Context) -> NSView {
        let view = MonitorDrawingView()
        view.mouseTracker = mouseTracker
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.needsDisplay = true
    }
}

class MonitorDrawingView: NSView {
    var mouseTracker: MouseTracker?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        // Find the bounds that encompass all screens
        let allScreensRect = screens.reduce(screens[0].frame) { result, screen in
            result.union(screen.frame)
        }
        
        // Calculate scale factor to fit in our view
        let scaleFactor = min(
            bounds.width / allScreensRect.width,
            bounds.height / allScreensRect.height
        ) * 0.9 // 90% of available space
        
        // Calculate offset to center the drawing
        let offsetX = (bounds.width - (allScreensRect.width * scaleFactor)) / 2
        let offsetY = (bounds.height - (allScreensRect.height * scaleFactor)) / 2
        
        // Save the current graphics state
        context.saveGState()
        
        // Transform coordinates
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scaleFactor, y: scaleFactor)
        context.translateBy(x: -allScreensRect.origin.x, y: -allScreensRect.origin.y)
        
        // Draw each screen
        for (index, screen) in screens.enumerated() {
            let rect = screen.frame
            
            // Draw screen outline
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2.0 / scaleFactor)
            context.stroke(rect)
            
            // Fill screen
            context.setFillColor(NSColor.darkGray.cgColor)
            context.fill(rect)
            
            // Draw screen number and resolution
            let text = "\(index + 1) (\(Int(screen.frame.width))x\(Int(screen.frame.height)))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12.0 / scaleFactor),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            let point = NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2
            )
            text.draw(at: point, withAttributes: attributes)
        }
        
        // Draw mouse cursor position
        if let mousePosition = mouseTracker?.mousePosition {
            context.setFillColor(NSColor.red.cgColor)
            let cursorSize = 10.0 / scaleFactor
            let cursorRect = CGRect(
                x: mousePosition.x - cursorSize/2,
                y: mousePosition.y - cursorSize/2,
                width: cursorSize,
                height: cursorSize
            )
            context.fillEllipse(in: cursorRect)
        }
        
        // Restore the graphics state
        context.restoreGState()
    }
}

// Update ContentView to include MouseTracker
struct ContentView: View {
    @StateObject private var eyeTrackingManager = EyeTrackingManager()
    @StateObject private var mouseTracker = MouseTracker()
    
    var body: some View {
        VStack {
            if eyeTrackingManager.cameraPermissionGranted {
                if eyeTrackingManager.isSetup {
                    FaceMeshView(faceLandmarks: eyeTrackingManager.currentFace)
                        .frame(height: 240)
                        .cornerRadius(8)
                    
                    // Monitor Layout with mouse position
                    MonitorLayoutView(mouseTracker: mouseTracker)
                        .frame(height: 100)
                        .cornerRadius(8)
                        .padding(.vertical)
                    
                    // Debug info
                    VStack {
                        Text("Eye Position: \(eyeTrackingManager.eyePosition, specifier: "%.2f")")
                        ProgressView(value: eyeTrackingManager.eyePosition)
                            .padding()
                        Text("Mouse Position: (\(Int(mouseTracker.mousePosition.x)), \(Int(mouseTracker.mousePosition.y)))")
                    }
                    .padding()
                } else {
                    ProgressView("Setting up camera...")
                }
            } else {
                Text("Camera access is required for eye tracking")
                    .foregroundColor(.red)
            }
        }
        .frame(width: 400, height: 500)
        .padding()
    }
}

// MARK: - App Entry Point
@main
struct EyeTrackingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
