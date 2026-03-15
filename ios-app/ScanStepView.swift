import SwiftUI
import ARKit
import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct ScanStepView: View {
    @ObservedObject var session: AnimalSession
    let onNext: () -> Void

    @StateObject private var viewModel = ScanViewModel()
    @State private var showSkipAlert = false
    @State private var saveErrorMessage: String?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    private let ciContext = CIContext()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("LiDAR Burst Capture")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text(headerText)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(.bottom, 14)

            ZStack {
                ARScanView(viewModel: viewModel)
                    .cornerRadius(16)
                    .padding(.horizontal, 16)

                if viewModel.state == .targeting {
                    targetingOverlay
                }

                if viewModel.state == .burstCapturing ||
                    viewModel.state == .selectingBest ||
                    viewModel.state == .captured {
                    captureHUD
                }
            }
            .frame(maxHeight: .infinity)

            controlBar
                .padding(.top, 12)
        }
        .padding(.top, 20)
        .alert("Skip Capture?", isPresented: $showSkipAlert) {
            Button("Skip", role: .destructive) { onNext() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Depth capture helps later measurement. Skip only if needed.")
        }
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }

    private var targetingOverlay: some View {
        VStack {
            Spacer()

            ZStack {
                Circle()
                    .stroke(ringColour.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)

                Circle()
                    .stroke(ringColour, lineWidth: 3)
                    .frame(width: 80, height: 80)

                VStack(spacing: 0) {
                    Rectangle().fill(ringColour).frame(width: 1, height: 20)
                    Spacer().frame(height: 16)
                    Rectangle().fill(ringColour).frame(width: 1, height: 20)
                }

                HStack(spacing: 0) {
                    Rectangle().fill(ringColour).frame(width: 20, height: 1)
                    Spacer().frame(width: 16)
                    Rectangle().fill(ringColour).frame(width: 20, height: 1)
                }
            }

            if viewModel.targetDistance > 0 {
                VStack(spacing: 6) {
                    Text(distanceLabel)
                        .font(.caption.bold())
                        .foregroundColor(ringColour)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)

                    Text(viewModel.guidanceText)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
    }

    private var ringColour: Color {
        viewModel.animalDetected ? .green : .white.opacity(0.5)
    }

    private var distanceLabel: String {
        let d = viewModel.targetDistance
        if d < 1.0 { return String(format: "%.1fm — too close", d) }
        if d > 3.2 { return String(format: "%.1fm — too far", d) }
        return String(format: "%.1fm", d)
    }

    private var captureHUD: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(viewModel.pointCount) valid depth samples", systemImage: "dot.scope")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)

                    if viewModel.state == .burstCapturing || viewModel.state == .selectingBest {
                        Text("Frames: \(viewModel.burstFrameCount)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.9))

                        Text(String(format: "Best score: %.2f", viewModel.bestCandidateScore))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)

                Spacer()

                Text(viewModel.qualityLevel)
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            switch viewModel.state {
            case .targeting:
                Text("Point at the cow, then start a short burst")
                    .font(.caption)
                    .foregroundColor(.gray)

                HStack(spacing: 12) {
                    Button("Skip Capture") {
                        showSkipAlert = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(12)

                    Button("Start Burst") {
                        viewModel.startBurstCapture()
                    }
                    .font(.title3.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.green, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }

            case .burstCapturing:
                VStack(spacing: 10) {
                    Text("Move slowly around the cow, then stop")
                        .font(.caption.bold())
                        .foregroundColor(.green)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            viewModel.cancelBurstCapture()
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3))
                        )

                        Button("Stop & Pick Best") {
                            viewModel.stopBurstCapture()
                        }
                        .font(.title3.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.cyan, Color(red: 0, green: 0.9, blue: 0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                    }
                }

            case .selectingBest:
                Text("Selecting the best frame...")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)

                ProgressView()
                    .tint(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)

            case .captured:
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Re-capture") {
                            viewModel.resetToTargeting()
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.cyan.opacity(0.3))
                        )

                        Button("Save & Next →") {
                            saveCapture()
                        }
                        .font(.title3.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .cornerRadius(12)
                    }

                    Button("Share Capture Files") {
                        shareCaptureFiles()
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private var headerText: String {
        switch viewModel.state {
        case .targeting:
            return "Aim at the cow and tap Start Burst"
        case .burstCapturing:
            return "Capturing many RGB + depth frames"
        case .selectingBest:
            return "Selecting the best frame"
        case .captured:
            return "Best frame captured successfully"
        }
    }

    private func saveCapture() {
        guard let capture = viewModel.capturedFrame else {
            saveErrorMessage = "No captured frame is available to save."
            return
        }

        let folder = AnimalSession.sessionFolder(for: session)
        let baseName = "animal_\(session.sessionNumber)_\(session.id.prefix(8))"

        let rgbFilename = "\(baseName)_rgb.jpg"
        let depthFilename = "\(baseName)_depth.bin"
        let metadataFilename = "\(baseName)_meta.json"
        let plyFilename = "\(baseName)_bestframe.ply"

        let rgbURL = folder.appendingPathComponent(rgbFilename)
        let depthURL = folder.appendingPathComponent(depthFilename)
        let metadataURL = folder.appendingPathComponent(metadataFilename)
        let plyURL = folder.appendingPathComponent(plyFilename)

        do {
            try saveRGBPixelBuffer(capture.rgbImage, to: rgbURL)
            try saveDepthPixelBufferAsFloat32Binary(capture.depthMap, to: depthURL)
            try saveMetadata(for: capture, to: metadataURL)
            try savePLY(for: capture, to: plyURL)

            session.rgbCaptureFilename = rgbFilename
            session.depthCaptureFilename = depthFilename
            session.captureMetadataFilename = metadataFilename
            session.plyFilename = plyFilename
            session.timestamp = Date()
            session.save()

            onNext()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func shareCaptureFiles() {
        let folder = AnimalSession.sessionFolder(for: session)
        let baseName = "animal_\(session.sessionNumber)_\(session.id.prefix(8))"

        let rgbURL = folder.appendingPathComponent("\(baseName)_rgb.jpg")
        let depthURL = folder.appendingPathComponent("\(baseName)_depth.bin")
        let metadataURL = folder.appendingPathComponent("\(baseName)_meta.json")
        let plyURL = folder.appendingPathComponent("\(baseName)_bestframe.ply")

        var items: [Any] = []

        if FileManager.default.fileExists(atPath: rgbURL.path) {
            items.append(rgbURL)
        }
        if FileManager.default.fileExists(atPath: depthURL.path) {
            items.append(depthURL)
        }
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            items.append(metadataURL)
        }
        if FileManager.default.fileExists(atPath: plyURL.path) {
            items.append(plyURL)
        }

        if items.isEmpty {
            saveErrorMessage = "No saved capture files were found to share. Save the capture first."
            return
        }

        shareItems = items
        DispatchQueue.main.async {
            showShareSheet = true
        }
    }

    private func saveRGBPixelBuffer(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw SaveCaptureError.failedToCreateColorSpace
        }

        guard let cgImage = ciContext.createCGImage(
            ciImage,
            from: ciImage.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw SaveCaptureError.failedToCreateCGImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw SaveCaptureError.failedToCreateImageDestination
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw SaveCaptureError.failedToWriteRGBImage
        }
    }

    private func saveDepthPixelBufferAsFloat32Binary(_ depthMap: CVPixelBuffer, to url: URL) throws {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else {
            throw SaveCaptureError.failedToAccessDepthBuffer
        }

        // Depth maps are kCVPixelFormatType_DepthFloat32 — read directly as Float32.
        let ptr = base.assumingMemoryBound(to: Float32.self)
        var values = [Float32]()
        values.reserveCapacity(width * height)

        for i in 0..<(width * height) {
            values.append(ptr[i])
        }

        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url, options: .atomic)
    }

    private func saveMetadata(for capture: CapturedCowFrame, to url: URL) throws {
        let K = capture.intrinsics
        let metadata = DepthCaptureMetadata(
            timestamp: Date(),
            imageWidth: Int(capture.imageResolution.width),
            imageHeight: Int(capture.imageResolution.height),
            depthWidth: Int(capture.depthResolution.width),
            depthHeight: Int(capture.depthResolution.height),
            intrinsics: [
                K[0, 0], K[0, 1], K[0, 2],
                K[1, 0], K[1, 1], K[1, 2],
                K[2, 0], K[2, 1], K[2, 2]
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - YCbCr colour sampling (NV12 / BiPlanarFullRange / VideoRange)

    private func sampleRGB(from buffer: CVPixelBuffer, rgbX: Int, rgbY: Int) -> (UInt8, UInt8, UInt8) {
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let sx = max(0, min(rgbX, w - 1))
        let sy = max(0, min(rgbY, h - 1))

        let yStride  = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)

        let yBase  = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!
            .assumingMemoryBound(to: UInt8.self)
        let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!
            .assumingMemoryBound(to: UInt8.self)

        let yVal  = Float(yBase [sy * yStride  + sx])
        let uvIdx = (sy / 2) * uvStride + (sx / 2) * 2
        let cb    = Float(uvBase[uvIdx])
        let cr    = Float(uvBase[uvIdx + 1])

        // BT.601 full-range YCbCr → RGB
        let y  = yVal  - 16
        let pb = cb    - 128
        let pr = cr    - 128
        let r  = 1.164 * y              + 1.596 * pr
        let g  = 1.164 * y - 0.392 * pb - 0.813 * pr
        let b  = 1.164 * y + 2.017 * pb

        return (
            UInt8(max(0, min(255, Int(r.rounded())))),
            UInt8(max(0, min(255, Int(g.rounded())))),
            UInt8(max(0, min(255, Int(b.rounded()))))
        )
    }

    private func savePLY(for capture: CapturedCowFrame, to url: URL) throws {
        let depthMap = capture.depthMap
        let dWidth  = CVPixelBufferGetWidth(depthMap)
        let dHeight = CVPixelBufferGetHeight(depthMap)

        // ── Lock depth ────────────────────────────────────────────────────────
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else {
            throw SaveCaptureError.failedToAccessDepthBuffer
        }
        // ARKit depth maps are kCVPixelFormatType_DepthFloat32.
        let depthPtr = depthBase.assumingMemoryBound(to: Float32.self)

        // ── Lock confidence (optional) ─────────────────────────────────────────
        let confMap = capture.confidenceMap
        var confPtr: UnsafeMutablePointer<UInt8>? = nil
        var confRowStride = 0
        if let cm = confMap {
            CVPixelBufferLockBaseAddress(cm, .readOnly)
            if let cb = CVPixelBufferGetBaseAddress(cm) {
                confPtr       = cb.assumingMemoryBound(to: UInt8.self)
                confRowStride = CVPixelBufferGetBytesPerRow(cm)
            }
        }
        defer { if let cm = confMap { CVPixelBufferUnlockBaseAddress(cm, .readOnly) } }

        // ── Lock RGB ───────────────────────────────────────────────────────────
        let rgbBuf = capture.rgbImage
        CVPixelBufferLockBaseAddress(rgbBuf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(rgbBuf, .readOnly) }

        let rgbWidth  = CVPixelBufferGetWidth(rgbBuf)
        let rgbHeight = CVPixelBufferGetHeight(rgbBuf)

        // ── Camera intrinsics ──────────────────────────────────────────────────
        let fx = capture.intrinsics[0, 0]
        let fy = capture.intrinsics[1, 1]
        let cx = capture.intrinsics[2, 0]
        let cy = capture.intrinsics[2, 1]

        // Scale depth pixel coords into full-resolution image space for unprojection.
        let scaleX = Float(capture.imageResolution.width)  / Float(dWidth)
        let scaleY = Float(capture.imageResolution.height) / Float(dHeight)

        // Scale from full-res image space to the (potentially different) RGB buffer size.
        let rgbScaleX = Float(rgbWidth)  / Float(capture.imageResolution.width)
        let rgbScaleY = Float(rgbHeight) / Float(capture.imageResolution.height)

        // ── Build point list ───────────────────────────────────────────────────
        struct ColoredPoint { let pos: SIMD3<Float>; let r, g, b: UInt8 }
        var points: [ColoredPoint] = []
        points.reserveCapacity(dWidth * dHeight)

        for y in 0..<dHeight {
            for x in 0..<dWidth {
                let z = depthPtr[y * dWidth + x]
                guard z > 0.25 && z < 4.0 && z.isFinite else { continue }

                // Only keep high-confidence pixels (ARConfidenceLevel.high == 2).
                // This removes the majority of noise the LiDAR produces.
                if let cp = confPtr {
                    let conf = cp[y * confRowStride + x]
                    guard conf >= 2 else { continue }
                }

                let imageX = Float(x) * scaleX
                let imageY = Float(y) * scaleY

                let X = (imageX - cx) * z / fx
                let Y = (imageY - cy) * z / fy

                // Sample colour from the RGB camera frame.
                let rgbX = Int((imageX * rgbScaleX).rounded())
                let rgbY = Int((imageY * rgbScaleY).rounded())
                let (r, g, b) = sampleRGB(from: rgbBuf, rgbX: rgbX, rgbY: rgbY)

                points.append(ColoredPoint(pos: SIMD3(X, Y, z), r: r, g: g, b: b))
            }
        }

        // ── Write PLY ──────────────────────────────────────────────────────────
        var ply  = "ply\n"
        ply += "format ascii 1.0\n"
        ply += "element vertex \(points.count)\n"
        ply += "property float x\n"
        ply += "property float y\n"
        ply += "property float z\n"
        ply += "property uchar red\n"
        ply += "property uchar green\n"
        ply += "property uchar blue\n"
        ply += "end_header\n"

        for p in points {
            ply += String(format: "%.6f %.6f %.6f %d %d %d\n",
                          p.pos.x, p.pos.y, p.pos.z, p.r, p.g, p.b)
        }

        try ply.write(to: url, atomically: true, encoding: .utf8)
    }
}

private enum SaveCaptureError: LocalizedError {
    case failedToCreateColorSpace
    case failedToCreateCGImage
    case failedToCreateImageDestination
    case failedToWriteRGBImage
    case failedToAccessDepthBuffer

    var errorDescription: String? {
        switch self {
        case .failedToCreateColorSpace:
            return "Could not create color space for RGB export."
        case .failedToCreateCGImage:
            return "Could not convert the captured camera image into a saveable image."
        case .failedToCreateImageDestination:
            return "Could not create the output image destination."
        case .failedToWriteRGBImage:
            return "Could not write the RGB image to disk."
        case .failedToAccessDepthBuffer:
            return "Could not access the LiDAR depth buffer."
        }
    }
}
