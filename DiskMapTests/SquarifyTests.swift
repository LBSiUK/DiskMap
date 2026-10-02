import CoreGraphics
import Testing
@testable import Disk_Map

struct SquarifyTests {
    let bounds = CGRect(x: 10, y: 20, width: 400, height: 300)

    @Test func areasAreProportionalToSizes() {
        let sizes: [Double] = [500, 250, 120, 80, 40, 10]
        let rects = squarify(sizes, in: bounds)
        let total = sizes.reduce(0, +)
        for (size, rect) in zip(sizes, rects) {
            let expected = Double(bounds.width * bounds.height) * size / total
            #expect(abs(Double(rect.width * rect.height) - expected) < 0.01)
        }
    }

    @Test func rectanglesStayInsideAndDoNotOverlap() {
        let rects = squarify([9, 7, 6, 4, 3, 2, 1, 1], in: bounds)
        for r in rects {
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(r))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.001)
            }
        }
    }

    @Test func emptyAndZeroInputGiveEmptyRects() {
        #expect(squarify([], in: bounds).isEmpty)
        #expect(squarify([0, 0], in: bounds) == [.zero, .zero])
        let mixed = squarify([5, 0, 5], in: bounds)
        #expect(mixed[1] == .zero)
        #expect(mixed[0].width > 0 && mixed[2].width > 0)
        #expect(squarify([1], in: .zero) == [.zero])
    }

    @Test func noNaNsForTinySizes() {
        let rects = squarify([1e12, 1, 1e-9], in: bounds)
        for r in rects {
            #expect(!r.origin.x.isNaN && !r.width.isNaN && !r.height.isNaN)
        }
    }
}
