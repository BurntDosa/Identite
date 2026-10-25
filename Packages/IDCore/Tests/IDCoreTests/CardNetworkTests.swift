import Testing
@testable import IDCore

struct CardNetworkTests {
    @Test func prefixes() {
        #expect(CardNetwork(cardNumber: "4111111111111111") == .visa)
        #expect(CardNetwork(cardNumber: "5500000000000004") == .mastercard)
        #expect(CardNetwork(cardNumber: "2221000000000009") == .mastercard)
        #expect(CardNetwork(cardNumber: "378282246310005") == .amex)
        #expect(CardNetwork(cardNumber: "6011000000000004") == .discover)
        #expect(CardNetwork(cardNumber: "6521000000000000") == .rupay)
        #expect(CardNetwork(cardNumber: "6070000000000000") == .rupay)
        #expect(CardNetwork(cardNumber: "36000000000000") == .diners)
        #expect(CardNetwork(cardNumber: "9999") == .other)
    }
    @Test func boundariesAndLongestMatch() {
        #expect(CardNetwork(cardNumber: "2220") == .other)
        #expect(CardNetwork(cardNumber: "2720") == .mastercard)
        #expect(CardNetwork(cardNumber: "2721") == .other)
        #expect(CardNetwork(cardNumber: "644") == .discover)
        #expect(CardNetwork(cardNumber: "649") == .discover)
        #expect(CardNetwork(cardNumber: "508") == .rupay)
        #expect(CardNetwork(cardNumber: "305") == .diners)
        #expect(CardNetwork(cardNumber: "306") == .other)
    }
}
