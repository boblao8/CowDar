import Foundation
internal import Combine
import UIKit

enum Breed: String, CaseIterable, Codable {
    case angus = "Angus"
    case hereford = "Hereford"
    case brahman = "Brahman"
    case droughtmaster = "Droughtmaster"
    case wagyu = "Wagyu"
    case charolais = "Charolais"
    case simmental = "Simmental"
    case other = "Other"
}

enum AnimalSex: String, CaseIterable, Codable {
    case cow = "Cow"
    case steer = "Steer"
    case bull = "Bull"
    case heifer = "Heifer"
    case calf = "Calf"
}

enum ScanLocation: String, CaseIterable, Codable {
    case crush = "Crush / Race"
    case field = "Field / Paddock"
    case saleyard = "Saleyard"
    case feedlot = "Feedlot"
}

/// Tracks the lifecycle of the server weight-estimate request for a session.
enum WeightEstimateState: String, Codable {
    case notRequested
    case waiting
    case received
    case failed
}

struct DepthCaptureMetadata: Codable {
    var timestamp: Date
    var imageWidth: Int
    var imageHeight: Int
    var depthWidth: Int
    var depthHeight: Int
    var intrinsics: [Float]
}

final class AnimalSession: ObservableObject, Codable, Identifiable {
    // Do NOT declare objectWillChange manually. A stored `var` shadows the
    // compiler-synthesised publisher, which causes @Published to fire on a
    // different instance than the one @ObservedObject subscribes to, so live
    // updates are silently dropped. Let the compiler wire everything together.

    var id: String
    var timestamp: Date
    var sessionNumber: Int

    // New pipeline files
    var rgbCaptureFilename: String?
    var depthCaptureFilename: String?
    var captureMetadataFilename: String?

    // Optional legacy field
    var plyFilename: String?

    var breed: Breed = .angus
    var sex: AnimalSex = .steer
    var location: ScanLocation = .saleyard
    var knownWeightKg: Double? = nil
    var notes: String = ""

    // Server weight-estimate response
    @Published var weightEstimateState: WeightEstimateState = .notRequested
    @Published var weightEstimateJSON:  String?              = nil

    init(sessionNumber: Int) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.sessionNumber = sessionNumber
    }

    var displayName: String {
        "Animal \(sessionNumber) — \(breed.rawValue) \(sex.rawValue)"
    }

    var hasWeight: Bool {
        knownWeightKg != nil
    }

    var hasDepthCapture: Bool {
        rgbCaptureFilename != nil &&
        depthCaptureFilename != nil &&
        captureMetadataFilename != nil
    }

    var hasLegacyScan: Bool {
        plyFilename != nil
    }

    var hasScan: Bool {
        hasDepthCapture || hasLegacyScan
    }

    var completionStatus: String {
        var parts: [String] = []

        if hasDepthCapture {
            parts.append("📡 RGB+Depth")
        } else if hasLegacyScan {
            parts.append("📡 Scan")
        }

        if let weight = knownWeightKg {
            parts.append("⚖️ \(Int(weight))kg")
        }

        return parts.isEmpty ? "Empty" : parts.joined(separator: "  ")
    }

    func save() {
        let dir = Self.sessionsDirectory()
        let url = dir.appendingPathComponent("\(id).json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save AnimalSession \(id): \(error)")
        }
    }

    static func sessionsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sessionFolder(for session: AnimalSession) -> URL {
        let dir = sessionsDirectory().appendingPathComponent(session.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadAll() -> [AnimalSession] {
        let dir = sessionsDirectory()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> AnimalSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(AnimalSession.self, from: data)
            }
            .map { session in
                session.refreshCaptureFilenamesFromDiskIfNeeded()
                return session
            }
            .sorted { $0.sessionNumber < $1.sessionNumber }
    }

    static func nextSessionNumber() -> Int {
        (loadAll().map { $0.sessionNumber }.max() ?? 0) + 1
    }

    func rgbCaptureURL() -> URL? {
        guard let filename = rgbCaptureFilename else { return nil }
        return Self.sessionFolder(for: self).appendingPathComponent(filename)
    }

    func depthCaptureURL() -> URL? {
        guard let filename = depthCaptureFilename else { return nil }
        return Self.sessionFolder(for: self).appendingPathComponent(filename)
    }

    func captureMetadataURL() -> URL? {
        guard let filename = captureMetadataFilename else { return nil }
        return Self.sessionFolder(for: self).appendingPathComponent(filename)
    }

    func plyURL() -> URL? {
        guard let filename = plyFilename else { return nil }
        return Self.sessionFolder(for: self).appendingPathComponent(filename)
    }

    /// Parses `weightEstimateJSON` and returns the `predictedWeight` value,
    /// or nil if the JSON hasn't arrived yet or doesn't contain that field.
    var parsedPredictedWeight: Double? {
        guard
            let json = weightEstimateJSON,
            let data = json.data(using: .utf8),
            let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("[AnimalSession] parsedPredictedWeight — JSON missing or unparseable")
            return nil
        }

        print("[AnimalSession] parsedPredictedWeight — keys: \(obj.keys.sorted())")
        print("[AnimalSession] parsedPredictedWeight — raw value: \(obj["predictedWeight"] ?? "nil"), type: \(type(of: obj["predictedWeight"] as Any))")

        // JSONSerialization always returns numbers as NSNumber regardless of
        // whether the JSON value has a decimal point.  Casting directly to
        // Double or Int can silently fail when the bridged type doesn't match
        // exactly.  Cast to NSNumber first, then use .doubleValue — this works
        // for any numeric JSON value (integer or floating-point).
        if let number = obj["predictedWeight"] as? NSNumber {
            let kg = number.doubleValue
            print("[AnimalSession] parsedPredictedWeight — parsed: \(kg) kg")
            return kg
        }

        print("[AnimalSession] parsedPredictedWeight — 'predictedWeight' key not found or wrong type")
        return nil
    }

    /// Copies all non-@Published (non-reactive) properties from `other` into
    /// this instance.  Called by SessionStore.reload() to keep a cached
    /// instance up-to-date with the latest disk representation without
    /// creating a new object (which would break @ObservedObject bindings).
    func mergeNonPublished(from other: AnimalSession) {
        // Wrap all assignments in a single objectWillChange.send() so that any
        // view observing this session redraws exactly once for the whole merge,
        // rather than zero times (plain vars don't auto-notify).
        objectWillChange.send()
        rgbCaptureFilename      = other.rgbCaptureFilename
        depthCaptureFilename    = other.depthCaptureFilename
        captureMetadataFilename = other.captureMetadataFilename
        plyFilename             = other.plyFilename
        breed                   = other.breed
        sex                     = other.sex
        location                = other.location
        knownWeightKg           = other.knownWeightKg
        notes                   = other.notes
        // Note: weightEstimateState / weightEstimateJSON are @Published and
        // are handled separately in SessionStore.reload() with rank comparison.
    }

    func refreshCaptureFilenamesFromDiskIfNeeded() {
        let folder = Self.sessionFolder(for: self)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        if rgbCaptureFilename == nil {
            rgbCaptureFilename = files.first(where: { $0.lastPathComponent.hasSuffix("_rgb.jpg") })?.lastPathComponent
        }

        if depthCaptureFilename == nil {
            depthCaptureFilename = files.first(where: { $0.lastPathComponent.hasSuffix("_depth.bin") })?.lastPathComponent
        }

        if captureMetadataFilename == nil {
            captureMetadataFilename = files.first(where: { $0.lastPathComponent.hasSuffix("_meta.json") })?.lastPathComponent
        }

        if plyFilename == nil {
            plyFilename = files.first(where: { $0.lastPathComponent.hasSuffix("_bestframe.ply") })?.lastPathComponent
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case sessionNumber
        case rgbCaptureFilename
        case depthCaptureFilename
        case captureMetadataFilename
        case plyFilename
        case breed
        case sex
        case location
        case knownWeightKg
        case notes
        case weightEstimateState
        case weightEstimateJSON
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        sessionNumber = try c.decode(Int.self, forKey: .sessionNumber)

        rgbCaptureFilename = try c.decodeIfPresent(String.self, forKey: .rgbCaptureFilename)
        depthCaptureFilename = try c.decodeIfPresent(String.self, forKey: .depthCaptureFilename)
        captureMetadataFilename = try c.decodeIfPresent(String.self, forKey: .captureMetadataFilename)

        plyFilename = try c.decodeIfPresent(String.self, forKey: .plyFilename)

        breed = try c.decode(Breed.self, forKey: .breed)
        sex = try c.decode(AnimalSex.self, forKey: .sex)
        location = try c.decode(ScanLocation.self, forKey: .location)
        knownWeightKg = try c.decodeIfPresent(Double.self, forKey: .knownWeightKg)
        notes = try c.decode(String.self, forKey: .notes)

        weightEstimateState = (try? c.decodeIfPresent(WeightEstimateState.self, forKey: .weightEstimateState)) ?? .notRequested
        weightEstimateJSON  = try? c.decodeIfPresent(String.self, forKey: .weightEstimateJSON)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(sessionNumber, forKey: .sessionNumber)

        try c.encodeIfPresent(rgbCaptureFilename, forKey: .rgbCaptureFilename)
        try c.encodeIfPresent(depthCaptureFilename, forKey: .depthCaptureFilename)
        try c.encodeIfPresent(captureMetadataFilename, forKey: .captureMetadataFilename)

        try c.encodeIfPresent(plyFilename, forKey: .plyFilename)

        try c.encode(breed, forKey: .breed)
        try c.encode(sex, forKey: .sex)
        try c.encode(location, forKey: .location)
        try c.encodeIfPresent(knownWeightKg, forKey: .knownWeightKg)
        try c.encode(notes, forKey: .notes)

        try c.encode(weightEstimateState, forKey: .weightEstimateState)
        try c.encodeIfPresent(weightEstimateJSON, forKey: .weightEstimateJSON)
    }
}
