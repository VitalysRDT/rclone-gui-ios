//
//  RclonePhotoSyncActivityBundle.swift
//  RclonePhotoSyncActivity
//
//  Top-level @main bundle that aggregates every widget shipped by the
//  PhotoSync extension. Currently:
//   - `PhotoSyncActivityWidget` : Live Activity (Dynamic Island + Lock
//     Screen banner) for the PhotoSync rclone copy pipeline.
//   - `PhotoSyncStatusWidget` : idle home-screen / lock-screen status
//     surface backed by App Group UserDefaults.
//

import SwiftUI
import WidgetKit

@main
struct RclonePhotoSyncActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            PhotoSyncActivityWidget()
        }
        PhotoSyncStatusWidget()
    }
}
