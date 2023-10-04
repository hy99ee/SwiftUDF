import Foundation
import Combine
import os

public typealias Redispatch = Fail

public protocol MiddlewareRepositoryType {
    associatedtype StoreState: StateType
    associatedtype StoreAction: Action
    associatedtype StorePackages: EnvironmentPackages
    associatedtype MiddlewareRedispatch: Error

    associatedtype Middleware = (StoreState, StoreAction) -> AnyPublisher<StoreAction, MiddlewareRedispatch>


    func dispatch(state: StoreState, action: StoreAction, packages: StorePackages, isRedispatch: Bool) -> AnyPublisher<StoreAction, MiddlewareRedispatch>
}

public final class MiddlewareRepository<StoreState, StoreAction, StorePackages>: MiddlewareRepositoryType, Reinitable
where StoreState: StateType,
      StoreAction: Action,
      StorePackages: EnvironmentPackages {
    public typealias Middleware = (StoreState, StoreAction, StorePackages) -> AnyPublisher<StoreAction, MiddlewareRedispatch>

    public enum RedispatchType {
        case repeatRedispatch
        case excludeRedispatch
    }

    public enum MiddlewareRedispatch: Error {
        case redispatch(actions: [StoreAction], type: RedispatchType = .repeatRedispatch)
    }

    private let middlewares: [Middleware]
    private let queue: DispatchQueue
    private var processMiddlewares: [Middleware]
    private var anyCancellables: Set<AnyCancellable> = []
    private var index = 0
    private var lastRedispatchActionCount = 0

    init(middlewares: [Middleware], queue: DispatchQueue) {
        self.middlewares = middlewares
        self.processMiddlewares = middlewares

        self.queue = queue
    }

    public func reinit() -> Self {
        anyCancellables = Set()
        processMiddlewares = middlewares

        return self
    }

    public func dispatch(state: StoreState, action: StoreAction, packages: StorePackages, isRedispatch: Bool) -> AnyPublisher<StoreAction, MiddlewareRedispatch>  {
        Deferred {
            Future {[unowned self] promise in
                self.anyCancellables = []
                self.index = 0
                if !isRedispatch {
                    processMiddlewares = middlewares
                }
                processMiddlewares.publisher
                    .flatMap { $0(state, action, packages) }
                    .handleEvents(receiveOutput: { [weak self] _ in self?.index += 1 })
                    .sink(receiveCompletion: {[unowned self] in
                        switch $0 {
                        case .finished:
                            promise(.success(action))
                        case let .failure(.redispatch(actions, type)):
                            switch type {
                            case .repeatRedispatch where lastRedispatchActionCount < 5:
                                if actions.contains(action) {
                                    lastRedispatchActionCount += 1
                                    if lastRedispatchActionCount > 1 {
                                        os_log(
                                            .fault,
                                            dso: reporterInfo.dli_fbase,
                                            log: OSLog(
                                                subsystem: "com.apple.runtime-issues",
                                                category: "SwiftUDF"
                                            ),
                                            "Repeat redispatch return with the same action"
                                        )
                                    }
                                } else {
                                    lastRedispatchActionCount = 0
                                }
                            default:
                                if processMiddlewares.count - 1 >= self.index {
                                    self.processMiddlewares.remove(at: self.index)
                                }
                            }
                            promise(.failure(.redispatch(actions: actions, type: type)))
                        }
                    }, receiveValue: { _ in })
                    .store(in: &anyCancellables)
            }
        }.eraseToAnyPublisher()
    }

    let reporterInfo: Dl_info = {
        var info = Dl_info()
        dladdr(
            dlsym(
                dlopen(nil, RTLD_LAZY),
                "$s10Foundation15AttributeScopesO7SwiftUIE05swiftE0AcDE0D12UIAttributesVmvg"
            ),
            &info
        )

        return info
    }()
}
