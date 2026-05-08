//
//  Item.swift
//  Rclone GUI
//
//  Created by Vitalys ROUGETET--DE TROYANE on 08/05/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
