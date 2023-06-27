import XCTest
import Combine
import SwiftUI
@testable import SwiftUDF

protocol StoreTestsContainerType {
    associatedtype Store: StateStoreType
    associatedtype TestCase: Equatable

    func makeSUT(for testCase: TestCase) -> Store
}

class StoreTestsContainer: StoreTestsContainerType {
    typealias TestCase = TestCaseValue
    typealias Store = StateStore<TestState, TestAction, TestMutation, TestPackages, CloseTransition>

    enum TestCaseValue: String {
        case middleware
        case flow
    }

    let printMiddleware: Store.Middleware = { _, action, _ in
        print("Mock middleware get action: \(action)")
        return Just(action)
            .setFailureType(to: Store.MiddlewareRedispatch.self)
            .eraseToAnyPublisher()
    }

    let repeatMiddleware: Store.Middleware = { state, action, _ in
        if state.count <= 5 {
            return Fail(error: Store.MiddlewareRedispatch.redispatch(actions: [.increaseCount])).eraseToAnyPublisher()
        }

        return Just(action)
            .setFailureType(to: Store.MiddlewareRedispatch.self)
            .eraseToAnyPublisher()
    }

    let flowReducer: Store.StoreReducer = { _state, mutation in
        var state = _state
        state.result = true

        return Just(.state(state)).eraseToAnyPublisher()
    }

    let middlewareReducer: Store.StoreReducer = { _state, mutation in
        var state = _state

        switch mutation {
        case .changeResult: state.result = true
        case .increaseCount: state.count += 1
        }

        return Just(.state(state)).eraseToAnyPublisher()
    }

    let flowDispatcher: Store.StoreDispatcher = { action, packages in
        Just(.changeResult).eraseToAnyPublisher()
    }

    let middlewareDispatcher: Store.StoreDispatcher = { action, packages in
        switch action {
        case .changeResult: return Just(.changeResult).eraseToAnyPublisher()
        case .increaseCount: return Just(.increaseCount).eraseToAnyPublisher()
        }
    }

    enum TestAction: Action, Hashable {
        case changeResult
        case increaseCount
    }

    enum TestMutation: Mutation {
        case changeResult
        case increaseCount
    }

    struct TestState: StateType, ReinitableByNewSelf {
        var result = false
        var count = 0
    }

    class TestPackages: EnvironmentPackages, Unreinitable {}

    func makeSUT(for testCase: TestCaseValue) -> Store {
        switch testCase {
        case .middleware:
            return Store(
                state: TestState(),
                dispatcher: middlewareDispatcher,
                reducer: middlewareReducer,
                packages: TestPackages(),
                middlewares: [printMiddleware, repeatMiddleware]
            )
        case .flow:
            return Store(
                state: TestState(),
                dispatcher: flowDispatcher,
                reducer: flowReducer,
                packages: TestPackages(),
                middlewares: [printMiddleware]
            )
        }

    }
}

class StoreFlowTests: XCTestCase {
    func testStoreDispatchFlow() {
        var store: StoreTestsContainer.Store! = StoreTestsContainer().makeSUT(for: .flow)

        let alertExpectation = XCTestExpectation(description: "StoreFlowTest")

        store.dispatch(.changeResult, on: .concurrent)

        DispatchQueue.main.async {
            store.dispatch(.changeResult, on: .concurrent)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            alertExpectation.fulfill()
        }

        wait(for: [alertExpectation], timeout: 1.5)
        XCTAssertTrue(store.state.result)
        store = nil
        XCTAssertNil(store)
    }

    func testStoreMiddlewareFlow() {
        var store: StoreTestsContainer.Store! = StoreTestsContainer().makeSUT(for: .middleware)
        let alertExpectation = XCTestExpectation(description: "StoreMiddlewareTest")

        store.dispatch(.increaseCount, on: .concurrent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.dispatch(.increaseCount, on: .concurrent)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            store.dispatch(.increaseCount, on: .concurrent)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            alertExpectation.fulfill()
        }

        wait(for: [alertExpectation], timeout: 2.5)
        XCTAssertEqual(store.state.count, 3)
        store = nil
        XCTAssertNil(store)
    }
}
