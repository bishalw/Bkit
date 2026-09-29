import BkitLogging

struct SyncService {
    let log: any Logging = OSLogger(subsystem: "com.example.notes", category: "sync")

    func finish(syncing count: Int) {
        log.info("Synced \(count) notes")  // "Synced 3 notes [SyncService.swift:7 finish(syncing:)]"
    }
}

// The README's logging snippet, compiled; it sits first so its line numbers match the README's.
