//
//  PhotoSyncLogger.swift
//  Rclone GUI — Services
//
//  Structured OSLog / OSSignpost surface for the PhotoSync pipeline.
//
//  Why this exists alongside `LogService`:
//  - `LogService` powers the in-app log viewer (user-facing feed).
//  - `PhotoSyncLog` powers `Console.app`, `log stream`, and Instruments
//    (developer-facing, signpost-aware). The pipeline emits both side by
//    side for hot paths so we get rich Instruments timelines without
//    spamming the in-app feed with per-photo debug noise.
//
//  Categories:
//    - photos.pipeline : producer/consumer runPipeline events
//    - photos.export   : Phase 2 PhotoKit export per-asset
//    - photos.upload   : rclone copyDirAsync job lifecycle
//    - photos.verify   : integrity verification (post-upload + manual)
//    - photos.signpost : OSSignposter for Instruments Points-of-Interest
//

import os

enum PhotoSyncLog {
    static let subsystem = "com.rougetet.rclone-gui"

    static let pipeline = Logger(subsystem: subsystem, category: "photos.pipeline")
    static let export   = Logger(subsystem: subsystem, category: "photos.export")
    static let upload   = Logger(subsystem: subsystem, category: "photos.upload")
    static let verify   = Logger(subsystem: subsystem, category: "photos.verify")

    /// Signposter for Instruments → Points-of-Interest. Use to bracket
    /// long-running blocks (Phase 2/3 exports, upload jobs, verify) so
    /// the timeline visualizes their overlap.
    static let signposter = OSSignposter(subsystem: subsystem, category: "photos.signpost")
}
