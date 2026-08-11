import Foundation

struct SpacesRefreshSnapshot {
    let spaces: [AnySpace]
    let providerGeneration: Int
}

final class SpacesRefreshScheduler {
    typealias SnapshotLoader = () -> SpacesRefreshSnapshot?
    typealias PublishHandler = (SpacesRefreshSnapshot) -> Bool

    private let debounceInterval: TimeInterval
    private let stateQueue = DispatchQueue(
        label: "moe.ciel.CielBar.spaces-refresh-scheduler")
    private let refreshQueue = DispatchQueue(
        label: "moe.ciel.CielBar.spaces-refresh-loader",
        qos: .background)
    private let snapshotLoader: SnapshotLoader
    private let publishHandler: PublishHandler

    private var scheduledRefresh: DispatchWorkItem?
    private var refreshRequestID = 0
    private var isRunning = false
    private var needsFollowUpRefresh = false
    private var followUpRefreshPolicy: SpacesRefreshPolicy = .debounced
    private var isStopped = false
    private var lastPublishedSpaces: [AnySpace] = []

    init(
        debounceInterval: TimeInterval = 0.1,
        snapshotLoader: @escaping SnapshotLoader,
        publishHandler: @escaping PublishHandler
    ) {
        self.debounceInterval = debounceInterval
        self.snapshotLoader = snapshotLoader
        self.publishHandler = publishHandler
    }

    func requestRefresh(
        reason: SpacesChangeReason,
        policy: SpacesRefreshPolicy = .debounced
    ) {
        stateQueue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.scheduleRefreshLocked(reason: reason, policy: policy)
        }
    }

    func stop() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isStopped = true
            self.scheduledRefresh?.cancel()
            self.scheduledRefresh = nil
            self.refreshRequestID += 1
            self.needsFollowUpRefresh = false
            self.followUpRefreshPolicy = .debounced
        }
    }

    private func scheduleRefreshLocked(
        reason: SpacesChangeReason,
        policy: SpacesRefreshPolicy
    ) {
        if isRunning {
            recordFollowUpRefreshLocked(policy: policy)
            return
        }

        scheduledRefresh?.cancel()
        refreshRequestID += 1
        let requestID = refreshRequestID

        if policy == .immediate {
            startRefreshLocked(requestID: requestID, reason: reason)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.startRefreshLocked(requestID: requestID, reason: reason)
        }
        scheduledRefresh = workItem
        stateQueue.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem)
    }

    private func startRefreshLocked(
        requestID: Int,
        reason: SpacesChangeReason
    ) {
        guard !isStopped, requestID == refreshRequestID else { return }
        scheduledRefresh = nil

        if isRunning {
            recordFollowUpRefreshLocked(policy: .debounced)
            return
        }

        isRunning = true
        refreshQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.snapshotLoader()
            self.finishRefresh(snapshot: snapshot, reason: reason)
        }
    }

    private func finishRefresh(
        snapshot: SpacesRefreshSnapshot?,
        reason: SpacesChangeReason
    ) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isStopped else { return }

            guard let snapshot,
                snapshot.spaces != self.lastPublishedSpaces
            else {
                self.completeRefreshLocked(reason: reason)
                return
            }

            DispatchQueue.main.async { [weak self, publishHandler] in
                let wasPublished = publishHandler(snapshot)
                self?.stateQueue.async { [weak self] in
                    guard let self else { return }
                    if wasPublished {
                        self.lastPublishedSpaces = snapshot.spaces
                    }
                    self.completeRefreshLocked(reason: reason)
                }
            }
        }
    }

    private func completeRefreshLocked(reason: SpacesChangeReason) {
        isRunning = false
        guard !isStopped else { return }

        let shouldRunFollowUp = needsFollowUpRefresh
        let followUpPolicy = followUpRefreshPolicy
        needsFollowUpRefresh = false
        followUpRefreshPolicy = .debounced

        if shouldRunFollowUp {
            scheduleRefreshLocked(reason: reason, policy: followUpPolicy)
        }
    }

    private func recordFollowUpRefreshLocked(policy: SpacesRefreshPolicy) {
        needsFollowUpRefresh = true
        if policy == .immediate {
            followUpRefreshPolicy = .immediate
        }
    }
}
