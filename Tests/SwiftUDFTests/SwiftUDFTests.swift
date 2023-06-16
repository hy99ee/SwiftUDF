import XCTest
import Combine
@testable import SwiftUDF


typealias Store = StateStore<MockState, MockAction, MockMutation, MockPackages, CloseTransition>
extension Store {
    static let middlewareOperation: Store.StoreMiddlewareRepository.Middleware = { state, action, packages in
        print("Middleware get action: \(action)")
        return Just(action)
            .setFailureType(to: StoreMiddlewareRepository.MiddlewareRedispatch.self)
            .eraseToAnyPublisher()
    }
}

enum MockAction: Action, Hashable {
    case mockAction
}
enum MockMutation: Mutation {
    case mockMutation
}
struct MockState: StateType, ReinitableByNewSelf {
    var result = false
}

let mockDispatcher: DispatcherType<MockAction, MockMutation, MockPackages> = { action, packages in
    switch action {
    case .mockAction:
        return Just(.mockMutation).eraseToAnyPublisher()
    }
}
let mockReducer: ReducerType<MockState, MockMutation, CloseTransition> = { _state, mutation in
    var state = _state

    switch mutation {
    case .mockMutation:
        state.result = true
    }

    return Just(.state(state)).eraseToAnyPublisher()
}

class MockPackages: EnvironmentPackages, Unreinitable {}


class StoreTests: XCTestCase {
    var store: Store!
    var state: MockState!
    var middlewares: [Store.StoreMiddlewareRepository.Middleware]!
    var packages: MockPackages!
    var dispatcher: DispatcherType<MockAction, MockMutation, MockPackages>!
    var reducer: ReducerType<MockState, MockMutation, CloseTransition>!

    override func setUp() {
        super.setUp()

        state = MockState()
        middlewares = []
        packages = MockPackages()
        dispatcher = mockDispatcher
        reducer = mockReducer

        store = Store(
            state: state,
            dispatcher: dispatcher,
            reducer: reducer,
            packages: packages,
            middlewares: middlewares
        )
    }

    override func tearDown() {
        store = nil
        middlewares = nil
        packages = nil
        dispatcher = nil
        reducer = nil
        super.tearDown()
    }

    func testStoreDispatchFlow() {
        let alertExpectation = XCTestExpectation(description: "StoreFlowTest")

        self.store.dispatch(.mockAction, on: .concurrent)

        DispatchQueue.main.async {
            self.store.dispatch(.mockAction, on: .concurrent)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            alertExpectation.fulfill()
        }

        wait(for: [alertExpectation], timeout: 1)
        XCTAssertTrue(self.store.state.result)
    }
}
