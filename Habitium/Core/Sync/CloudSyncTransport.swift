//
//  CloudSyncTransport.swift
//  Habitium
//
//  Thin, generic wrapper over Postgrest calls — the only place
//  CloudSyncService talks to the network directly. Every failure is
//  swallowed and logged rather than thrown: a sync attempt that can't
//  reach Supabase (offline, expired token, whatever) must never crash or
//  block the app — local SwiftData already has the real data, the cloud
//  copy is a "when possible" mirror, not a dependency for the app to work.
//
//  ⚠️ Same blind-write disclaimer as SupabaseAuthManager/CloudSyncDTOs:
//  `.from(_:).select()/.upsert()/.delete()/.eq()/.execute()` is
//  supabase-swift v2's documented PostgrestClient builder pattern from
//  training knowledge, not compiled against the real resolved package.
//

import Foundation
import Supabase

enum CloudSyncTransport {

    /// Upserts by primary key (`id`) — used by every table except the
    /// three singletons, which call `upsertSingleton` instead.
    static func upsert<DTO: Encodable & Sendable>(_ rows: [DTO], table: String, client: SupabaseClient) async {
        guard !rows.isEmpty else { return }
        do {
            try await client.from(table).upsert(rows).execute()
        } catch {
            print("CloudSync: upsert \(table) failed — \(error)")
        }
    }

    /// Upserts a single row keyed by `user_id` instead of `id` — for the
    /// three singleton tables (nutrition_goals, budget_settings,
    /// user_settings). The DTOs for these tables have no `id` field at
    /// all, so ON CONFLICT (user_id) DO UPDATE never touches the row's
    /// primary key.
    static func upsertSingleton<DTO: Encodable & Sendable>(_ row: DTO, table: String, client: SupabaseClient) async {
        do {
            try await client.from(table).upsert(row, onConflict: "user_id").execute()
        } catch {
            print("CloudSync: upsert (singleton) \(table) failed — \(error)")
        }
    }

    /// All rows for the signed-in user — RLS already filters to
    /// `auth.uid() = user_id`, no explicit filter needed.
    static func fetchAll<DTO: Decodable>(table: String, client: SupabaseClient) async -> [DTO] {
        do {
            let response: [DTO] = try await client.from(table).select().execute().value
            return response
        } catch {
            print("CloudSync: fetch \(table) failed — \(error)")
            return []
        }
    }

    /// The signed-in user's single row for a singleton table, if any.
    static func fetchSingleton<DTO: Decodable>(table: String, client: SupabaseClient) async -> DTO? {
        await fetchAll(table: table, client: client).first
    }

    /// Deletes one row by id. Idempotent — deleting an id that's already
    /// gone (e.g. a retried tombstone) succeeds silently, doesn't throw.
    /// Returns whether the call itself succeeded (network/auth-wise), so
    /// the caller knows whether it's safe to clear the local tombstone.
    @discardableResult
    static func delete(id: UUID, table: String, client: SupabaseClient) async -> Bool {
        do {
            try await client.from(table).delete().eq("id", value: id.uuidString).execute()
            return true
        } catch {
            print("CloudSync: delete \(table) \(id) failed — \(error)")
            return false
        }
    }
}
