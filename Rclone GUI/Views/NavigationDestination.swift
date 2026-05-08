//
//  NavigationDestination.swift
//  Rclone GUI — Views
//
//  Single hashable enum used by NavigationStack. Letting all destinations
//  share the same type means we can declare ONE `.navigationDestination`
//  modifier at the root and route everywhere from it.
//

import Foundation

public enum NavigationDestination: Hashable, Sendable {
    case folder(remote: String, path: String)
}
