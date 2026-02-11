//
//  ExtractionQueue.swift
//  Attune
//
//  Manages a FIFO queue of segments awaiting extraction.
//  Processes one segment at a time serially, using ExtractorService to extract items.
//  Returns results via completion handler; does NOT persist or filter.
//

import Foundation
import Combine

/// Work item representing a segment to be extracted
struct ExtractionWorkItem: Equatable {
    let sessionId: String
    let segmentId: String
    let segmentIndex: Int
    let transcriptText: String
    let priorContextText: String?
    
    /// Unique key for deduplication
    var key: String {
        return "\(sessionId)_\(segmentId)"
    }
    
    static func == (lhs: ExtractionWorkItem, rhs: ExtractionWorkItem) -> Bool {
        return lhs.key == rhs.key
    }
}

/// Internal work item with completion handler
private struct QueuedWorkItem {
    let workItem: ExtractionWorkItem
    let onComplete: ([ExtractedItem]) -> Void
}

/// Manages the extraction queue and processes segments serially.
/// Calls completion handler with results; does NOT persist or filter.
@MainActor
class ExtractionQueue: ObservableObject {
    
    // MARK: - Published State
    
    /// Number of segments pending extraction
    @Published var pendingCount: Int = 0
    
    /// Whether the queue is currently processing a segment
    @Published var isRunning: Bool = false
    
    // MARK: - Singleton
    
    static let shared = ExtractionQueue()
    
    // MARK: - Private State
    
    /// FIFO queue of work items with completion handlers
    private var queue: [QueuedWorkItem] = []
    
    /// Set of in-flight work item keys to prevent duplicates
    private var inFlight: Set<String> = []
    
    /// Current processing task (to prevent duplicate processing)
    private var processingTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Enqueues a segment for extraction.
    /// Automatically starts processing if not already running.
    /// - Parameters:
    ///   - workItem: The work item containing segment data
    ///   - onComplete: Completion handler called with extracted items (or empty array on failure)
    func enqueue(workItem: ExtractionWorkItem, onComplete: @escaping ([ExtractedItem]) -> Void) {
        let key = workItem.key
        
        // Avoid duplicate enqueue
        if queue.contains(where: { $0.workItem.key == key }) {
            AppLogger.log(AppLogger.QUE, "[extract] already_queued session=\(AppLogger.shortId(workItem.sessionId)) seg=\(workItem.segmentIndex)")
            return
        }
        
        // Avoid enqueuing if already in-flight
        if inFlight.contains(key) {
            AppLogger.log(AppLogger.QUE, "[extract] already_inflight session=\(AppLogger.shortId(workItem.sessionId)) seg=\(workItem.segmentIndex)")
            return
        }
        
        // Add to queue
        let queuedItem = QueuedWorkItem(workItem: workItem, onComplete: onComplete)
        queue.append(queuedItem)
        pendingCount = queue.count
        
        // Log enqueue operation
        AppLogger.log(
            AppLogger.QUE,
            "[extract] enqueued session=\(AppLogger.shortId(workItem.sessionId)) seg=\(workItem.segmentIndex) pending=\(queue.count)"
        )
        
        // Start processing if not already running
        startProcessingIfNeeded()
    }
    
    // MARK: - Processing
    
    /// Starts processing the queue if not already running
    private func startProcessingIfNeeded() {
        guard processingTask == nil else {
            // Already processing
            return
        }
        
        processingTask = Task {
            await processQueue()
            processingTask = nil
        }
    }
    
    /// Processes the queue serially until empty
    private func processQueue() async {
        isRunning = true
        
        while !queue.isEmpty {
            let queuedItem = queue.removeFirst()
            pendingCount = queue.count
            
            await processQueuedItem(queuedItem)
        }
        
        isRunning = false
    }
    
    /// Processes a single queued item with retry logic
    private func processQueuedItem(_ queuedItem: QueuedWorkItem) async {
        let workItem = queuedItem.workItem
        let key = workItem.key
        
        // Mark as in-flight
        inFlight.insert(key)
        
        // Log start
        AppLogger.log(
            AppLogger.QUE,
            "[extract] started session=\(AppLogger.shortId(workItem.sessionId)) seg=\(workItem.segmentIndex)"
        )
        
        // Call ExtractorService (which handles its own retry logic internally)
        let items = await ExtractorService.extractItems(
            transcriptText: workItem.transcriptText,
            priorContextText: workItem.priorContextText,
            sessionId: workItem.sessionId,
            segmentId: workItem.segmentId,
            segmentIndex: workItem.segmentIndex
        )
        
        // Remove from in-flight
        inFlight.remove(key)
        
        // Log completion
        AppLogger.log(
            AppLogger.QUE,
            "[extract] done session=\(AppLogger.shortId(workItem.sessionId)) seg=\(workItem.segmentIndex) items=\(items.count)"
        )
        
        // Call completion handler
        queuedItem.onComplete(items)
    }
    
}
