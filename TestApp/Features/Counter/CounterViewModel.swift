import Observation

/// カウンター画面の状態とロジック。
/// UI から切り離しておくことで、ユニットテストで振る舞いを検証できる。
@Observable
final class CounterViewModel {
    /// 現在の値
    private(set) var count: Int

    /// 1 回の操作で増減する量
    let step: Int

    /// 取りうる値の範囲
    let range: ClosedRange<Int>

    private let initialCount: Int

    init(count: Int = 0, step: Int = 1, range: ClosedRange<Int> = 0...99) {
        let clamped = min(max(count, range.lowerBound), range.upperBound)
        self.count = clamped
        self.initialCount = clamped
        self.step = step
        self.range = range
    }

    var canIncrement: Bool { count + step <= range.upperBound }
    var canDecrement: Bool { count - step >= range.lowerBound }
    var canReset: Bool { count != initialCount }

    func increment() {
        guard canIncrement else { return }
        count += step
    }

    func decrement() {
        guard canDecrement else { return }
        count -= step
    }

    func reset() {
        count = initialCount
    }
}
