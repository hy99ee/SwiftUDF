import Combine
import SwiftUI

// MARK: Store
public protocol Action: Equatable {}

public protocol Mutation {}

public protocol Reinitable {
    func reinit() -> Self
}

public protocol ReinitableByNewSelf: Reinitable {
    init()
}
public extension ReinitableByNewSelf {
    func reinit() -> Self { Self() }
}

public protocol Unreinitable {}
public extension Unreinitable {
    func reinit() -> Self { self }
}

public protocol StateType: Reinitable, Equatable {}

public typealias DispatcherType<ActionType: Action, MutationType: Mutation, EnvironmentPackagesType: EnvironmentPackages> = ( _ action: ActionType, _ packages: EnvironmentPackagesType) -> AnyPublisher<MutationType, Never>

public typealias ReducerType<StoreState: StateType, StoreMutation: Mutation, Transition: TransitionType> = (_ state: StoreState, _ mutation: StoreMutation) -> AnyPublisher<AmbiguousMutation<StoreState, Transition>, Never>

public protocol EnvironmentType {}

public protocol EnvironmentPackages: Reinitable {}

public struct DispatchQueueSyncService {
    public enum DispatchQueueType {
        case serial
        case concurrent
    }

    public init(
        serialQueue: DispatchQueue = DispatchQueue(
            label: "com.udf.store.serial.queue",
            qos: .userInitiated
        ),
        concurrentQueue: DispatchQueue = DispatchQueue(
            label: "com.udf.store.concurrent.queue",
            qos: .userInitiated,
            attributes: .concurrent
        )
    ) {
        self.serialQueue = serialQueue
        self.concurrentQueue = concurrentQueue
    }

    public func queue(type: DispatchQueueType) -> DispatchQueue {
        switch type {
        case .serial:
            return serialQueue
        case .concurrent:
            return concurrentQueue
        }
    }

    private let concurrentQueue: DispatchQueue
    private let serialQueue: DispatchQueue
}

// MARK: Coordinator
public protocol TransitionType: Hashable, Identifiable {}

public enum AmbiguousMutation<State, Transition> where State: StateType, Transition: TransitionType {
    case state(_ state: State)
    case coordinate(destination: Transition)
}

public protocol TransitionSender {
    associatedtype SenderTransitionType: TransitionType

    var transition: PassthroughSubject<SenderTransitionType, Never> { get }
}

public protocol CoordinatorType: View {
    associatedtype Link: TransitionType

    var stateReceiver: AnyPublisher<Link, Never> { get }

    var path: NavigationPath { get }
    var alert: Link? { get }
    var sheet: Link? { get }
    var fullcover: Link? { get }

    var view: AnyView { get }
    
    func transitionReceiver(_ link: Link)
}

public extension NavigationPath {
    static let sharedPath = NavigationPath()
}
public extension CoordinatorType {
    var path: NavigationPath { NavigationPath.sharedPath }
    var alert: Link? { nil }
    var sheet: Link? { nil }
    var fullcover: Link? { nil }

    var body: some View {
        view
        .onReceive(stateReceiver) {
            transitionReceiver($0)
        }
    }
}

public enum NoneTransition : TransitionType {
    case none

    public var id: String { String(describing: self) }
}
public enum CloseTransition : TransitionType {
    case close

    public var id: String { String(describing: self) }
}
public enum ErrorTransition : TransitionType {
    case error(error: Error)

    public var id: String {
        if case let ErrorTransition.error(error) = self {
            return error.localizedDescription
        } else {
            return UUID().uuidString
        }
    }
    public static func == (lhs: ErrorTransition, rhs: ErrorTransition) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: self))
    }
}
