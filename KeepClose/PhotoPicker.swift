import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct PhotoPickerState {
    var personID: UUID?
    var choosing = false
    var library = false
    var camera = false
    var cameraRequested = false
    var fixture = false
    var loading = false

    var busy: Bool { choosing || library || camera || cameraRequested || fixture || loading }

    mutating func open(for id: UUID) {
        guard !busy else { return }
        personID = id
        choosing = true
    }

    mutating func requestCamera(for id: UUID) {
        guard !busy else { return }
        personID = id
        cameraRequested = true
    }
}

struct PhotoPicker: ViewModifier {
    @ObservedObject var model: AppModel
    @Binding var state: PhotoPickerState
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(L.t("photo.add"), isPresented: $state.choosing) {
                Button(L.t("photo.library")) {
                    if model.testing { state.fixture = true } else { state.library = true }
                }
                .accessibilityIdentifier("photo.library")
                if UIImagePickerController.isSourceTypeAvailable(.camera), let id = state.personID {
                    Button(L.t("photo.camera")) {
                        state.choosing = false
                        state.requestCamera(for: id)
                    }
                }
            }
            .onChange(of: state.cameraRequested) { _, requested in
                if requested { openCamera() }
            }
            .photosPicker(isPresented: $state.library, selection: $item, matching: .images)
            .onChange(of: item) { _, selected in
                guard let selected, let id = state.personID else { return }
                item = nil
                state.loading = true
                Task {
                    defer { state.loading = false }
                    if let bytes = try? await selected.loadTransferable(type: Data.self) {
                        await model.addPhoto(bytes, to: id)
                    } else {
                        model.message = L.t("error.photo")
                    }
                }
            }
            .fullScreenCover(isPresented: $state.camera) {
                CameraView { image in
                    state.camera = false
                    if let image { save(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $state.fixture) {
                Button(L.t("photo.add")) {
                    state.fixture = false
                    save(Seed.sampleImage())
                }
                .buttonStyle(PrimaryButton())
                .padding(24)
                .accessibilityIdentifier("photo.fixture")
                .presentationDetents([.medium])
            }
    }

    private func openCamera() {
        state.cameraRequested = false
        if model.testing {
            state.fixture = true
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            model.message = L.t("photo.camera-unavailable")
            return
        }
        state.loading = true
        Task { @MainActor in
            defer { state.loading = false }
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            if granted { state.camera = true }
            else { model.message = L.t("photo.camera-denied") }
        }
    }

    private func save(_ image: UIImage) {
        guard let id = state.personID else { return }
        state.loading = true
        Task {
            defer { state.loading = false }
            await model.addPhoto(image, to: id)
        }
    }
}
