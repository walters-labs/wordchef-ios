//
//  ContentView.swift
//  wordchef-ios
//
//  Created by Jackson Walters on 10/31/25.
//

import SwiftUI

let apiKeyStorageKey = "wordchefApiKey"

struct NearestResponse: Codable {
    struct InputData: Codable {
        let words: [String]
        let embeddings: [[Double]]
        let average_embedding: [Double]
    }
    struct Neighbor: Codable {
        let word: String
        let distance: Double
        let embedding: [Double]
    }

    let input: InputData
    let nearest: [Neighbor]
}

struct ContentView: View {
    @State private var query: String = ""
    @State private var neighborLimit: String = "5"
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Store images keyed by word
    @State private var neighborImages: [String: Image] = [:]
    
    // Load API key once, no UI input needed
    private let apiKey: String = ContentView.loadApiKeyFromPlist() ?? ""

    var body: some View {
        VStack(spacing: 16) {
            TextField("Enter word(s)...", text: $query)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            TextField("Number of neighbors (default 5)", text: $neighborLimit)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Button("Get Nearest Images") {
                Task {
                    await fetchNearestAndImages()
                }
            }
            .disabled(query.isEmpty || isLoading)
            .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .padding()
            }

            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 20) {
                    ForEach(neighborImages.sorted(by: { $0.key < $1.key }), id: \.key) { word, image in
                        VStack {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 120, maxHeight: 120)
                                .border(Color.gray)
                            Text(word)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .padding()
            }

            Spacer()
        }
        .padding(.top)
    }

    static func loadApiKeyFromPlist() -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let apiKey = dict["API_KEY"] as? String else {
            return nil
        }
        return apiKey
    }

    func fetchNearestAndImages() async {
        isLoading = true
        errorMessage = nil
        neighborImages = [:]

        guard let encodedWords = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            errorMessage = "Invalid words input"
            isLoading = false
            return
        }

        let limit = Int(neighborLimit) ?? 5
        let cappedLimit = max(1, min(limit, 20))

        guard let nearestUrl = URL(string: "https://wordchef.app/api/nearest.php?words=\(encodedWords)&limit=\(cappedLimit)") else {
            errorMessage = "Invalid nearest URL"
            isLoading = false
            return
        }

        var nearestRequest = URLRequest(url: nearestUrl)
        nearestRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (nearestData, nearestResponse) = try await URLSession.shared.data(for: nearestRequest)

            guard let httpResponse = nearestResponse as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Nearest API server error"
                isLoading = false
                return
            }

            let decoder = JSONDecoder()
            let nearestResponseObj = try decoder.decode(NearestResponse.self, from: nearestData)

            let words = nearestResponseObj.nearest.map { $0.word }

            if words.isEmpty {
                errorMessage = "No nearest words found"
                isLoading = false
                return
            }

            try await fetchBulkImages(for: words)

        } catch {
            errorMessage = "Failed to fetch nearest: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func fetchBulkImages(for words: [String]) async throws {
        guard let url = URL(string: "https://wordchef.app/api/bulk_image.php?api_key=\(apiKey)") else {
            errorMessage = "Invalid bulk image URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONEncoder().encode(words)
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            errorMessage = "Bulk image API server error"
            isLoading = false
            return
        }

        let decoder = JSONDecoder()
        let imagesDict = try decoder.decode([String: String].self, from: data)

        var loadedImages: [String: Image] = [:]

        for (word, base64String) in imagesDict {
            if let imageData = Data(base64Encoded: base64String),
               let uiImage = UIImage(data: imageData) {
                loadedImages[word] = Image(uiImage: uiImage)
            } else {
                print("Failed to decode image for word: \(word)")
            }
        }

        DispatchQueue.main.async {
            self.neighborImages = loadedImages
            self.isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
