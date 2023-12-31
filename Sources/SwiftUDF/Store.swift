import SwiftUI
import Combine

public protocol StateStoreType: ObservableObject, TransitionSender, Reinitable {
    associatedtype StoreState: StateType
    associatedtype StoreAction: Action
    associatedtype StoreMutation: Mutation
    associatedtype StorePackages: EnvironmentPackages
    associatedtype StoreTransition: TransitionType
    associatedtype StoreMiddlewareRepository: MiddlewareRepositoryType

    var state: StoreState { get }
    var packages: StorePackages { get }

    func dispatch(_ action: StoreAction, on queueType: DispatchQueueSyncService.DispatchQueueType, isRedispatch: Bool)
}

extension StateStoreType {
    public typealias StoreDispatcher = DispatcherType<StoreAction, StoreMutation, StorePackages>
    public typealias StoreReducer = ReducerType<StoreState, StoreMutation, StoreTransition>
    public typealias Middleware = StoreMiddlewareRepository.Middleware
    public typealias MiddlewareRedispatch = StoreMiddlewareRepository.MiddlewareRedispatch
}

open class StateStore<
    StoreState,
    StoreAction,
    StoreMutation,
    StorePackages,
    StoreTransition
>: StateStoreType
where StoreState: StateType,
      StoreAction: Action,
      StoreMutation: Mutation,
      StorePackages: EnvironmentPackages,
      StoreTransition: TransitionType
{
    public typealias StoreMiddlewareRepository = MiddlewareRepository<StoreState, StoreAction, StorePackages>
    public typealias StoreDispatcher = DispatcherType<StoreAction, StoreMutation, StorePackages>
    public typealias StoreReducer = ReducerType<StoreState, StoreMutation, StoreTransition>

    public let transition = PassthroughSubject<StoreTransition, Never>()

    @Published private(set) public var state: StoreState
    private let dispatcher: StoreDispatcher
    private let reducer: StoreReducer
    private(set) public var packages: StorePackages
    private let queueService: DispatchQueueSyncService
    private var middlewareRepository: StoreMiddlewareRepository

    public init(
        state: StoreState,
        dispatcher: @escaping StoreDispatcher,
        reducer: @escaping StoreReducer,
        packages: StorePackages,
        queueService: DispatchQueueSyncService = DispatchQueueSyncService(),
        middlewares: [StoreMiddlewareRepository.Middleware] = []
    ) {
        self.state = state
        self.dispatcher = dispatcher
        self.reducer = reducer
        self.packages = packages
        self.queueService = queueService
        self.middlewareRepository = MiddlewareRepository(middlewares: middlewares, queue: self.queueService.queue(type: .serial))
    }

    public final func dispatch(_ action: StoreAction, on queueType: DispatchQueueSyncService.DispatchQueueType = .serial, isRedispatch: Bool = false) {
        middlewareRepository.dispatch(    // Middleware
            state: state,
            action: action,
            packages: packages,
            isRedispatch: isRedispatch
        )
        .subscribe(on: self.queueService.queue(type: .serial))
        .receive(on: self.queueService.queue(type: queueType))
        .catch {[unowned self] in
            if case let StoreMiddlewareRepository.MiddlewareRedispatch.redispatch(actions, _) = $0 {
                for action in actions {
                    self.dispatch(action, isRedispatch: true)
                }
            }
            return Empty<StoreAction, StoreMiddlewareRepository.MiddlewareRedispatch>()
        }
        .assertNoFailure()
        .flatMap { [unowned self] in dispatcher($0, self.packages) }   // Dispatch
        .receive(on: DispatchQueue.main)
        .flatMap { [unowned self] in reducer(state, $0) }   // Reduce
        .compactMap {
            switch $0 {
            case let .state(state):
                return state
            case let .coordinate(destination):
                self.transition.send(destination)
                return nil
            }
        }
        .assign(to: &$state)
    }

    @discardableResult
    public func reinit() -> Self {
        self.packages = self.packages.reinit()
        self.state = self.state.reinit()
        self.middlewareRepository = self.middlewareRepository.reinit()

        return self
    }
}
