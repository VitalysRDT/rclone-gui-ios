//
//  RclonePhotoSyncActivityLiveActivity.swift
//  RclonePhotoSyncActivity
//
//  ⚠️ ÉTAPE MANUELLE REQUISE AVANT D'ACTIVER LE LIVE ACTIVITY :
//
//  Ce fichier est volontairement minimaliste tant que `PhotoSyncActivityAttributes`
//  et les `PausePhotoSyncIntent`/`ResumePhotoSyncIntent` ne sont pas ajoutés
//  au target membership de l'extension.
//
//  Comment activer le vrai Live Activity :
//   1. Dans Xcode, sélectionner `Rclone GUI/Models/PhotoSyncActivityAttributes.swift`
//      → File Inspector → Target Membership → cocher `RclonePhotoSyncActivity`
//   2. Idem pour `Rclone GUI/AppIntents/PhotoSyncIntents.swift`
//   3. Remplacer le contenu de ce fichier par le code complet du widget UI
//      (sauvegardé en bas du fichier dans le bloc `#if false`).
//   4. Dupliquer l'asset `AccentColor` dans `RclonePhotoSyncActivity/Assets.xcassets`
//      (les targets ne partagent pas le catalog).
//
//  Tant que cette étape n'est pas faite, le bridge `PhotoSyncLiveActivity`
//  côté main app appelle gracieusement `Activity.request(...)` qui échoue
//  silencieusement (aucune activité n'est créée — l'app continue de tourner
//  normalement, juste sans Dynamic Island).
//

import ActivityKit
import SwiftUI
import WidgetKit

// Stub minimal : Activity widget vide en attendant l'ajout du target
// membership pour PhotoSyncActivityAttributes. Reproduit la même
// structure pour que ActivityKit reconnaisse le type, mais sans UI.
struct PhotoSyncActivityAttributesStub: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stub: Bool = true
    }
    var stub: Bool = true
}

@available(iOS 16.2, *)
struct PhotoSyncActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PhotoSyncActivityAttributesStub.self) { _ in
            EmptyView()
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { EmptyView() }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }
}

/*
 ════════════════════════════════════════════════════════════════════════
 VRAI CODE LIVE ACTIVITY (à activer après l'étape manuelle ci-dessus)
 ════════════════════════════════════════════════════════════════════════

 @available(iOS 16.2, *)
 struct PhotoSyncActivityWidget: Widget {
     var body: some WidgetConfiguration {
         ActivityConfiguration(for: PhotoSyncActivityAttributes.self) { context in
             PhotoSyncLockScreenView(state: context.state, attributes: context.attributes)
                 .activityBackgroundTint(Color.black.opacity(0.85))
                 .activitySystemActionForegroundColor(.white)
         } dynamicIsland: { context in
             DynamicIsland {
                 DynamicIslandExpandedRegion(.leading) {
                     Image(systemName: "photo.stack.fill")
                         .font(.title3.weight(.semibold))
                         .foregroundStyle(Color("AccentColor"))
                 }
                 DynamicIslandExpandedRegion(.trailing) {
                     VStack(alignment: .trailing, spacing: 2) {
                         Text("\(context.state.completed)/\(context.state.total)")
                             .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                         if let eta = context.state.etaSeconds, eta > 0 {
                             Text(photoSyncETA(eta))
                                 .font(.system(.caption2, design: .monospaced))
                                 .foregroundStyle(.secondary)
                         }
                     }
                 }
                 DynamicIslandExpandedRegion(.center) {
                     if let name = context.state.currentFilename, !name.isEmpty {
                         Text(name)
                             .font(.caption.monospaced())
                             .foregroundStyle(.secondary)
                             .lineLimit(1)
                             .truncationMode(.middle)
                     } else {
                         Text(context.attributes.remoteLabel)
                             .font(.caption.weight(.medium))
                             .foregroundStyle(.secondary)
                     }
                 }
                 DynamicIslandExpandedRegion(.bottom) {
                     HStack(spacing: 12) {
                         ProgressView(value: context.state.progress)
                             .tint(Color("AccentColor"))
                         if #available(iOS 17.0, *) {
                             if context.state.isPaused {
                                 Button(intent: ResumePhotoSyncIntent()) {
                                     Label("Reprendre", systemImage: "play.fill")
                                 }
                                 .buttonStyle(.bordered)
                                 .tint(.green)
                             } else {
                                 Button(intent: PausePhotoSyncIntent()) {
                                     Label("Pause", systemImage: "pause.fill")
                                 }
                                 .buttonStyle(.bordered)
                                 .tint(Color("AccentColor"))
                             }
                         }
                     }
                 }
             } compactLeading: {
                 Image(systemName: context.state.phase.icon)
                     .foregroundStyle(Color("AccentColor"))
             } compactTrailing: {
                 Text("\(context.state.completed)/\(context.state.total)")
                     .font(.system(.caption, design: .monospaced).weight(.semibold))
                     .foregroundStyle(.primary)
             } minimal: {
                 ZStack {
                     Circle()
                         .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
                     Circle()
                         .trim(from: 0, to: max(0, min(1, context.state.progress)))
                         .stroke(Color("AccentColor"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                         .rotationEffect(.degrees(-90))
                 }
             }
             .keylineTint(Color("AccentColor"))
             .widgetURL(URL(string: "rclone-gui://photosync"))
         }
     }
 }

 @available(iOS 16.2, *)
 private struct PhotoSyncLockScreenView: View {
     let state: PhotoSyncActivityAttributes.ContentState
     let attributes: PhotoSyncActivityAttributes

     var body: some View {
         HStack(alignment: .top, spacing: 14) {
             Image(systemName: "photo.stack.fill")
                 .font(.title2.weight(.semibold))
                 .foregroundStyle(Color("AccentColor"))
                 .frame(width: 44, height: 44)
                 .background(Color("AccentColor").opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

             VStack(alignment: .leading, spacing: 6) {
                 HStack(alignment: .firstTextBaseline) {
                     Text(state.isPaused ? "PhotoSync en pause" : "PhotoSync")
                         .font(.headline)
                         .lineLimit(1)
                     Spacer(minLength: 8)
                     Text("\(state.completed)/\(state.total)")
                         .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                         .foregroundStyle(.secondary)
                 }
                 if let name = state.currentFilename, !name.isEmpty {
                     Text(name)
                         .font(.system(.caption, design: .monospaced))
                         .foregroundStyle(.secondary)
                         .lineLimit(1)
                         .truncationMode(.middle)
                 } else {
                     Text(attributes.remoteLabel)
                         .font(.caption)
                         .foregroundStyle(.secondary)
                 }
                 ProgressView(value: state.progress)
                     .progressViewStyle(.linear)
                     .tint(state.isPaused ? .gray : Color("AccentColor"))
                 HStack(spacing: 6) {
                     if state.speedBytesPerSec > 1 {
                         Label(photoSyncThroughput(state.speedBytesPerSec), systemImage: "speedometer")
                             .font(.caption2.monospacedDigit())
                             .foregroundStyle(.secondary)
                     }
                     Spacer()
                     if let eta = state.etaSeconds, eta > 0 {
                         Label(photoSyncETA(eta), systemImage: "hourglass")
                             .font(.caption2.monospacedDigit())
                             .foregroundStyle(.secondary)
                     }
                 }
             }
         }
         .padding(.horizontal, 16)
         .padding(.vertical, 12)
         .frame(maxWidth: .infinity, alignment: .leading)
     }
 }

 @available(iOS 16.2, *)
 fileprivate func photoSyncThroughput(_ bps: Double) -> String {
     guard bps > 1 else { return "—" }
     return "\(ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file))/s"
 }

 @available(iOS 16.2, *)
 fileprivate func photoSyncETA(_ seconds: Double) -> String {
     let s = max(0, Int(seconds.rounded()))
     if s < 60 { return "\(s) s" }
     if s < 3600 { return "\(s / 60) min" }
     return "\(s / 3600) h \((s % 3600) / 60) min"
 }
 */
