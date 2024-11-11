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
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setStrokeColor(NSColor.green.cgColor)
        context.setLineWidth(2.0)
        
        guard let landmarks = faceLandmarks?.landmarks else { return }
        
        // Convert normalized coordinates to view coordinates
        let convertPoint = { (point: CGPoint) -> CGPoint in
            return CGPoint(
                x: point.x * self.bounds.width,
                y: (1 - point.y) * self.bounds.height
            )
        }
        
        // Draw function for points array
        let drawPoints = { (points: [CGPoint]) in
            guard let first = points.first else { return }
            let startPoint = convertPoint(first)
            context.move(to: startPoint)
            
            for point in points.dropFirst() {
                let cgPoint = convertPoint(point)
                context.addLine(to: cgPoint)
            }
            context.strokePath()
        }
        
        // Draw all available landmarks
        if let allPoints = landmarks.allPoints?.normalizedPoints {
            drawPoints(allPoints)
        }
        
        // Draw eyes with different color
        context.setStrokeColor(NSColor.yellow.cgColor)
        if let leftEye = landmarks.leftEye?.normalizedPoints {
            drawPoints(leftEye + [leftEye[0]])  // Close the eye contour
        }
        if let rightEye = landmarks.rightEye?.normalizedPoints {
            drawPoints(rightEye + [rightEye[0]])  // Close the eye contour
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
                    
                    // Only move mouse if sufficient time has passed since last movement
                    if eyeX < 0.4 && (self?.lastEyeX ?? 0) >= 0.4 {
                        if let lastMove = self?.lastMovementTime,
                           Date().timeIntervalSince(lastMove) > 1.0 {
                            self?.moveMouseToLeftDisplay()
                        }
                    }
                    self?.lastEyeX = eyeX
                }
            }
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
        try? imageRequestHandler.perform([faceDetectionRequest])
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var eyeTrackingManager = EyeTrackingManager()
    
    var body: some View {
        VStack {
            if eyeTrackingManager.cameraPermissionGranted {
                if eyeTrackingManager.isSetup {
                    FaceMeshView(faceLandmarks: eyeTrackingManager.currentFace)
                        .frame(height: 240)
                        .cornerRadius(8)
                    
                    // Debug info
                    VStack {
                        Text("Eye Position: \(eyeTrackingManager.eyePosition, specifier: "%.2f")")
                        ProgressView(value: eyeTrackingManager.eyePosition)
                            .padding()
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
        .frame(width: 400, height: 400)
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
