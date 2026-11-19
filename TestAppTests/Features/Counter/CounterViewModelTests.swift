import Testing
@testable import TestApp

@MainActor
struct CounterViewModelTests {
    @Test func startsAtInitialValue() {
        let viewModel = CounterViewModel(count: 5)
        #expect(viewModel.count == 5)
    }

    @Test func initialValueIsClampedToRange() {
        let viewModel = CounterViewModel(count: 200, range: 0...10)
        #expect(viewModel.count == 10)
    }

    @Test func incrementAddsStep() {
        let viewModel = CounterViewModel(step: 2)
        viewModel.increment()
        #expect(viewModel.count == 2)
    }

    @Test func decrementSubtractsStep() {
        let viewModel = CounterViewModel(count: 5, step: 2)
        viewModel.decrement()
        #expect(viewModel.count == 3)
    }

    @Test func doesNotExceedUpperBound() {
        let viewModel = CounterViewModel(count: 9, range: 0...9)
        #expect(!viewModel.canIncrement)
        viewModel.increment()
        #expect(viewModel.count == 9)
    }

    @Test func doesNotGoBelowLowerBound() {
        let viewModel = CounterViewModel(count: 0, range: 0...9)
        #expect(!viewModel.canDecrement)
        viewModel.decrement()
        #expect(viewModel.count == 0)
    }

    @Test func resetRestoresInitialValue() {
        let viewModel = CounterViewModel(count: 3)
        #expect(!viewModel.canReset)
        viewModel.increment()
        viewModel.increment()
        #expect(viewModel.canReset)
        viewModel.reset()
        #expect(viewModel.count == 3)
    }
}
