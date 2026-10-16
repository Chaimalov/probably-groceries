import Foundation

struct WidgetPage {
    let range: Range<Int>
    let previous: Int
    let next: Int

    init(count: Int, offset: Int, capacity: Int) {
        let count = max(0, count)
        let size = max(1, capacity)
        // Deletions may invalidate the final page; clamp instead of showing empty rows.
        let last = count == 0 ? 0 : ((count - 1) / size) * size
        let start = min(max(0, offset), last)
        range = start..<min(start + size, count)
        previous = max(0, start - size)
        next = range.upperBound < count ? range.upperBound : 0
    }
}
