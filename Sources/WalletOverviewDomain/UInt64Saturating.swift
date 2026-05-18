extension UInt64 {
    func saturatingMultiplied(by rhs: UInt64) -> UInt64 {
        let product = self.multipliedFullWidth(by: rhs)
        return product.high == 0 ? product.low : UInt64.max
    }
}
