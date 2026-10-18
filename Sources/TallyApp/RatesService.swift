import Foundation
import TallyEngine

/// Fetches exchange rates from free, keyless public endpoints and caches them on disk.
/// open.er-api.com covers fiat currencies; Coinbase's public rates cover crypto.
enum RatesService {
    static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tally", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rates.json")
    }

    static func cached() -> CurrencyRates? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CurrencyRates.self, from: data)
    }

    static func fetch() async throws -> CurrencyRates {
        struct Fiat: Decodable { let result: String; let rates: [String: Double] }
        struct Coinbase: Decodable { struct D: Decodable { let rates: [String: String] }; let data: D }

        let (fiatData, _) = try await URLSession.shared.data(from: URL(string: "https://open.er-api.com/v6/latest/USD")!)
        let fiat = try JSONDecoder().decode(Fiat.self, from: fiatData)
        guard fiat.result == "success" else { throw URLError(.badServerResponse) }
        var rates = fiat.rates

        if let (cbData, _) = try? await URLSession.shared.data(from: URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=USD")!),
           let cb = try? JSONDecoder().decode(Coinbase.self, from: cbData) {
            for code in ["BTC", "ETH", "LTC", "SOL", "DOGE", "XRP", "ADA", "DOT", "USDT", "USDC", "BNB", "XMR"] {
                if let s = cb.data.rates[code], let v = Double(s), rates[code] == nil { rates[code] = v }
            }
        }
        let result = CurrencyRates(rates: rates, updated: Date())
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: cacheURL, options: .atomic) }
        return result
    }
}
