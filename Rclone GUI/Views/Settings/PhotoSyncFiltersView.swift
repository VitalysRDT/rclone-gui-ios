//
//  PhotoSyncFiltersView.swift
//  Rclone GUI — Views/Settings
//
//  Lets the user restrict which Photos library assets get backed up. Maps
//  directly to `PhotoSyncService.filters` (PhotoSyncFilters JSON in UserDefaults).
//

import SwiftUI

struct PhotoSyncFiltersView: View {
    @State private var filters: PhotoSyncFilters = .allEnabled
    @State private var useDateRange = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var useMaxDuration = false
    @State private var maxDurationMinutes: Double = 10

    var body: some View {
        Form {
            Section {
                Toggle("Photos", isOn: $filters.includePhotos)
                Toggle("Vidéos", isOn: $filters.includeVideos)
            } header: {
                Text("Types principaux")
            } footer: {
                Text("Décocher exclut entièrement la catégorie. Au moins une doit rester cochée pour que la sync ait quelque chose à faire.")
            }

            Section {
                Toggle("Live Photos", isOn: $filters.includeLivePhotos)
                    .disabled(!filters.includePhotos)
                Toggle("Captures d'écran", isOn: $filters.includeScreenshots)
                    .disabled(!filters.includePhotos)
                Toggle("Panoramas", isOn: $filters.includePanoramas)
                    .disabled(!filters.includePhotos)
                Toggle("Slow-mo / time-lapse", isOn: $filters.includeSlowMo)
                    .disabled(!filters.includeVideos)
            } header: {
                Text("Sous-types")
            } footer: {
                Text("Un Live Photo reste une photo : décocher l'option ne supprime pas la photo principale, ça ignore juste la composante vidéo liée.")
            }

            Section {
                Toggle("Filtrer par dates", isOn: $useDateRange)
                if useDateRange {
                    DatePicker("Du", selection: $startDate, displayedComponents: .date)
                    DatePicker("Au", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            } header: {
                Text("Plage de dates")
            } footer: {
                Text("Seules les photos prises entre ces deux dates seront indexées par la prochaine synchronisation.")
            }

            Section {
                Toggle("Limiter la durée des vidéos", isOn: $useMaxDuration)
                if useMaxDuration {
                    HStack {
                        Slider(value: $maxDurationMinutes, in: 1...120, step: 1)
                        Text("\(Int(maxDurationMinutes)) min")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            } header: {
                Text("Taille (durée vidéo)")
            } footer: {
                Text("Les vidéos plus longues que ce seuil sont sautées. Les photos ne sont pas affectées (elles sont toujours petites).")
            }

            Section {
                Button {
                    resetToDefaults()
                } label: {
                    Label("Tout réactiver (réinitialiser)", systemImage: "arrow.uturn.backward")
                }
                .disabled(filters.isDefault && !useDateRange && !useMaxDuration)
            } footer: {
                let n = filters.activeCount
                if n == 0 {
                    Text("Aucun filtre actif — toute la photothèque est éligible.")
                } else {
                    Text("\(n) filtre(s) actif(s). Les changements s'appliquent à la prochaine synchro.")
                }
            }
        }
        .navigationTitle("Filtres")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
        .task {
            load()
        }
        .onChange(of: filters) { _, _ in save() }
        .onChange(of: useDateRange) { _, _ in syncDateRangeToFilters(); save() }
        .onChange(of: startDate) { _, _ in syncDateRangeToFilters(); save() }
        .onChange(of: endDate) { _, _ in syncDateRangeToFilters(); save() }
        .onChange(of: useMaxDuration) { _, _ in syncMaxDurationToFilters(); save() }
        .onChange(of: maxDurationMinutes) { _, _ in syncMaxDurationToFilters(); save() }
    }

    private func load() {
        let current = PhotoSyncService.shared.filters
        filters = current
        if let start = current.dateRangeStart {
            startDate = start
            useDateRange = true
        }
        if let end = current.dateRangeEnd {
            endDate = end
            useDateRange = true
        }
        if let seconds = current.maxVideoDurationSeconds, seconds > 0 {
            maxDurationMinutes = max(1, seconds / 60)
            useMaxDuration = true
        }
    }

    private func save() {
        PhotoSyncService.shared.filters = filters
    }

    private func syncDateRangeToFilters() {
        if useDateRange {
            filters.dateRangeStart = startDate
            filters.dateRangeEnd = endDate
        } else {
            filters.dateRangeStart = nil
            filters.dateRangeEnd = nil
        }
    }

    private func syncMaxDurationToFilters() {
        if useMaxDuration {
            filters.maxVideoDurationSeconds = maxDurationMinutes * 60
        } else {
            filters.maxVideoDurationSeconds = nil
        }
    }

    private func resetToDefaults() {
        filters = .allEnabled
        useDateRange = false
        useMaxDuration = false
        save()
    }
}

#Preview {
    NavigationStack {
        PhotoSyncFiltersView()
    }
}
