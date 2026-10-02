import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing & van Wijk). Returns one rectangle per
/// size, in the same order. Sizes should be sorted biggest first for the best shapes.
/// Zero and negative sizes get an empty rectangle.
func squarify(_ sizes: [Double], in bounds: CGRect) -> [CGRect] {
    var result = Array(repeating: CGRect.zero, count: sizes.count)
    let total = sizes.reduce(0) { $0 + max($1, 0) }
    guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

    let scale = Double(bounds.width * bounds.height) / total
    var pending: [(index: Int, area: Double)] = sizes.enumerated()
        .filter { $0.element > 0 }
        .map { ($0.offset, $0.element * scale) }
    var rect = bounds

    func worst(_ row: ArraySlice<(index: Int, area: Double)>, side: Double) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard let mx = row.map(\.area).max(), let mn = row.map(\.area).min(), sum > 0, mn > 0 else { return .infinity }
        return max(side * side * mx / (sum * sum), (sum * sum) / (side * side * mn))
    }

    while !pending.isEmpty {
        let side = Double(min(rect.width, rect.height))
        var count = 1
        var best = worst(pending[0..<1], side: side)
        while count < pending.count {
            let next = worst(pending[0...count], side: side)
            if next > best { break }
            best = next
            count += 1
        }
        let row = pending[0..<count]
        let sum = row.reduce(0) { $0 + $1.area }
        if rect.width >= rect.height {
            let w = CGFloat(sum) / rect.height
            var y = rect.minY
            for item in row {
                let h = CGFloat(item.area) / w
                result[item.index] = CGRect(x: rect.minX, y: y, width: w, height: h)
                y += h
            }
            rect = CGRect(x: rect.minX + w, y: rect.minY, width: max(rect.width - w, 0), height: rect.height)
        } else {
            let h = CGFloat(sum) / rect.width
            var x = rect.minX
            for item in row {
                let w = CGFloat(item.area) / h
                result[item.index] = CGRect(x: x, y: rect.minY, width: w, height: h)
                x += w
            }
            rect = CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: max(rect.height - h, 0))
        }
        pending.removeFirst(count)
    }
    return result
}
