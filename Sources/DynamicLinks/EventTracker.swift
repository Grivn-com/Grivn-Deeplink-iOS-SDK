//
//  EventTracker.swift
//  DynamicLinks
//
//  SDK internal event tracker.
//  Batches events locally, flushing every 30s or when 20 events accumulate.
//

import Foundation

internal final class EventTracker: @unchecked Sendable {

    private let apiService: ApiService
    private let projectId: String
    private let deviceId: String
    private let deviceType: String
    private let osVersion: String
    private let appVersion: String
    private let sdkVersion: String

    private var pendingEvents: [EventItemRequest] = []
    private let lock = NSLock()
    private var flushTask: Task<Void, Never>?
    private var userId: String = ""

    init(
        apiService: ApiService,
        projectId: String,
        deviceId: String,
        deviceType: String,
        osVersion: String,
        appVersion: String,
        sdkVersion: String
    ) {
        self.apiService = apiService
        self.projectId = projectId
        self.deviceId = deviceId
        self.deviceType = deviceType
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
    }

    func start() {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                await flush()
            }
        }
        SDKLogger.debug("EventTracker started")
    }

    func stop() {
        flushTask?.cancel()
        flushTask = nil
        // Best-effort final flush
        Task {
            await flush()
        }
        SDKLogger.debug("EventTracker stopped")
    }

    func trackEvent(name: String, params: [String: Any]? = nil, deeplinkId: String? = nil) {
        let item = EventItemRequest(
            eventName: name,
            params: params,
            timestamp: Date().timeIntervalSince1970,
            deeplinkId: deeplinkId ?? "",
            userId: userId
        )

        var shouldFlush = false
        lock.lock()
        pendingEvents.append(item)
        shouldFlush = pendingEvents.count >= 20
        lock.unlock()

        if shouldFlush {
            Task { await flush() }
        }
    }

    func setUserId(_ id: String) {
        userId = id
        SDKLogger.debug("EventTracker userId set to: \(id)")
    }

    func flush() async {
        let batch: [EventItemRequest]
        lock.lock()
        if pendingEvents.isEmpty {
            lock.unlock()
            return
        }
        batch = pendingEvents
        pendingEvents.removeAll()
        lock.unlock()

        SDKLogger.debug("Flushing \(batch.count) events")

        let request = EventBatchRequest(
            projectId: projectId,
            deviceId: deviceId,
            deviceType: deviceType,
            osVersion: osVersion,
            appVersion: appVersion,
            sdkVersion: sdkVersion,
            events: batch
        )

        do {
            _ = try await apiService.trackEvents(request: request)
            SDKLogger.info("Flushed \(batch.count) events successfully")
        } catch {
            SDKLogger.warn("Failed to flush events, re-enqueuing", error)
            lock.lock()
            pendingEvents.insert(contentsOf: batch, at: 0)
            // Cap at 1000 to prevent unbounded growth
            if pendingEvents.count > 1000 {
                pendingEvents = Array(pendingEvents.prefix(1000))
            }
            lock.unlock()
        }
    }
}
