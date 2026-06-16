import Foundation

enum DaemonDetector {
    struct DetectionState {
        let detectedURL: URL?
        let probes: [BinaryProbe]

        var details: String {
            probes
                .map { probe in
                    if probe.isDetected {
                        return "\(probe.url.path): executable"
                    }
                    if probe.exists {
                        return "\(probe.url.path): \(probe.detail)"
                    }
                    return "\(probe.url.path): \(probe.detail)"
                }
                .joined(separator: "\n")
        }
    }

    struct BinaryProbe {
        let url: URL
        let exists: Bool
        let hasExecutableModeBit: Bool
        let detail: String

        var isDetected: Bool {
            exists && hasExecutableModeBit
        }
    }

    static func detectedBinaryURL() -> URL? {
        detectionState().detectedURL
    }

    static func detectionState() -> DetectionState {
        let probes = [probeBinary(AppPaths.rootlessDaemonURL)]
        return DetectionState(
            detectedURL: probes.first(where: \.isDetected)?.url,
            probes: probes
        )
    }

    private static func probeBinary(_ url: URL) -> BinaryProbe {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            return BinaryProbe(
                url: url,
                exists: false,
                hasExecutableModeBit: false,
                detail: error.localizedDescription
            )
        }

        let mode = attributes[.posixPermissions] as? Int ?? 0
        let hasExecutableModeBit = (mode & 0o111) != 0
        return BinaryProbe(
            url: url,
            exists: true,
            hasExecutableModeBit: hasExecutableModeBit,
            detail: hasExecutableModeBit ? "executable" : "missing executable mode"
        )
    }
}
