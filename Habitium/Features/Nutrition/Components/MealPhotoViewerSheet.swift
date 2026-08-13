//
//  MealPhotoViewerSheet.swift
//  Habitium
//
//  Shows a saved meal photo after decrypting it on demand — this is the
//  one place FoodEntry.imageData ever gets decrypted, and doing so here
//  (rather than eagerly when listing meals) is what keeps "Escanear"/save
//  fast and Face ID-free while "ver foto" stays properly gated.
//

import SwiftUI

struct MealPhotoViewerSheet: View {
    let entry: FoodEntry
    var viewModel: FoodTrackerViewModel

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if isLoading {
                    ProgressView("Verificando identidad…")
                } else if failed {
                    ContentUnavailableFallback()
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            let decrypted = await viewModel.decryptedImage(for: entry)
            isLoading = false
            if let decrypted {
                image = decrypted
            } else {
                failed = true
            }
        }
    }
}

private struct ContentUnavailableFallback: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No se pudo mostrar la foto")
                .font(.headline)
            Text("Puede que canceles la verificación o que la foto esté dañada.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
