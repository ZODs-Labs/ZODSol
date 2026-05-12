import Foundation

/// Modular arithmetic over the prime field F_p with p = 2^255 - 19.
///
/// Used only to validate that a 32-byte string decodes as a valid Ed25519
/// Edwards point. We do not implement signing or signature verification here;
/// that work belongs to CryptoKit. Implementation: 8 × UInt32 little-endian
/// limbs, schoolbook multiplication, fold high limbs via 2^256 ≡ 38 mod p.
///
/// Performance is not a concern: we run at most one `isOnCurve` check per
/// send-asset operation. Correctness is rigorously tested against the Ed25519
/// generator and against deterministic PDA test vectors.
struct Field25519: Equatable {
    /// 8 little-endian UInt32 limbs. Values are stored mod p in canonical form.
    let l: [UInt32]

    /// p = 2^255 - 19, expressed as 8 little-endian UInt32 limbs.
    static let pLimbs: [UInt32] = [
        0xFFFF_FFED, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF,
        0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF,
    ]

    /// p - 2, the exponent for modular inverse via Fermat's little theorem.
    /// p - 2 = 2^255 - 21.
    static let pMinus2Limbs: [UInt32] = [
        0xFFFF_FFEB, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF,
        0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF,
    ]

    /// (p - 1) / 2 = 2^254 - 10, the exponent for the Legendre symbol.
    static let pMinus1Over2Limbs: [UInt32] = [
        0xFFFF_FFF6, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF,
        0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, 0x3FFF_FFFF,
    ]

    /// d = -121665/121666 mod p, the twisted-Edwards parameter for Ed25519.
    /// Big-endian: 52036CEE2B6FFE738CC740797779E89800700A4D4141D8AB75EB4DCA135978A3
    static let dLimbs: [UInt32] = [
        0x1359_78A3, 0x75EB_4DCA, 0x4141_D8AB, 0x0070_0A4D,
        0x7779_E898, 0x8CC7_4079, 0x2B6F_FE73, 0x5203_6CEE,
    ]

    static let zero = Field25519(canonicalLimbs: [0, 0, 0, 0, 0, 0, 0, 0])
    static let one = Field25519(canonicalLimbs: [1, 0, 0, 0, 0, 0, 0, 0])

    /// Construct from 8 limbs assumed to be canonical (< p). Callers that may
    /// pass non-canonical input must first call `reduceCanonical`.
    init(canonicalLimbs limbs: [UInt32]) {
        precondition(limbs.count == 8)
        self.l = limbs
    }

    /// Parse 32 bytes little-endian, returning a fully reduced field element.
    /// Values >= p wrap mod p (caller may want to reject such inputs first).
    init(bytesLE bytes: Data) {
        precondition(bytes.count == 32)
        let arr = Array(bytes)
        var limbs = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            let off = i * 4
            limbs[i] = UInt32(arr[off])
                | (UInt32(arr[off + 1]) << 8)
                | (UInt32(arr[off + 2]) << 16)
                | (UInt32(arr[off + 3]) << 24)
        }
        self.l = Self.reduceCanonical(limbs)
    }

    /// Serialize to 32 bytes little-endian.
    func toBytesLE() -> Data {
        var out = Data(count: 32)
        for i in 0..<8 {
            let v = self.l[i]
            out[i * 4] = UInt8(v & 0xFF)
            out[i * 4 + 1] = UInt8((v >> 8) & 0xFF)
            out[i * 4 + 2] = UInt8((v >> 16) & 0xFF)
            out[i * 4 + 3] = UInt8((v >> 24) & 0xFF)
        }
        return out
    }

    var isZero: Bool {
        self.l.allSatisfy { $0 == 0 }
    }

    /// True iff a >= p (lexicographic comparison from most-significant limb).
    static func greaterOrEqualP(_ x: [UInt32]) -> Bool {
        for i in (0..<8).reversed() where x[i] != self.pLimbs[i] {
            return x[i] > pLimbs[i]
        }
        return true
    }

    /// Subtract p from `x` (treating `x` as a 256-bit value >= p).
    static func subP(_ x: [UInt32]) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: 8)
        var borrow: Int64 = 0
        for i in 0..<8 {
            let d = Int64(x[i]) - Int64(self.pLimbs[i]) - borrow
            if d < 0 {
                out[i] = UInt32(d + (1 << 32))
                borrow = 1
            } else {
                out[i] = UInt32(d)
                borrow = 0
            }
        }
        return out
    }

    /// Reduce a (possibly non-canonical) 8-limb value to canonical form < p.
    static func reduceCanonical(_ x: [UInt32]) -> [UInt32] {
        var v = x
        while self.greaterOrEqualP(v) {
            v = self.subP(v)
        }
        return v
    }

    static func add(_ a: Field25519, _ b: Field25519) -> Field25519 {
        var out = [UInt32](repeating: 0, count: 8)
        var carry: UInt64 = 0
        for i in 0..<8 {
            let sum = UInt64(a.l[i]) + UInt64(b.l[i]) + carry
            out[i] = UInt32(sum & 0xFFFF_FFFF)
            carry = sum >> 32
        }
        // If carry, fold via 2^256 ≡ 38 mod p.
        if carry != 0 {
            var c: UInt64 = 38
            for i in 0..<8 {
                let sum = UInt64(out[i]) + c
                out[i] = UInt32(sum & 0xFFFF_FFFF)
                c = sum >> 32
                if c == 0 { break }
            }
        }
        return Field25519(canonicalLimbs: self.reduceCanonical(out))
    }

    static func sub(_ a: Field25519, _ b: Field25519) -> Field25519 {
        var out = [UInt32](repeating: 0, count: 8)
        var borrow: Int64 = 0
        for i in 0..<8 {
            let d = Int64(a.l[i]) - Int64(b.l[i]) - borrow
            if d < 0 {
                out[i] = UInt32(d + (1 << 32))
                borrow = 1
            } else {
                out[i] = UInt32(d)
                borrow = 0
            }
        }
        if borrow != 0 {
            // out += p
            var carry: UInt64 = 0
            for i in 0..<8 {
                let sum = UInt64(out[i]) + UInt64(self.pLimbs[i]) + carry
                out[i] = UInt32(sum & 0xFFFF_FFFF)
                carry = sum >> 32
            }
        }
        return Field25519(canonicalLimbs: self.reduceCanonical(out))
    }

    static func mul(_ a: Field25519, _ b: Field25519) -> Field25519 {
        // 8x8 schoolbook into 16 limbs (each in low 32 bits of a UInt64).
        var prod = [UInt64](repeating: 0, count: 16)
        for i in 0..<8 {
            var carry: UInt64 = 0
            for j in 0..<8 {
                let p = UInt64(a.l[i]) * UInt64(b.l[j])
                let sum = prod[i + j] + (p & 0xFFFF_FFFF) + carry
                prod[i + j] = sum & 0xFFFF_FFFF
                carry = (p >> 32) + (sum >> 32)
            }
            // Propagate final carry up the high limbs.
            var k = i + 8
            while carry != 0, k < 16 {
                let sum = prod[k] + carry
                prod[k] = sum & 0xFFFF_FFFF
                carry = sum >> 32
                k += 1
            }
        }
        return self.reduce16(prod)
    }

    /// Reduce a 16-limb product (each limb in low 32 bits of UInt64) modulo p.
    private static func reduce16(_ prod: [UInt64]) -> Field25519 {
        // result = low8 + 38 * high8 (since 2^256 ≡ 38 mod p).
        var out = [UInt64](repeating: 0, count: 9)
        for i in 0..<8 {
            out[i] = prod[i]
        }

        var carry: UInt64 = 0
        for i in 0..<8 {
            let m = prod[i + 8] * 38 + carry
            let sum = out[i] + (m & 0xFFFF_FFFF)
            out[i] = sum & 0xFFFF_FFFF
            carry = (m >> 32) + (sum >> 32)
        }
        out[8] = carry

        // Fold spill into low limbs once more. out[8] * 38 fits in ~40 bits
        // worst case (since prod[i+8] < 2^32 and we accumulated up to 8 of them).
        if out[8] != 0 {
            var c = out[8] * 38
            out[8] = 0
            for i in 0..<8 {
                let sum = out[i] + (c & 0xFFFF_FFFF)
                out[i] = sum & 0xFFFF_FFFF
                c = (sum >> 32) + (c >> 32)
                if c == 0 { break }
            }
        }

        var limbs = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            limbs[i] = UInt32(out[i] & 0xFFFF_FFFF)
        }
        return Field25519(canonicalLimbs: self.reduceCanonical(limbs))
    }

    /// Modular exponentiation: self^exp mod p, where `exp` is little-endian limbs.
    static func pow(_ base: Field25519, _ expLimbs: [UInt32]) -> Field25519 {
        var result = Field25519.one
        var b = base
        // Iterate from least-significant bit to most.
        for limb in expLimbs {
            var bits = limb
            for _ in 0..<32 {
                if (bits & 1) == 1 {
                    result = self.mul(result, b)
                }
                b = self.mul(b, b)
                bits >>= 1
            }
        }
        return result
    }

    /// Modular inverse via Fermat: a^(p-2) mod p. Returns zero for input zero.
    static func inv(_ a: Field25519) -> Field25519 {
        self.pow(a, self.pMinus2Limbs)
    }
}
