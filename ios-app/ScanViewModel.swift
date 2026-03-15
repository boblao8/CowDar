import Foundation
import ARKit
import SwiftUI
internal import Combine
import CoreVideo
import simd
import QuartzCore

enum ScanState {
    case targeting
    case burstCapturing
    case selectingBest
    case captured
}

struct CapturedCowFrame {
    let rgbImage: CVPixelBuffer
    let depthMap: CVPixelBuffer
    let confidenceMap: CVPixelBuffer?   // nil if unavailable; use for high-confidence filtering
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
    let depthResolution: CGSize
    let timestamp: TimeInterval
}

struct CaptureCandidate {
    let frame: CapturedCowFrame
    let score: Float
    let validDepthSamples: Int
}

final class ScanViewModel: ObservableObject {
    @Published var state: ScanState = .targeting
    @Published var qualityLevel: String = "Aim at the cow"
    @Published var targetDistance: Float = 0
    @Published var animalDetected: Bool = false
    @Published var pointCount: Int = 0
    @Published var guidanceText: String = "Aim at the cow"
    @Published var capturedFrame: CapturedCowFrame?
    @Published var burstFrameCount: Int = 0
    @Published var bestCandidateScore: Float = 0

    weak var arSession: ARSession?

    private var candidates: [CaptureCandidate] = []
    private var burstStartTime: TimeInterval?
    private let maxBurstDuration: TimeInterval = 4.0
    private var processedFrameCounter = 0

    private var smoothedTargetDistance: Float = 0
    private let smoothingAlpha: Float = 0.22

    // MARK: - Session config

    func configureForTargeting(session: ARSession) {
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func configureForCapture(session: ARSession) {
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        session.run(config, options: [])
    }

    // MARK: - Live guidance

    func updateTargeting(frame: ARFrame) {
        guard state == .targeting else { return }

        guard let depthMap = (frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap) else {
            DispatchQueue.main.async {
                self.animalDetected = false
                self.guidanceText = "No depth available"
                self.targetDistance = 0
                self.qualityLevel = "Aim at the cow"
            }
            return
        }

        guard let analysis = analyzeDepthMap(depthMap) else {
            DispatchQueue.main.async {
                self.animalDetected = false
                self.guidanceText = "Aim at the cow"
                self.targetDistance = 0
                self.qualityLevel = "Aim at the cow"
            }
            return
        }

        if smoothedTargetDistance == 0 {
            smoothedTargetDistance = analysis.subjectDistance
        } else {
            smoothedTargetDistance =
                (1 - smoothingAlpha) * smoothedTargetDistance +
                smoothingAlpha * analysis.subjectDistance
        }

        let distance = smoothedTargetDistance
        let coverage = analysis.coverage
        let offsetX = analysis.offsetX
        let offsetY = analysis.offsetY

        var guidance = "Looks good"
        var okay = true

        if distance < 1.0 {
            guidance = "Move further back"
            okay = false
        } else if distance > 3.2 {
            guidance = "Move closer"
            okay = false
        } else if coverage < 0.035 {
            guidance = "Get more of the cow in frame"
            okay = false
        } else if offsetX < -0.12 {
            guidance = "Move camera left"
            okay = false
        } else if offsetX > 0.12 {
            guidance = "Move camera right"
            okay = false
        } else if offsetY < -0.12 {
            guidance = "Aim lower"
            okay = false
        } else if offsetY > 0.12 {
            guidance = "Aim higher"
            okay = false
        }

        DispatchQueue.main.async {
            self.targetDistance = distance
            self.animalDetected = okay
            self.guidanceText = guidance
            self.pointCount = analysis.validDepthSamples
            self.qualityLevel = okay ? "Ready for burst capture" : "Adjust framing"
        }
    }

    // MARK: - Burst capture lifecycle

    func startBurstCapture() {
        guard let session = arSession else { return }

        configureForCapture(session: session)

        capturedFrame = nil
        candidates.removeAll()
        burstFrameCount = 0
        bestCandidateScore = 0
        pointCount = 0
        processedFrameCounter = 0
        burstStartTime = CACurrentMediaTime()
        qualityLevel = "Capturing burst..."
        guidanceText = "Move slowly around the cow"
        state = .burstCapturing
    }

    func stopBurstCapture() {
        guard state == .burstCapturing else { return }
        finalizeBestCapture()
    }

    func cancelBurstCapture() {
        guard state == .burstCapturing || state == .selectingBest else { return }
        candidates.removeAll()
        burstFrameCount = 0
        bestCandidateScore = 0
        qualityLevel = "Aim at the cow"
        guidanceText = "Aim at the cow"
        pointCount = 0
        state = .targeting
    }

    func resetToTargeting() {
        capturedFrame = nil
        candidates.removeAll()
        burstFrameCount = 0
        bestCandidateScore = 0
        pointCount = 0
        targetDistance = 0
        smoothedTargetDistance = 0
        qualityLevel = "Aim at the cow"
        guidanceText = "Aim at the cow"
        animalDetected = false
        processedFrameCounter = 0
        burstStartTime = nil
        state = .targeting
    }

    func processFrame(_ frame: ARFrame) {
        guard state == .burstCapturing else { return }

        if let start = burstStartTime,
           CACurrentMediaTime() - start >= maxBurstDuration {
            finalizeBestCapture()
            return
        }

        processedFrameCounter += 1
        if processedFrameCounter % 2 != 0 { return }

        guard let scored = scoreFrame(frame) else { return }
        // Use smoothed depth for scoring (stable distances) but keep the raw
        // confidence map from sceneDepth — it is aligned with the raw depth map
        // and used later when exporting the PLY.
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let confidenceMap = frame.sceneDepth?.confidenceMap

        let candidateFrame = CapturedCowFrame(
            rgbImage: frame.capturedImage,
            depthMap: depthData.depthMap,
            confidenceMap: confidenceMap,
            intrinsics: frame.camera.intrinsics,
            imageResolution: CGSize(
                width: frame.camera.imageResolution.width,
                height: frame.camera.imageResolution.height
            ),
            depthResolution: CGSize(
                width: CVPixelBufferGetWidth(depthData.depthMap),
                height: CVPixelBufferGetHeight(depthData.depthMap)
            ),
            timestamp: frame.timestamp
        )

        let candidate = CaptureCandidate(
            frame: candidateFrame,
            score: scored.score,
            validDepthSamples: scored.validDepthSamples
        )

        candidates.append(candidate)

        DispatchQueue.main.async {
            self.burstFrameCount = self.candidates.count
            self.bestCandidateScore = max(self.bestCandidateScore, candidate.score)
            self.pointCount = candidate.validDepthSamples
            self.targetDistance = scored.subjectDistance
            self.qualityLevel = String(format: "Best score: %.2f", self.bestCandidateScore)
            self.guidanceText = "Move slowly around the cow"
        }
    }

    private func finalizeBestCapture() {
        DispatchQueue.main.async {
            self.state = .selectingBest
            self.qualityLevel = "Selecting best frame..."
            self.guidanceText = "Please wait"
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            DispatchQueue.main.async {
                self.qualityLevel = "No usable frame found"
                self.guidanceText = "Try again"
                self.state = .targeting
            }
            return
        }

        DispatchQueue.main.async {
            self.capturedFrame = best.frame
            self.pointCount = best.validDepthSamples
            self.bestCandidateScore = best.score
            self.qualityLevel = String(format: "Best frame selected (%.2f)", best.score)
            self.guidanceText = "Best frame ready"
            self.state = .captured
        }
    }

    // MARK: - Depth analysis / scoring

    private struct DepthAnalysis {
        let subjectDistance: Float
        let coverage: Float
        let offsetX: Float
        let offsetY: Float
        let validDepthSamples: Int
    }

    private func analyzeDepthMap(_ depthMap: CVPixelBuffer) -> DepthAnalysis? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        // ARKit depth maps are kCVPixelFormatType_DepthFloat32 — read as Float32.
        let ptr = base.assumingMemoryBound(to: Float32.self)

        // Smaller central ROI gives better distance estimate than a huge box.
        let minX = width * 38 / 100
        let maxX = width * 62 / 100
        let minY = height * 28 / 100
        let maxY = height * 72 / 100

        var depths: [Float] = []
        var validXSum: Float = 0
        var validYSum: Float = 0
        var validCount: Float = 0

        for y in Swift.stride(from: minY, to: maxY, by: 2) {
            for x in Swift.stride(from: minX, to: maxX, by: 2) {
                let d = ptr[y * width + x]
                if d > 0.35 && d < 6.0 {
                    depths.append(d)
                    validXSum += Float(x)
                    validYSum += Float(y)
                    validCount += 1
                }
            }
        }

        guard !depths.isEmpty else { return nil }

        depths.sort()

        // Lower percentile tends to lock onto the nearer cow body rather than deeper background.
        let percentileIndex = max(0, min(depths.count - 1, Int(Float(depths.count) * 0.30)))
        let subjectDistance = depths[percentileIndex]

        let roiSampleCount = Float(((maxX - minX) / 2) * ((maxY - minY) / 2))
        let coverage = validCount / max(roiSampleCount, 1)

        let avgX = validXSum / validCount
        let avgY = validYSum / validCount
        let centerX = Float(width) / 2
        let centerY = Float(height) / 2

        let offsetX = (avgX - centerX) / Float(width)
        let offsetY = (avgY - centerY) / Float(height)

        return DepthAnalysis(
            subjectDistance: subjectDistance,
            coverage: coverage,
            offsetX: offsetX,
            offsetY: offsetY,
            validDepthSamples: Int(validCount)
        )
    }

    // Counts pixels that belong to the near-foreground depth cluster (the cow).
    // Uses a wide ROI so the cow doesn't have to be perfectly centred to be counted.
    private func countCowDepthPixels(_ depthMap: CVPixelBuffer) -> (cowPixelCount: Int, cowDepth: Float)? {
        let width  = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        // ARKit depth maps are kCVPixelFormatType_DepthFloat32.
        let ptr = base.assumingMemoryBound(to: Float32.self)

        // Wide ROI — only skip the very edges so the cow is captured
        // wherever it happens to be in the frame.
        let minX = width  / 20        // 5 % left margin
        let maxX = width  * 19 / 20   // 5 % right margin
        let minY = height / 10        // 10 % top (avoid ceiling / sky)
        let maxY = height * 9  / 10   // 10 % bottom (reduce floor hits)

        // Collect every valid depth in the wide ROI.
        var allDepths: [Float] = []
        allDepths.reserveCapacity((maxX - minX) * (maxY - minY))

        for y in minY..<maxY {
            for x in minX..<maxX {
                let d = ptr[y * width + x]
                if d > 0.25 && d < 5.0 {
                    allDepths.append(d)
                }
            }
        }

        guard allDepths.count > 100 else { return nil }

        allDepths.sort()

        // The cow is the nearest large object — use the 20th-percentile depth
        // as the front surface of the cow, then extend 1.2 m backwards to
        // cover the full body depth when viewed from the side.
        let nearIdx   = max(0, Int(Float(allDepths.count) * 0.20))
        let nearDepth = allDepths[nearIdx]

        let cowFront = max(0.25, nearDepth - 0.10)   // a little in front of the body
        let cowBack  = nearDepth + 1.20              // ~1 m body depth side-on

        var cowCount = 0
        for d in allDepths where d >= cowFront && d <= cowBack {
            cowCount += 1
        }

        return (cowPixelCount: cowCount, cowDepth: nearDepth)
    }

    private func scoreFrame(_ frame: ARFrame) -> (score: Float, validDepthSamples: Int, subjectDistance: Float)? {
        guard let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap else {
            return nil
        }

        // Primary metric: number of pixels belonging to the cow's depth band.
        // More cow pixels = better frame.  Normalise against a "very good" scan
        // (~20 000 cow pixels fills a decent side-on view at 2 m).
        guard let cowStats = countCowDepthPixels(depthMap) else { return nil }

        let coverageScore = min(Float(cowStats.cowPixelCount) / 20_000.0, 1.0)

        // Small sanity penalty for extreme distances only — does not penalise
        // good coverage at slightly non-ideal distances.
        let preferredDistance: Float = 2.0
        let distanceTolerance: Float = 1.8
        let distanceScore = max(0.0, 1.0 - abs(cowStats.cowDepth - preferredDistance) / distanceTolerance)

        // 90 % cow coverage, 10 % distance sanity
        let totalScore = 0.90 * coverageScore + 0.10 * distanceScore

        return (
            score: totalScore,
            validDepthSamples: cowStats.cowPixelCount,
            subjectDistance: cowStats.cowDepth
        )
    }

    // MARK: - Measurement utilities

    func depthPixelForNormalizedPoint(xNorm: Float, yNorm: Float) -> CGPoint? {
        guard let frame = capturedFrame else { return nil }

        let rgbWidth = Float(frame.imageResolution.width)
        let rgbHeight = Float(frame.imageResolution.height)
        let depthWidth = Float(frame.depthResolution.width)
        let depthHeight = Float(frame.depthResolution.height)

        guard rgbWidth > 0, rgbHeight > 0, depthWidth > 0, depthHeight > 0 else {
            return nil
        }

        let uRGB = xNorm * rgbWidth
        let vRGB = yNorm * rgbHeight

        let uDepth = uRGB * depthWidth / rgbWidth
        let vDepth = vRGB * depthHeight / rgbHeight

        return CGPoint(x: CGFloat(uDepth), y: CGFloat(vDepth))
    }

    func medianDepthAround(depthX: Int, depthY: Int, radius: Int = 2) -> Float? {
        guard let frame = capturedFrame else { return nil }

        let depthMap = frame.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard depthX >= 0, depthX < width, depthY >= 0, depthY < height else {
            return nil
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let ptr = base.assumingMemoryBound(to: Float32.self)

        var samples: [Float] = []

        for dy in -radius...radius {
            for dx in -radius...radius {
                let x = depthX + dx
                let y = depthY + dy
                guard x >= 0, x < width, y >= 0, y < height else { continue }

                let d = ptr[y * width + x]
                if d > 0.2 && d < 6.0 {
                    samples.append(d)
                }
            }
        }

        guard !samples.isEmpty else { return nil }
        return samples.sorted()[samples.count / 2]
    }

    func cameraPointForNormalizedPoint(xNorm: Float, yNorm: Float) -> SIMD3<Float>? {
        guard let frame = capturedFrame,
              let depthPoint = depthPixelForNormalizedPoint(xNorm: xNorm, yNorm: yNorm) else {
            return nil
        }

        let x = Int(depthPoint.x.rounded())
        let y = Int(depthPoint.y.rounded())

        guard let z = medianDepthAround(depthX: x, depthY: y) else { return nil }

        let fx = frame.intrinsics[0, 0]
        let fy = frame.intrinsics[1, 1]
        let cx = frame.intrinsics[2, 0]
        let cy = frame.intrinsics[2, 1]

        let X = (Float(x) - cx) * z / fx
        let Y = (Float(y) - cy) * z / fy

        return SIMD3<Float>(X, Y, z)
    }

    func distanceBetweenNormalizedPoints(_ a: CGPoint, _ b: CGPoint) -> Float? {
        guard let p1 = cameraPointForNormalizedPoint(
            xNorm: Float(a.x),
            yNorm: Float(a.y)
        ),
        let p2 = cameraPointForNormalizedPoint(
            xNorm: Float(b.x),
            yNorm: Float(b.y)
        ) else {
            return nil
        }

        return simd_distance(p1, p2)
    }
}
