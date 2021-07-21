import SwiftUI

extension CGMConfig {
    struct RootView: BaseView {
        @EnvironmentObject var viewModel: ViewModel<Provider>

        var body: some View {
            Form {
                Section(header: Text("CGM Types")) {
                    if let cgmState = viewModel.cgmState {
                        Button {
                            viewModel.setupCGM = true
                        } label: {
                            HStack {
                                Image(uiImage: cgmState.image ?? UIImage()).padding()
                                Text(cgmState.name)
                            }
                        }
                    } else {
                        Button("Add Libre Transmitter") { viewModel.addCGM(.libretransmitter) }
                    }
                }
            }
            .navigationTitle("CGM config")
            .navigationBarTitleDisplayMode(.automatic)
            .popover(isPresented: $viewModel.setupCGM) {
                if let cgmManager = viewModel.provider.apsManager.cgmManager {
                    let apsGlucoseUnit = viewModel.provider.settingsManager.settings.units

                    CGMSettingsView(
                        cgmManager: cgmManager,
                        completionDelegate: viewModel,
                        glucoseUnit: apsGlucoseUnit == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter
                    )
                } else {
                    CGMSetupView(
                        cgmType: viewModel.setupCGMType,
                        cgmInitialSettings: viewModel.initialSettings,
                        completionDelegate: viewModel,
                        setupDelegate: viewModel
                    )
                }
            }
        }
    }
}
