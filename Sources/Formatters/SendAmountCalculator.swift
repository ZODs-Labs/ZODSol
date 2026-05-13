import Foundation
import SolanaKit

public struct SendAmountCalculator: Sendable {
    public init() {}

    public func compute(_ intent: SendAmountIntent, input: SendAmountInput) -> SendAmountResult {
        switch intent {
        case let .percentage(rawPercent):
            self.computePercentage(rawPercent, input: input)
        case let .manual(text, mode):
            self.computeManual(text: text, mode: mode, input: input)
        }
    }

    public func maxSpendable(input: SendAmountInput) -> UInt64 {
        guard input.isNativeSOL else { return input.balanceBaseUnits }
        let fee = input.feeReserveLamports.rawValue
        let rent = input.rentReserveLamports.rawValue
        let reserve = fee.addingReportingOverflow(rent)
        if reserve.overflow { return 0 }
        if input.balanceBaseUnits <= reserve.partialValue { return 0 }
        return input.balanceBaseUnits - reserve.partialValue
    }

    public func parse(text: String, decimals: UInt8) -> (baseUnits: UInt64, decimalsError: Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("e") || trimmed.contains("E") { return nil }
        if trimmed.hasPrefix(".") { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 { return nil }

        let wholePart = String(parts[0])
        let fractionPart = parts.count == 2 ? String(parts[1]) : ""

        guard !wholePart.isEmpty, wholePart.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if !fractionPart.isEmpty {
            guard fractionPart.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        }

        if fractionPart.count > Int(decimals) {
            return (0, true)
        }

        let paddingCount = Int(decimals) - fractionPart.count
        let padded = fractionPart + String(repeating: "0", count: paddingCount)
        let combined = wholePart + padded
        let normalized = combined.drop(while: { $0 == "0" })
        let digits = normalized.isEmpty ? "0" : String(normalized)

        guard let value = UInt64(digits) else { return nil }
        return (value, false)
    }
}

extension SendAmountCalculator {
    private func computePercentage(_ rawPercent: Double, input: SendAmountInput) -> SendAmountResult {
        let clamped = max(0.0, min(1.0, rawPercent))
        let spendable = self.maxSpendable(input: input)
        let scaled = Double(spendable) * clamped
        let baseUnits: UInt64 = if scaled <= 0 {
            0
        } else if scaled >= Double(UInt64.max) {
            UInt64.max
        } else {
            UInt64(scaled.rounded(.down))
        }
        return self.makeResult(
            baseUnits: baseUnits,
            input: input,
            roundedToZero: false,
            decimalsError: false)
    }

    private func computeManual(text: String, mode: FiatMode, input: SendAmountInput) -> SendAmountResult {
        switch mode {
        case .token:
            return self.computeManualToken(text: text, input: input)
        case .fiat:
            guard let price = input.priceUSD else {
                return self.computeManualToken(text: text, input: input)
            }
            return self.computeManualFiat(text: text, priceUSD: price, input: input)
        }
    }

    private func computeManualToken(text: String, input: SendAmountInput) -> SendAmountResult {
        guard let parsed = self.parse(text: text, decimals: input.decimals) else {
            return self.makeResult(
                baseUnits: 0,
                input: input,
                roundedToZero: false,
                decimalsError: false)
        }
        if parsed.decimalsError {
            return self.makeResult(
                baseUnits: 0,
                input: input,
                roundedToZero: false,
                decimalsError: true)
        }
        return self.makeResult(
            baseUnits: parsed.baseUnits,
            input: input,
            roundedToZero: false,
            decimalsError: false)
    }

    private func computeManualFiat(text: String, priceUSD: Decimal, input: SendAmountInput) -> SendAmountResult {
        guard let parsedDecimal = Self.parseFiatDecimal(text) else {
            return self.makeResult(
                baseUnits: 0,
                input: input,
                roundedToZero: false,
                decimalsError: false)
        }
        if parsedDecimal == 0 {
            return self.makeResult(
                baseUnits: 0,
                input: input,
                roundedToZero: false,
                decimalsError: false)
        }
        if priceUSD <= 0 {
            return self.makeResult(
                baseUnits: 0,
                input: input,
                roundedToZero: true,
                decimalsError: false)
        }
        let scale = Self.power10(Int(input.decimals))
        let raw = parsedDecimal / priceUSD * scale
        let floored = Self.floor(raw)
        let baseUnits = Self.decimalToUInt64Clamped(floored)
        let roundedToZero = baseUnits == 0 && parsedDecimal > 0
        return self.makeResult(
            baseUnits: baseUnits,
            input: input,
            roundedToZero: roundedToZero,
            decimalsError: false)
    }

    private func makeResult(
        baseUnits: UInt64,
        input: SendAmountInput,
        roundedToZero: Bool,
        decimalsError: Bool) -> SendAmountResult
    {
        let tokenAmount = TokenAmount(amount: baseUnits, decimals: input.decimals)
        let tokenString = TokenAmountFormatter().string(tokenAmount, symbol: nil)
        let displayToken = tokenString.hasSuffix(" ")
            ? String(tokenString.dropLast())
            : tokenString
        let displayFiat: String?
        if let price = input.priceUSD {
            let decimalAmount = Decimal(baseUnits) / Self.power10(Int(input.decimals))
            let fiat = decimalAmount * price
            displayFiat = CurrencyFormatter().string(usd: fiat)
        } else {
            displayFiat = nil
        }
        return SendAmountResult(
            baseUnits: baseUnits,
            displayToken: displayToken,
            inputTokenText: Self.inputTokenText(baseUnits: baseUnits, decimals: input.decimals),
            displayFiat: displayFiat,
            exceedsBalance: baseUnits > input.balanceBaseUnits,
            isZero: baseUnits == 0,
            roundedToZero: roundedToZero,
            decimalsError: decimalsError)
    }

    fileprivate static func parseFiatDecimal(_ text: String) -> Decimal? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$") {
            trimmed = String(trimmed.dropFirst())
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("e") || trimmed.contains("E") { return nil }
        if trimmed.hasPrefix(".") { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 { return nil }

        let wholePart = String(parts[0])
        let fractionPart = parts.count == 2 ? String(parts[1]) : ""
        guard !wholePart.isEmpty, wholePart.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if !fractionPart.isEmpty {
            guard fractionPart.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        }
        let normalized = fractionPart.isEmpty ? wholePart : "\(wholePart).\(fractionPart)"
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    fileprivate static func inputTokenText(baseUnits: UInt64, decimals: UInt8) -> String {
        let decimals = Int(decimals)
        guard decimals > 0 else { return "\(baseUnits)" }
        var scale: UInt64 = 1
        for _ in 0..<decimals {
            let next = scale.multipliedReportingOverflow(by: 10)
            if next.overflow { return "\(baseUnits)" }
            scale = next.partialValue
        }
        let whole = baseUnits / scale
        let fraction = baseUnits % scale
        guard fraction > 0 else { return "\(whole)" }
        let padded = String(fraction).padding(toLength: decimals, withPad: "0", startingAt: 0)
        let trimmed = padded.reversed().drop(while: { $0 == "0" }).reversed()
        return "\(whole).\(String(trimmed))"
    }

    fileprivate static func power10(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        var base = Decimal(10)
        var remaining = exponent
        while remaining > 0 {
            if remaining & 1 == 1 { result *= base }
            remaining >>= 1
            if remaining > 0 { base *= base }
        }
        return result
    }

    fileprivate static func floor(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, .down)
        return output
    }

    fileprivate static func decimalToUInt64Clamped(_ value: Decimal) -> UInt64 {
        if value <= 0 { return 0 }
        let maxDecimal = Decimal(UInt64.max)
        if value >= maxDecimal { return UInt64.max }
        let nsNumber = value as NSDecimalNumber
        return nsNumber.uint64Value
    }
}
