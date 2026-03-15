import Foundation
import SwiftUI

// CapturedPayload is unique to the camera flow and is NOT defined in ContentView.swift.
// Make it Identifiable so it can be used with .navigationDestination(item:) and fullScreenCover(item:).
struct CapturedPayload: Identifiable {
    let id = UUID()
    let depthData: Data
    let depthWidth: Int
    let depthHeight: Int
    let photoData: Data
    let intrinsicsString: String
    let referenceWidth: Float
    let referenceHeight: Float
}

// NOTE: PredictionResponse, AppError, and ResultRow are defined in ContentView.swift
// and are visible across the entire module. Do NOT redeclare them here.
