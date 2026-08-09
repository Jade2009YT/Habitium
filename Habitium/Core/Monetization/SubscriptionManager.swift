//
//  SubscriptionManager.swift
//  Habitium
//
//  StoreKit 2 wrapper for a single auto-renewable subscription
//  ("Habitium Pro", monthly). This is scaffolding for a *possible* future
//  App Store release — for personal use nothing in the app checks
//  `isProActive`, so the app is fully unlocked regardless of purchase
//  state. If you ever publish and want to gate a feature, read
//  `isProActive` from the environment and branch in the view.
//
//  Testing locally costs nothing: Xcode's StoreKit Testing framework reads
//  Configuration/Habitium.storekit (already set up with the monthly
//  product) when you select it under Scheme → Options → StoreKit
//  Configuration, so you can exercise the whole purchase flow in the
//  Simulator without an App Store Connect account.
//

import Foundation
import Observation
import StoreKit

enum HabitiumProduct {
    /// Must match the product identifier configured both in
    /// Configuration/Habitium.storekit (local testing) and, eventually, in
    /// App Store Connect (real release).
    static let proMonthly = "com.habitium.app.pro.monthly"
    static let all: Set<String> = [proMonthly]
}

@MainActor
@Observable
final class SubscriptionManager {

    private(set) var products: [Product] = []
    private(set) var isProActive: Bool = false
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

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
        guard let product = products.first(where: { $0.id == HabitiumProduct.proMonthly }) else {
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
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
            }
            await refreshEntitlements()
        }
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == HabitiumProduct.proMonthly {
                active = transaction.revocationDate == nil
            }
        }
        isProActive = active
    }
}
