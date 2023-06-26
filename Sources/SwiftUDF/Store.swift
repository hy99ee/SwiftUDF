import SwiftUI
import Combine

public final class StateStore<
    StoreState,
    StoreAction,
    StoreMutation,
    StorePackages,
    StoreTransition
>: ObservableObject, TransitionSender, Reinitable
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
    private(set) var packages: StorePackages
    private let queueService: DispatchQueueSyncService
    private var middlewaresRepository: StoreMiddlewareRepository

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
        self.middlewaresRepository = MiddlewareRepository(middlewares: middlewares, queue: self.queueService.queue(type: .serial))
    }

    public func dispatch(_ action: StoreAction, isRedispatch: Bool = false, on queueType: DispatchQueueSyncService.DispatchQueueType = .serial) {
        middlewaresRepository.dispatch(    // Middleware
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
        .flatMap { [unowned self] in dispatcher($0, self.packages) }   // Dispatch
        .flatMap { [unowned self] in reducer(state, $0) }   // Reduce
        .assertNoFailure()
        .compactMap({
            switch $0 {
            case let .state(state):
                return state
            case let .coordinate(destination):
                self.transition.send(destination)
                return nil
            }
        })
        .assign(to: &$state)
    }

    @discardableResult
    public func reinit() -> Self {
        self.packages = self.packages.reinit()
        self.state = self.state.reinit()
        self.middlewaresRepository = self.middlewaresRepository.reinit()

        return self
    }
}
