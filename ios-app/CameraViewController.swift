import UIKit
import AVFoundation

protocol CameraViewControllerDelegate: AnyObject {
    func didCapturePhoto(payload: CapturedPayload)
}

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    weak var delegate: CameraViewControllerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    // MARK: - Setup

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("[camera] No back camera — simulator path, skipping setup")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .photo
        captureSession = session

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }

            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                // Enable depth delivery on the OUTPUT object once, at setup time.
                if output.isDepthDataDeliverySupported {
                    output.isDepthDataDeliveryEnabled = true
                    print("[camera] Depth delivery enabled on output")
                } else {
                    print("[camera] Depth delivery NOT supported on this device")
                }
            }
            photoOutput = output

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.layer.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                print("[camera] Session started")
            }
        } catch {
            print("[camera] Setup error: \(error)")
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard let output = photoOutput else { return }
        let settings = AVCapturePhotoSettings()
        // Enable depth delivery on the SETTINGS object, gated on what the output supports.
        if output.isDepthDataDeliveryEnabled {
            settings.isDepthDataDeliveryEnabled = true
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            print("[camera] Capture error: \(error!)")
            return
        }

        guard let photoData = photo.fileDataRepresentation() else {
            print("[camera] Failed to get JPEG data from photo")
            return
        }

        var tightDepthData = Data()
        var depthWidth = 0
        var depthHeight = 0
        var intrinsicsString = ""
        var referenceWidth: Float = 0
        var referenceHeight: Float = 0

        if let rawDepth = photo.depthData {
            // ─────────────────────────────────────────────────────────────────
            // STEP 1 — Convert to Float32.
            // Hardware may deliver kCVPixelFormatType_DepthFloat16; reading those
            // bytes as Float32 on the server produces silent garbage. Always upcast.
            // ─────────────────────────────────────────────────────────────────
            let depth32 = rawDepth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            print("[depth] Converted from type \(rawDepth.depthDataType) → Float32 (\(kCVPixelFormatType_DepthFloat32))")

            let pixelBuffer = depth32.depthDataMap

            // ─────────────────────────────────────────────────────────────────
            // STEP 2 — Strip hardware row-stride padding.
            // CVPixelBuffer rows are aligned to a hardware boundary, so
            // bytesPerRow >= width * 4. The server does reshape((H, W)) and
            // will produce garbage if padding bytes are included.
            // ─────────────────────────────────────────────────────────────────
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            let width       = CVPixelBufferGetWidth(pixelBuffer)
            let height      = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer) // hardware stride
            let bytesPerPixel = 4 // Float32

            depthWidth  = width
            depthHeight = height

            // Use GetBaseAddress (NOT GetBaseAddressOfPlane) —
            // kCVPixelFormatType_DepthFloat32 is a non-planar format.
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                print("[depth] ERROR: could not get base address")
                return
            }

            var tight = Data(capacity: width * height * bytesPerPixel)
            for row in 0..<height {
                let rowStart = baseAddress.advanced(by: row * bytesPerRow)
                tight.append(rowStart.assumingMemoryBound(to: UInt8.self),
                              count: width * bytesPerPixel)
            }

            let expectedBytes = width * height * bytesPerPixel
            print("[depth] width=\(width) height=\(height) hwStride=\(bytesPerRow) tightBytes=\(tight.count) expected=\(expectedBytes)")
            if tight.count != expectedBytes {
                print("[depth] ⚠️  MISMATCH — something is wrong with padding removal")
            }

            tightDepthData = tight

            // ─────────────────────────────────────────────────────────────────
            // STEP 3 — Transpose intrinsics from column-major to row-major.
            // AVFoundation gives simd_float3x3 in column-major storage, so
            // columns.0 is the first COLUMN (not the first row).
            // The server expects row-major [[fx,0,cx],[0,fy,cy],[0,0,1]].
            // ─────────────────────────────────────────────────────────────────
            if let calibration = depth32.cameraCalibrationData {
                let m = calibration.intrinsicMatrix
                let rowMajor: [[Float]] = [
                    [m.columns.0.x, m.columns.1.x, m.columns.2.x],
                    [m.columns.0.y, m.columns.1.y, m.columns.2.y],
                    [m.columns.0.z, m.columns.1.z, m.columns.2.z],
                ]
                print("[intrinsics] Transposed row-major: \(rowMajor)")

                if let jsonData = try? JSONEncoder().encode(rowMajor),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    intrinsicsString = jsonStr
                }

                let refDims = calibration.intrinsicMatrixReferenceDimensions
                referenceWidth  = Float(refDims.width)
                referenceHeight = Float(refDims.height)
                print("[intrinsics] Reference dimensions: \(referenceWidth) × \(referenceHeight)")
            } else {
                print("[intrinsics] No calibration data available")
            }
        } else {
            print("[depth] No depth data in this capture (non-LiDAR device?)")
        }

        let payload = CapturedPayload(
            depthData: tightDepthData,
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            photoData: photoData,
            intrinsicsString: intrinsicsString,
            referenceWidth: referenceWidth,
            referenceHeight: referenceHeight
        )

        DispatchQueue.main.async {
            self.delegate?.didCapturePhoto(payload: payload)
        }
    }
}
