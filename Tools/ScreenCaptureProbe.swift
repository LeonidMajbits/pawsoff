import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreImage
import Foundation
import Darwin

// Native probe only. It is NOT part of PawsOff, and requires Screen Recording
// authorization separately. No pixels are written unless --snapshot is specified.
private final class Sink: NSObject, SCStreamOutput, SCStreamDelegate {
    private let lock = NSLock()
    private var completeFrames = 0
    private var errorMessage: String?
    private var lastPixelBuffer: CVPixelBuffer?
    let retainPixels: Bool
    init(retainPixels: Bool) { self.retainPixels = retainPixels }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let entries = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = entries.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        lock.lock(); defer { lock.unlock() }
        completeFrames += 1
        if retainPixels { lastPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); defer { lock.unlock() }; errorMessage = error.localizedDescription
    }
    func snapshot() -> (Int, String?, CVPixelBuffer?) {
        lock.lock(); defer { lock.unlock() }
        return (completeFrames, errorMessage, lastPixelBuffer)
    }
}
private func emit(_ values: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
}
private struct ProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
@main
struct ScreenCaptureProbe {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data(("Capture probe: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        var seconds = 60
        var includeCurtain = false
        var output: URL?
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--seconds":
                index += 1
                guard index < args.count, let value = Int(args[index]), (1...3600).contains(value) else {
                    throw ProbeError(message: "--seconds needs 1...3600")
                }
                seconds = value
            case "--include-curtain": includeCurtain = true
            case "--snapshot":
                index += 1
                guard index < args.count else { throw ProbeError(message: "--snapshot needs a new PNG path") }
                output = URL(fileURLWithPath: args[index])
                guard !FileManager.default.fileExists(atPath: output!.path) else {
                    throw ProbeError(message: "Refusing to overwrite the snapshot path")
                }
            default: throw ProbeError(message: "Usage: capture-probe [--seconds 60] [--include-curtain] [--snapshot new.png]")
            }
            index += 1
        }
        let initial = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = initial.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? initial.displays.first else {
            throw ProbeError(message: "No shareable display")
        }
        let excluded = includeCurtain ? [] : initial.applications.filter { $0.bundleIdentifier == "com.leonidmajbits.pawsoff" }
        if !includeCurtain && excluded.isEmpty {
            throw ProbeError(message: "Launch the bundled PawsOff.app before this probe so its process can be excluded")
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 1280; config.height = 720
        config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        config.queueDepth = 3
        config.showsCursor = false; config.capturesAudio = false
        let sink = Sink(retainPixels: output != nil)
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "PawsOff.CaptureProbe"))
        try await stream.startCapture()
        do {
            for second in 1...seconds {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let started = ProcessInfo.processInfo.systemUptime
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let state = sink.snapshot()
                if let message = state.1 { throw ProbeError(message: message) }
                try emit(["second": second, "uptime": started, "completeFrames": state.0,
                    "queryMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000,
                    "displays": content.displays.count, "windows": content.windows.count,
                    "excludedPawsOff": !includeCurtain])
            }
            let final = sink.snapshot()
            guard final.0 > 0 else { throw ProbeError(message: "No complete screen frame was delivered") }
            if let output {
                guard let pixels = final.2 else { throw ProbeError(message: "No pixels for explicit snapshot") }
                let image = CIImage(cvPixelBuffer: pixels)
                guard let cgImage = CIContext().createCGImage(image, from: image.extent),
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                    throw ProbeError(message: "PNG conversion failed")
                }
                try png.write(to: output, options: .withoutOverwriting)
            }
        } catch {
            try? await stream.stopCapture(); throw error
        }
        try await stream.stopCapture()
    }
}
