import Foundation

/// Exchange rates expressed as units of each currency per 1 USD.
public struct CurrencyRates: Codable, Sendable, Equatable {
    public var rates: [String: Double]
    public var updated: Date

    public init(rates: [String: Double], updated: Date) {
        self.rates = rates; self.updated = updated
    }

    public func rate(_ code: String) -> Double? { code == "USD" ? 1 : rates[code] }

    /// Approximate rates used until (or if) live rates can be fetched.
    public static let fallback = CurrencyRates(rates: [
        "USD": 1, "EUR": 0.86, "GBP": 0.75, "JPY": 150, "INR": 88, "CHF": 0.80, "CAD": 1.39, "AUD": 1.53,
        "NZD": 1.72, "CNY": 7.12, "HKD": 7.78, "SGD": 1.29, "SEK": 9.4, "NOK": 10.0, "DKK": 6.4, "PLN": 3.65,
        "CZK": 20.9, "HUF": 335, "RUB": 81, "TRY": 41.8, "UAH": 41.5, "ILS": 3.3, "AED": 3.6725, "SAR": 3.75,
        "QAR": 3.64, "KWD": 0.306, "BRL": 5.4, "MXN": 18.4, "ARS": 1400, "CLP": 950, "COP": 3900, "ZAR": 17.4,
        "EGP": 48.5, "NGN": 1480, "KES": 129, "KRW": 1420, "TWD": 30.5, "THB": 32.5, "IDR": 16500, "MYR": 4.22,
        "PHP": 58, "VND": 26300, "PKR": 282, "BDT": 122, "LKR": 302, "NPR": 140, "RON": 4.37, "BGN": 1.68,
        "ISK": 122, "MAD": 9.1, "BTC": 0.0000093, "ETH": 0.00025,
    ], updated: Date(timeIntervalSince1970: 1_760_000_000))
}

/// Names and symbols people use for currencies.
enum CurrencyNames {
    static let symbols: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₽": "RUB", "₩": "KRW",
        "₺": "TRY", "₴": "UAH", "₪": "ILS", "₿": "BTC", "₫": "VND", "₱": "PHP", "฿": "THB", "₦": "NGN",
    ]
    /// Display prefix for result formatting.
    static let prefix: [String: String] = [
        "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "INR": "₹", "KRW": "₩", "RUB": "₽", "TRY": "₺",
        "UAH": "₴", "ILS": "₪",
    ]
    static let crypto: Set<String> = ["BTC", "ETH", "LTC", "SOL", "DOGE", "XRP", "ADA", "DOT", "USDT", "USDC", "BNB", "XMR"]

    static let words: [String: [String]] = [
        "USD": ["dollar", "dollars", "us dollar", "us dollars", "buck", "bucks", "usd"],
        "EUR": ["euro", "euros", "eur"],
        "GBP": ["british pound", "british pounds", "pound sterling", "pounds sterling", "sterling", "quid", "gbp"],
        "JPY": ["yen", "jpy"],
        "INR": ["rupee", "rupees", "indian rupee", "indian rupees", "inr"],
        "CHF": ["franc", "francs", "swiss franc", "swiss francs", "chf"],
        "CAD": ["canadian dollar", "canadian dollars", "cad"],
        "AUD": ["australian dollar", "australian dollars", "aud"],
        "NZD": ["new zealand dollar", "new zealand dollars", "nzd"],
        "CNY": ["yuan", "renminbi", "rmb", "cny"],
        "HKD": ["hong kong dollar", "hong kong dollars", "hkd"],
        "SGD": ["singapore dollar", "singapore dollars", "sgd"],
        "SEK": ["swedish krona", "swedish kronor", "sek"],
        "NOK": ["norwegian krone", "norwegian kroner", "nok"],
        "DKK": ["danish krone", "danish kroner", "dkk"],
        "PLN": ["zloty", "zlotys", "zł", "pln"],
        "CZK": ["koruna", "czech koruna", "czk"],
        "HUF": ["forint", "forints", "huf"],
        "RUB": ["ruble", "rubles", "rouble", "roubles", "rub"],
        "TRY": ["lira", "turkish lira"],
        "UAH": ["hryvnia", "hryvnias", "uah"],
        "ILS": ["shekel", "shekels", "ils"],
        "AED": ["dirham", "dirhams", "aed"],
        "SAR": ["riyal", "riyals", "sar"],
        "BRL": ["real", "reais", "brazilian real", "brl"],
        "MXN": ["mexican peso", "mexican pesos", "mxn"],
        "ZAR": ["rand", "rands", "zar"],
        "KRW": ["won", "krw"],
        "THB": ["baht", "thb"],
        "IDR": ["rupiah", "idr"],
        "MYR": ["ringgit", "myr"],
        "PHP": ["philippine peso", "philippine pesos"],
        "VND": ["dong", "vnd"],
        "PKR": ["pakistani rupee", "pakistani rupees", "pkr"],
        "BTC": ["bitcoin", "bitcoins", "btc"],
        "ETH": ["ether", "ethereum", "eth"],
        "LTC": ["litecoin", "litecoins", "ltc"],
        "SOL": ["solana"],
        "DOGE": ["dogecoin", "doge"],
    ]
}
