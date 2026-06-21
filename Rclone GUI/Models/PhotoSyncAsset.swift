//
//  PhotoSyncAsset.swift
//  Rclone GUI — Models
//
//  Persistent index for opportunistic Photo Library backup.
//

import Foundation
import SwiftData

public enum PhotoSyncStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case exporting
    case enqueued
    case completed
    case failed
    case skipped
}

@Model
public final class PhotoSyncAsset {
    // Index sur statusRaw : la bibliothèque fait 18k+ assets, et de nombreux
    // fetch/fetchCount filtrent sur statusRaw (pending/exporting/enqueued…) →
    // sans index, full scan de 18k lignes à chaque appel. localIdentifier est
    // déjà indexé (.unique).
    #Index<PhotoSyncAsset>([\.statusRaw])

    @Attribute(.unique) public var localIdentifier: String
    public var mediaType: String
    public var creationDate: Date?
    public var discoveredAt: Date
    public var lastAttemptAt: Date?
    public var completedAt: Date?
    public var statusRaw: String
    public var remotePathsJSON: String
    public var byteCount: Int64
    public var contentHash: String?
    public var retryCount: Int
    public var lastError: String?
    /// MD5 calculé localement avant l'upload (CryptoKit). Sert à dédupliquer
    /// et à comparer avec le hash distant après transfert.
    public var localHash: String?
    /// MD5 récupéré depuis rclone (lsjson --hash) après l'upload.
    public var remoteHash: String?
    /// `nil` tant qu'aucune vérification n'a eu lieu, sinon
    /// "verified" / "mismatch" / "missing" / "unsupported".
    public var verificationStatus: String?

    public var status: PhotoSyncStatus {
        get { PhotoSyncStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public var remotePaths: [String] {
        get {
            guard let data = remotePathsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8)
            remotePathsJSON = String(decoding: data, as: UTF8.self)
        }
    }

    public init(
        localIdentifier: String,
        mediaType: String,
        creationDate: Date?
    ) {
        self.localIdentifier = localIdentifier
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.discoveredAt = .now
        self.statusRaw = PhotoSyncStatus.pending.rawValue
        self.remotePathsJSON = "[]"
        self.byteCount = 0
        self.retryCount = 0
    }
}
