//
//  AppIntent.swift
//  RclonePhotoSyncActivity
//
//  Created by Vitalys ROUGETET--DE TROYANE on 20/05/2026.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}
