//
//  ContentView.swift
//  wordchef-ios
//
//  Created by Jackson Walters on 10/31/25.
//

import SwiftUI

let apiKeyStorageKey = "wordchefApiKey"

struct EmbeddingsResponse: Codable {
    let input: InputData
}

struct InputData: Codable {
    let words: [String]
    let embeddings: [[Double]]
}

struct ContentView: View {
    @State private var query: String = ""
    @State private var responseText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var apiKeyInput: String = ""

    init() {
        // Try to get from UserDefaults first
        if let storedKey = UserDefaults.standard.string(forKey: apiKeyStorageKey), !storedKey.isEmpty {
            _apiKeyInput = State(initialValue: storedKey)
        } else if let plistKey = ContentView.loadApiKeyFromPlist() {
            _apiKeyInput = State(initialValue: plistKey)
        } else {
            _apiKeyInput = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter words...", text: $query)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("Search") {
                Task {
                    await fetchEmbeddings()
                }
            }
            .disabled(query.isEmpty || isLoading)

            TextField("Enter API Key", text: $apiKeyInput)
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("Save API Key") {
                saveApiKey(apiKeyInput)
            }

            if isLoading {
                ProgressView()
            }

            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }

            ScrollView {
                Text(responseText)
                    .padding()
            }

            Spacer()
        }
        .padding()
    }

    func saveApiKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: apiKeyStorageKey)
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

    func fetchEmbeddings() async {
        isLoading = true
        errorMessage = nil
        responseText = ""

        guard let url = URL(string: "https://wordchef.app/api/nearest.php?words=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKeyInput, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Server error"
                isLoading = false
                return
            }

            let decoder = JSONDecoder()
            let embeddingsResponse = try decoder.decode(EmbeddingsResponse.self, from: data)

            var resultString = "Words:\n"
            resultString += embeddingsResponse.input.words.joined(separator: ", ")
            resultString += "\n\nEmbeddings:\n"
            for vector in embeddingsResponse.input.embeddings {
                resultString += vector.map { String(format: "%.3f", $0) }.joined(separator: ", ")
                resultString += "\n"
            }

            responseText = resultString
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    ContentView()
}
