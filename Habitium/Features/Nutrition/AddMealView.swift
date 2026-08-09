//
//  AddMealView.swift
//  Habitium
//
//  Sheet for logging a meal: pick a photo (analyzed by GPT-4o Vision /
//  Claude), describe it in text (also AI-analyzed), or enter macros
//  manually.
//

import PhotosUI
import SwiftUI

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FoodTrackerViewModel

    @State private var mealType: MealType = .breakfast
    @State private var mode: Mode = .photo

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?

    @State private var descriptionText = ""

    @State private var manualName = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""

    enum Mode: String, CaseIterable, Identifiable {
        case photo = "Foto"
        case text = "Texto"
        case manual = "Manual"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo de comida", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                }

                Section {
                    Picker("Método", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .photo: photoSection
                case .text: textSection
                case .manual: manualSection
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(Theme.Colors.danger)
                    }
                }
            }
            .navigationTitle("Registrar comida")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .disabled(viewModel.isAnalyzing)
            .overlay {
                if viewModel.isAnalyzing {
                    ProgressView("Analizando con IA…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Label("Elegir foto de la comida", systemImage: "camera.fill")
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    selectedImageData = try? await newValue?.loadTransferable(type: Data.self)
                }
            }

            Button("Analizar con IA") {
                guard let selectedImageData else { return }
                Task {
                    await viewModel.analyzePhoto(selectedImageData, mealType: mealType)
                    if viewModel.errorMessage == nil { dismiss() }
                }
            }
            .disabled(selectedImageData == nil)
        }
    }

    private var textSection: some View {
        Section {
            TextField("Ej: 2 huevos revueltos con pan tostado y aguacate", text: $descriptionText, axis: .vertical)
                .lineLimit(3...6)

            Button("Analizar con IA") {
                Task {
                    await viewModel.analyzeDescription(descriptionText, mealType: mealType)
                    if viewModel.errorMessage == nil { dismiss() }
                }
            }
            .disabled(descriptionText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var manualSection: some View {
        Section {
            TextField("Nombre de la comida", text: $manualName)
            TextField("Calorías", text: $manualCalories).keyboardType(.decimalPad)
            TextField("Proteína (g)", text: $manualProtein).keyboardType(.decimalPad)
            TextField("Carbohidratos (g)", text: $manualCarbs).keyboardType(.decimalPad)
            TextField("Grasas (g)", text: $manualFat).keyboardType(.decimalPad)

            Button("Guardar") {
                viewModel.addManualEntry(
                    name: manualName.isEmpty ? "Comida" : manualName,
                    mealType: mealType,
                    calories: Double(manualCalories) ?? 0,
                    protein: Double(manualProtein) ?? 0,
                    carbs: Double(manualCarbs) ?? 0,
                    fat: Double(manualFat) ?? 0
                )
                dismiss()
            }
            .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

#Preview {
    AddMealView(viewModel: FoodTrackerViewModel(container: AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext)))
}
