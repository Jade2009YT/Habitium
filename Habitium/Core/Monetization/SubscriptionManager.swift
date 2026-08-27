//
//  SubscriptionManager.swift
//  Habitium
//
//  StoreKit 2 wrapper for two ways to unlock "Habitium Pro": an
//  auto-renewable monthly subscription, or a non-consumable one-time
//  "lifetime" purchase. This is scaffolding for a *possible* future App
//  Store release — for personal use nothing in the app checks
//  `isProActive`, so the app is fully unlocked regardless of purchase
//  state. If you ever publish and want to gate a feature, read
//  `isProActive` from the environment and branch in the view.
//
//  Testing locally costs nothing: Xcode's StoreKit Testing framework reads
//  Configuration/Habitium.storekit (already set up with both products)
//  when you select it under Scheme → Options → StoreKit Configuration, so
//  you can exercise the whole purchase flow in the Simulator without an
//  App Store Connect account.
//
//  Licensing note: this does NOT require any login system to work across
//  a user's devices. StoreKit entitlements are tied to their Apple ID
//  automatically — "Restaurar compras" re-syncs on any device signed in
//  with the same Apple ID. A custom account system would only be needed
//  for something StoreKit can't do (e.g. syncing app *data*, not just
//  purchase status, or a non-Apple platform).
//

import Foundation
import Observation
import StoreKit

enum HabitiumProduct {
    /// Must match the product identifiers configured both in
    /// Configuration/Habitium.storekit (local testing) and, eventually, in
    /// App Store Connect (real release).
    static let proMonthly = "com.habitium.app.pro.monthly"
    static let lifetime = "com.habitium.app.lifetime"
    static let all: Set<String> = [proMonthly, lifetime]
}

@MainActor
@Observable
final class SubscriptionManager {

    private(set) var products: [Product] = []
    private(set) var isSubscriptionActive: Bool = false
    private(set) var isLifetimeOwned: Bool = false
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    /// Unlocked either way — subscribed monthly, or bought once for life.
    var isProActive: Bool { isSubscriptionActive || isLifetimeOwned }

    var monthlyProduct: Product? { products.first { $0.id == HabitiumProduct.proMonthly } }
    var lifetimeProduct: Product? { products.first { $0.id == HabitiumProduct.lifetime } }

    // nonisolated(unsafe): only ever set once from init (on the main
    // actor) and read/cancelled from deinit, which Swift always treats as
    // nonisolated even on an @MainActor class — there's no real data race
    // here (Task itself is Sendable), just a shape the isolation checker
    // can't express any other way.
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: HabitiumProduct.all)
        } catch {
            errorMessage = "No se pudieron cargar los productos: \(error.localizedDescription)"
        }
    }

    func purchaseProMonthly() async {
        guard let product = monthlyProduct else {
            errorMessage = "Producto no disponible. Configura Habitium.storekit en el scheme de Xcode o publica el producto en App Store Connect."
            return
        }
        await purchase(product)
    }

    func purchaseLifetime() async {
        guard let product = lifetimeProduct else {
            errorMessage = "Producto no disponible. Configura Habitium.storekit en el scheme de Xcode o publica el producto en App Store Connect."
            return
        }
        await purchase(product)
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Compra fallida: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func observeTransactionUpdates() async {
        // Explicitly StoreKit.Transaction — Habitium also has its own
        // (finance) `Transaction` @Model in this module, and the bare name
        // resolves to that one instead, which has no `.updates` member.
        for await update in StoreKit.Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
            }
            await refreshEntitlements()
        }
    }

    private func refreshEntitlements() async {
        var subscriptionActive = false
        var lifetimeOwned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == HabitiumProduct.proMonthly {
                subscriptionActive = true
            } else if transaction.productID == HabitiumProduct.lifetime {
                lifetimeOwned = true
            }
        }
        isSubscriptionActive = subscriptionActive
        isLifetimeOwned = lifetimeOwned
    }
}
