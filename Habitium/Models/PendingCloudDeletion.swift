//
//  PendingCloudDeletion.swift
//  Habitium
//
//  A "tombstone": one row is inserted here (in the SAME context.save() as
//  the real delete, so it's never lost) every time a repository deletes
//  something that has a Supabase table. CloudSyncService drains these at
//  the start of every sync pass — deletes the matching row in Postgres,
//  then removes the tombstone. Without this, a deleted local row would
//  just... still exist in the cloud, and the next sync would pull it
//  right back as if it were new.
//

import Foundation
import SwiftData

@Model
final class PendingCloudDeletion {
    var id: UUID
    /// Supabase table name (see supabase/schema.sql), e.g. "habits".
    var table: String
    /// id of the deleted row in that table.
    var recordID: UUID
    var recordedAt: Date

    init(id: UUID = UUID(), table: String, recordID: UUID, recordedAt: Date = .now) {
        self.id = id
        self.table = table
        self.recordID = recordID
        self.recordedAt = recordedAt
    }
}
