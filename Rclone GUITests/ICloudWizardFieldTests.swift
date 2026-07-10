//
//  ICloudWizardFieldTests.swift
//  Rclone GUITests
//
//  Unit tests for the iCloud Drive wizard field overrides: French labels
//  that state the real expected value (regular Apple ID password, not an
//  app-specific one), and the forced-picker rendering of `service`
//  (drive/photos) even though rclone doesn't flag the option Exclusive.
//

import Testing
import Foundation
@testable import Rclone_GUI

// MARK: - Fixtures

private func makeOption(
    name: String,
    exclusive: Bool = false,
    examples: [RcloneExampleValue]? = nil
) -> RcloneOptionSchema {
    RcloneOptionSchema(
        name: name,
        help: "",
        type: "string",
        defaultStr: "",
        valueStr: nil,
        required: true,
        isPassword: false,
        sensitive: false,
        advanced: false,
        exclusive: exclusive,
        hide: 0,
        noPrefix: false,
        examples: examples,
        provider: nil
    )
}

private let serviceExamples = [
    RcloneExampleValue(value: "drive", help: "iCloud Drive", provider: nil),
    RcloneExampleValue(value: "photos", help: "iCloud Photos", provider: nil),
]

// MARK: - Tests

@Suite("Overrides des champs du wizard iCloud")
struct ICloudWizardFieldTests {

    @Test("Labels iCloud : la vraie valeur attendue est nommée")
    func icloudFieldLabels() {
        #expect(BackendOverrides.fieldLabel(backend: "iclouddrive", field: "apple_id") == "Email Apple ID")
        #expect(BackendOverrides.fieldLabel(backend: "iclouddrive", field: "password") == "Mot de passe Apple ID (habituel)")
        #expect(BackendOverrides.fieldLabel(backend: "iclouddrive", field: "service") == "Service iCloud (Drive ou Photos)")
    }

    @Test("Pas d'override de label pour les autres backends/champs")
    func noLabelOverrideElsewhere() {
        #expect(BackendOverrides.fieldLabel(backend: "iclouddrive", field: "client_id") == nil)
        #expect(BackendOverrides.fieldLabel(backend: "s3", field: "apple_id") == nil)
        #expect(BackendOverrides.fieldLabel(backend: "drive", field: "service") == nil)
    }

    @Test("service iCloud est forcé en sélecteur exclusif")
    func icloudServiceForcesPicker() {
        #expect(BackendOverrides.forcesPicker(backend: "iclouddrive", field: "service"))
        #expect(!BackendOverrides.forcesPicker(backend: "iclouddrive", field: "apple_id"))
        #expect(!BackendOverrides.forcesPicker(backend: "s3", field: "service"))
    }

    @Test("FieldSpec : forcePicker rend un picker malgré exclusive=false")
    func forcePickerYieldsPickerUI() {
        let option = makeOption(name: "service", exclusive: false, examples: serviceExamples)

        let forced = FieldSpec(from: option, forcePicker: true)
        #expect(forced.uiKind == .picker)

        // Sans le forçage, le même schéma rclone donne le combobox flou.
        let plain = FieldSpec(from: option)
        #expect(plain.uiKind == .combobox)
    }

    @Test("FieldSpec : exclusive=true donne un picker sans forçage")
    func exclusiveStillYieldsPicker() {
        let option = makeOption(name: "region", exclusive: true, examples: serviceExamples)
        #expect(FieldSpec(from: option).uiKind == .picker)
    }

    @Test("FieldSpec : forcePicker sans examples reste un champ texte")
    func forcePickerWithoutExamplesFallsBack() {
        let option = makeOption(name: "service", exclusive: false, examples: nil)
        #expect(FieldSpec(from: option, forcePicker: true).uiKind == .textInput)
    }

    @Test("FieldSpec : le label override remplace le nom humanisé")
    func labelOverrideApplied() {
        let option = makeOption(name: "apple_id")
        #expect(FieldSpec(from: option).label == "Apple Id")
        #expect(FieldSpec(from: option, label: "Email Apple ID").label == "Email Apple ID")
    }
}
