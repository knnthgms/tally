import XCTest
@testable import TallyEngine

final class EngineTests: XCTestCase {
    var engine: Engine!

    override func setUp() {
        engine = Engine(rates: CurrencyRates(rates: ["USD": 1, "EUR": 0.8, "GBP": 0.5, "CHF": 0.9, "BTC": 0.00001],
                                             updated: Date()))
        engine.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // Wednesday 2026-10-14 12:00 UTC
        engine.now = { Date(timeIntervalSince1970: 1_791_979_200) }
    }

    func r(_ s: String) -> String { engine.evaluate(expression: s).display ?? "ERR: \(engine.evaluate(expression: s).error ?? "-")" }

    func doc(_ s: String) -> [String] { engine.evaluate(s).map { $0.display ?? "" } }

    func testArithmetic() {
        XCTAssertEqual(r("2 + 3 * 4"), "14")
        XCTAssertEqual(r("(2 + 3) * 4"), "20")
        XCTAssertEqual(r("2^10"), "1,024")
        XCTAssertEqual(r("-2^2"), "-4")
        XCTAssertEqual(r("10 plus 5 minus 3"), "12")
        XCTAssertEqual(r("6 times 7"), "42")
        XCTAssertEqual(r("8 multiplied by 2"), "16")
        XCTAssertEqual(r("9 divided by 3"), "3")
        XCTAssertEqual(r("10 mod 3"), "1")
        XCTAssertEqual(r("1/3"), "0.33")
        XCTAssertEqual(r("5!"), "120")
        XCTAssertEqual(r("1,000,000 / 4"), "250,000")
        XCTAssertEqual(r("2 pi"), "6.28")
        XCTAssertEqual(r("5k + 2"), "5,002")
        XCTAssertEqual(r("3 million"), "3,000,000")
        XCTAssertEqual(r("8 / (45 - 20%)"), "0.22")
    }

    func testBitwiseAndBases() {
        XCTAssertEqual(r("0xFF"), "255")
        XCTAssertEqual(r("255 in hex"), "0xFF")
        XCTAssertEqual(r("10 in bin"), "0b1010")
        XCTAssertEqual(r("8 in oct"), "0o10")
        XCTAssertEqual(r("5 & 3"), "1")
        XCTAssertEqual(r("5 | 3"), "7")
        XCTAssertEqual(r("5 xor 3"), "6")
        XCTAssertEqual(r("1 << 4"), "16")
        XCTAssertEqual(r("12345 in sci"), "1.23e4")
    }

    func testPercentages() {
        XCTAssertEqual(r("20% of 10"), "2")
        XCTAssertEqual(r("5% on 30"), "31.5")
        XCTAssertEqual(r("6% off 40"), "37.6")
        XCTAssertEqual(r("50 as a % of 100"), "50%")
        XCTAssertEqual(r("70 as a % on 20"), "250%")
        XCTAssertEqual(r("20 as a % off 80"), "75%")
        XCTAssertEqual(r("5% of what is 6"), "120")
        XCTAssertEqual(r("5% on what is 6.3"), "6")
        XCTAssertEqual(r("20% off what is 8"), "10")
        XCTAssertEqual(r("$10 + 20%"), "$12")
        XCTAssertEqual(r("20% of what is 30 cm"), "150 cm")
        XCTAssertEqual(r("0.35 as %"), "35%")
    }

    func testUnits() {
        XCTAssertEqual(r("5 inches in cm"), "12.7 cm")
        XCTAssertEqual(r("1 mile in km"), "1.61 km")
        XCTAssertEqual(r("20 ml in tea spoons"), "4.06 tsp")
        XCTAssertEqual(r("5 feet 3 inches in cm"), "160.02 cm")
        XCTAssertEqual(r("1 hour 30 min in minutes"), "90 minutes")
        XCTAssertEqual(r("100 °C in fahrenheit"), "212 °F")
        XCTAssertEqual(r("32 F to C"), "0 °C")
        XCTAssertEqual(r("1 GB in MB"), "1,000 MB")
        XCTAssertEqual(r("1 GiB in MiB"), "1,024 MiB")
        XCTAssertEqual(r("60 km/h in mph"), "37.28 mph")
        XCTAssertEqual(r("10 km / 2 h"), "5 km/h")
        XCTAssertEqual(r("2 m * 3 m"), "6 m²")
        XCTAssertEqual(r("1 acre in sq m"), "4,046.86 m²")
        XCTAssertEqual(r("1 m3 in liters"), "1,000 L")
        XCTAssertEqual(r("10 km / 5 km"), "2")
        XCTAssertEqual(r("180 degrees in rad"), "3.14 rad")
        XCTAssertEqual(r("12 px in em"), "0.75 em")
        XCTAssertEqual(r("inch in cm"), "2.54 cm")
        XCTAssertEqual(r("5 in"), "5 in")
        XCTAssertEqual(r("3 kg + 500 g"), "3.5 kg")
        XCTAssertEqual(r("sqrt(16 m²)"), "4 m")
        XCTAssertEqual(r("1 lb in kg"), "0.45 kg")
    }

    func testCurrency() {
        XCTAssertEqual(r("$10 in EUR"), "€8")
        XCTAssertEqual(r("4 GBP in Euro"), "€6.40")
        XCTAssertEqual(r("10 euros in dollars"), "$12.50")
        XCTAssertEqual(r("$6 times 5"), "$30")
        XCTAssertEqual(r("$10 + €8"), "$20")
        XCTAssertEqual(r("1 BTC in USD"), "$100,000")
        XCTAssertEqual(r("9 CHF"), "9 CHF")
    }

    func testFunctions() {
        XCTAssertEqual(r("sqrt 16"), "4")
        XCTAssertEqual(r("sqrt(16) + 1"), "5")
        XCTAssertEqual(r("cbrt(27)"), "3")
        XCTAssertEqual(r("root 3 (27)"), "3")
        XCTAssertEqual(r("abs(-5)"), "5")
        XCTAssertEqual(r("round(3.6)"), "4")
        XCTAssertEqual(r("round(3.14159; 3)"), "3.14")
        XCTAssertEqual(r("log(1000)"), "3")
        XCTAssertEqual(r("log 2 (8)"), "3")
        XCTAssertEqual(r("ln(e)"), "1")
        XCTAssertEqual(r("sin(30°)"), "0.5")
        XCTAssertEqual(r("cos(pi)"), "-1")
        XCTAssertEqual(r("fact(5)"), "120")
    }

    func testDocumentFeatures() {
        let lines = doc("""
        # Groceries
        Milk: $3
        Bread: $2.50 // tasty
        sum
        prev * 2

        v = 20
        v * 2
        avg
        total in EUR
        """)
        XCTAssertEqual(lines[0], "")
        XCTAssertEqual(lines[1], "$3")
        XCTAssertEqual(lines[2], "$2.50")
        XCTAssertEqual(lines[3], "$5.50")
        XCTAssertEqual(lines[4], "$11")
        XCTAssertEqual(lines[6], "20")
        XCTAssertEqual(lines[7], "40")
        XCTAssertEqual(lines[8], "30")
        XCTAssertEqual(lines[9], "€90")
    }

    func testDemoSample() {
        let lines = doc("""
        Price: $6 times 5
        Fee: 8 CHF in Euro
        Sum in USD - 9%
        """)
        XCTAssertEqual(lines[0], "$30")
        XCTAssertEqual(lines[1], "€7.11")
        // (30 + 7.11/0.8) * 0.91
        XCTAssertEqual(lines[2], "$35.39")
    }

    func testTextIsIgnored() {
        XCTAssertEqual(r("I paid $10 for lunch"), "$10")
        XCTAssertEqual(engine.evaluate(expression: "Just a note").kind, .text)
    }

    func testDates() {
        XCTAssertEqual(r("today"), r("Wednesday, October 14"))
        XCTAssertEqual(r("today + 3 days"), r("Saturday 17 October"))
        XCTAssertEqual(r("next friday"), r("Oct 16"))
        XCTAssertEqual(r("next friday + 2 weeks"), r("Oct 30"))
        XCTAssertEqual(r("2026-12-25 - today"), "72 days")
        XCTAssertEqual(r("fromunix(0) in UTC").contains("1970"), true)
        XCTAssertEqual(r("Oct 14 in unix"), "1,791,928,800")
        let t = r("2:30 pm HKT in Berlin")
        XCTAssertTrue(t.contains("8:30") || t.contains("08:30"), t)
        XCTAssertFalse(r("PST time").hasPrefix("ERR"))
        XCTAssertFalse(r("time in New York").hasPrefix("ERR"))
        XCTAssertFalse(r("3 days ago").hasPrefix("ERR"))
    }

    func testCSSVariables() {
        let lines = doc("""
        em = 20px
        2 em in px
        ppi = 300
        1 inch in px
        """)
        XCTAssertEqual(lines[1], "40 px")
        XCTAssertEqual(lines[3], "300 px")
    }

    func testMultiWordVariables() {
        let lines = doc("""
        Savings goal = $10k
        Savings goal / 12
        monthly rent = $1,450
        monthly rent * 12
        """)
        XCTAssertEqual(lines[0], "$10,000")
        XCTAssertEqual(lines[1], "$833.33")
        XCTAssertEqual(lines[3], "$17,400")
    }
}

final class SettingsTests: XCTestCase {
    func testDegreesModeAndNumberOnly() {
        let e = Engine(rates: .fallback)
        e.anglesInDegrees = true
        XCTAssertEqual(e.evaluate(expression: "sin(30)").display, "0.5")
        XCTAssertEqual(e.evaluate(expression: "asin(1)").display, "90")
        let v = e.evaluate(expression: "$1,234.5").value!
        XCTAssertEqual(e.formatter.numberOnly(v), "1234.5")
        XCTAssertEqual(e.formatter.format(v), "$1,234.50")
    }
}

final class PasteTests: XCTestCase {
    let numiCopy = """
    # credit cards
    coral = 3542.87inr = INR 3,542.87
    regalia = 81026inr = INR 81,026

    debt = coral + regalia = INR 84,568.87

    # bank balance
    fi = 58034 inr = INR 58,034

    iminbal = 10000inr = INR 10,000
    icici = 72565.21 inr - iminbal = INR 62,565.21

    balance = fi + icici = INR 1,20,599.21

    # Bills
    rent = 49500inr = INR 49,500
    esops = 45000inr = INR 45,000
    emi = 58000inr = INR 58,000
    sips = 45000inr = INR 45,000
    help = 5800inr = INR 5,800

    bills = rent + esops + emi + sips + help = INR 2,03,300

    sal = 214000inr = INR 2,14,000

    settle = balance - debt - bills + sal = INR 46,730.34

    targetfi = 50000inr = INR 50,000
    targeticici = 45000inr - iminbal = INR 35,000

    targetBal = targetfi + targeticici = INR 85,000

    targetBal - settle = INR 38,269.66
    """

    func testStripsNumiResultsButKeepsAssignments() {
        let e = Engine(rates: .fallback)
        let clean = e.stripPastedResults(numiCopy)
        let lines = clean.components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "coral = 3542.87inr")
        XCTAssertEqual(lines[4], "debt = coral + regalia")
        XCTAssertEqual(lines[10], "icici = 72565.21 inr - iminbal")
        XCTAssertEqual(lines.last, "targetBal - settle")
        XCTAssertFalse(clean.contains("INR"))
        // The cleaned document still calculates to Numi's answer.
        e.formatter.settings.indianGrouping = true
        XCTAssertEqual(e.evaluate(clean).last?.display, "₹38,269.66")
        XCTAssertEqual(e.evaluate(clean)[12].display, "₹1,20,599.21")
    }

    func testLeavesPlainAssignmentsAndMismatchesAlone() {
        let e = Engine(rates: .fallback)
        XCTAssertEqual(e.stripPastedResults("rent = 49500"), "rent = 49500")
        XCTAssertEqual(e.stripPastedResults("a = 5\na = 7"), "a = 5\na = 7")
        XCTAssertEqual(e.stripPastedResults("2 + 2 = 5"), "2 + 2 = 5")
        XCTAssertEqual(e.stripPastedResults("2 + 2 = 4"), "2 + 2")
        XCTAssertEqual(e.stripPastedResults("255 in hex = 0xFF"), "255 in hex")
        XCTAssertEqual(e.stripPastedResults("x - 3 = -$1", context: "x = $2"), "x - 3")
    }
}

extension EngineTests {
    // Quirk: "Total:" looked like it collided with the total/sum keyword; really Food was 225 d·EUR.
    func testTotalLabelOverTripCosts() {
        let lines = doc("Flights = 2 × €189\nHotel = 3 × €80\nFood = 5 days × €45\nTotal: Flights + Hotel + Food")
        XCTAssertEqual(lines[3], "€843")
        XCTAssertEqual(doc("Total: 5 + 5")[0], "10")
    }

    func testLabelsDefineVariables() {
        let lines = doc("Flights: 2 × €189\nHotel: 3 × €80\nFood: 5 days × €45\nTrip: Flights + Hotel + Food\nTrip / 2")
        XCTAssertEqual(lines[3], "€843")
        XCTAssertEqual(lines[4], "€421.50")
        XCTAssertEqual(doc("Coffee per week: 5 × $4\nCoffee per week × 52")[1], "$1,040")
        XCTAssertEqual(doc("Rent : $1,000\nRent × 12")[1], "$12,000")
    }

    func testLabelsDontShadowBuiltIns() {
        // "Total:" stays a label, so a later "total" still sums the block.
        XCTAssertEqual(doc("3\n4\nTotal: 100\ntotal")[3], "107")
        XCTAssertEqual(doc("Hours: 3\n2 hours in min")[1], "120 minutes")
        // Labels that aren't name-shaped stay display-only.
        XCTAssertEqual(doc("Day 1 (Mon): 5\nDay 1 + 1")[1], "")
        // An explicit assignment can still shadow on purpose.
        XCTAssertEqual(doc("total = 7\ntotal × 2")[1], "14")
    }

    func testMoneyTimesCountUnitIsMoney() {
        XCTAssertEqual(r("5 days × €45"), "€225")
        XCTAssertEqual(r("€45 × 5 days"), "€225")
        XCTAssertEqual(r("3 m × €2"), "€6")
        XCTAssertEqual(r("5 days × €45 + €10"), "€235")
        XCTAssertEqual(r("5 days × €45 in USD"), "$281.25")
        // Rates still cancel or stay rates.
        XCTAssertEqual(r("5 days × €45 / day"), "€225")
        XCTAssertEqual(r("5 h × $20/h"), "$100")
        XCTAssertEqual(r("€90 / 2 days"), "45 EUR/d")
        XCTAssertEqual(r("5 days × 3"), "15 days")
    }
}
