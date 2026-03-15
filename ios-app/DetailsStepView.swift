import SwiftUI

struct DetailsStepView: View {
    @ObservedObject var session: AnimalSession
    let onNext: () -> Void

    @State private var weightText: String = ""
    @State private var selectedBreed: Breed = .angus
    @State private var selectedSex: AnimalSex = .steer
    @State private var selectedLocation: ScanLocation = .saleyard
    @State private var notes: String = ""
    @FocusState private var weightFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Animal Details")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Tap to select — known weight is most important")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 14) {
                    knownWeightCard

                    sectionCard(title: "Breed") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Breed.allCases, id: \.self) { breed in
                                Button(action: { selectedBreed = breed }) {
                                    Text(breed.rawValue)
                                        .font(.subheadline.bold())
                                        .foregroundColor(selectedBreed == breed ? .black : .gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(selectedBreed == breed ? Color.cyan : Color.white.opacity(0.08))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionCard(title: "Sex") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(AnimalSex.allCases, id: \.self) { sex in
                                Button(action: { selectedSex = sex }) {
                                    Text(sex.rawValue)
                                        .font(.subheadline.bold())
                                        .foregroundColor(selectedSex == sex ? .black : .gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(selectedSex == sex ? Color.cyan : Color.white.opacity(0.08))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionCard(title: "Scan Location") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(ScanLocation.allCases, id: \.self) { loc in
                                Button(action: { selectedLocation = loc }) {
                                    Text(locationLabel(loc))
                                        .font(.subheadline.bold())
                                        .foregroundColor(selectedLocation == loc ? .black : .gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(selectedLocation == loc ? Color.cyan : Color.white.opacity(0.08))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionCard(title: "Notes  (optional)") {
                        TextField("Age, body condition, ear tag, anything useful...",
                                  text: $notes, axis: .vertical)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(3...5)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Button(action: saveAndNext) {
                Label("Calculate Weight", systemImage: "scalemass.fill")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.cyan)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .onAppear {
            if let w = session.knownWeightKg {
                weightText = String(format: "%.0f", w)
            }
            selectedBreed    = session.breed
            selectedSex      = session.sex
            selectedLocation = session.location
            notes            = session.notes
        }
    }

    private func locationLabel(_ loc: ScanLocation) -> String {
        switch loc {
        case .crush: return "Crush"
        case .field: return "Field"
        case .saleyard: return "Saleyard"
        case .feedlot: return "Feedlot"
        }
    }

    private func saveAndNext() {
        if let w = Double(weightText.replacingOccurrences(of: ",", with: ".")) {
            session.knownWeightKg = w
        }
        session.breed    = selectedBreed
        session.sex      = selectedSex
        session.location = selectedLocation
        session.notes    = notes
        session.save()
        // Fire-and-forget: continues running even after the view is dismissed
        NetworkService.shared.submitScanForWeightEstimate(session)
        onNext()
    }

    private var knownWeightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Known Weight", systemImage: "scalemass.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                Spacer()
                Text("MOST IMPORTANT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: $weightText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(weightText.isEmpty ? .gray.opacity(0.3) : .orange)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text("kg")
                    .font(.title2.bold())
                    .foregroundColor(.orange.opacity(0.6))
                    .padding(.trailing, 8)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(weightText.isEmpty ? Color.orange.opacity(0.2) : Color.orange.opacity(0.5)))
            .onTapGesture { weightFocused = true }
            Text("Enter the weight from the saleyard scale or crush weigh system")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(14)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2)))
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.white)
            content()
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }
}
