// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SDRReceiver",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SDRReceiver", targets: ["SDRReceiver"])
    ],
    targets: [
        .executableTarget(
            name: "SDRReceiver",
            dependencies: [
                "SoapySDRShim",
                "LiquidDSPShim"
            ],
            path: "Sources",
            exclude: [
                "UI/Shaders/WaterfallShader.metal"
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedLibrary("SoapySDR"),
                .linkedLibrary("liquid"),
                .linkedLibrary("rtlsdr"),
                .unsafeFlags(["-L/opt/homebrew/lib"])
            ]
        ),
        .systemLibrary(
            name: "SoapySDRShim",
            path: "Bridge/SoapySDRShim",
            pkgConfig: "SoapySDR",
            providers: [
                .brew(["soapysdr"])
            ]
        ),
        .systemLibrary(
            name: "LiquidDSPShim",
            path: "Bridge/LiquidDSPShim",
            providers: [
                .brew(["liquid-dsp"])
            ]
        )
    ]
)
