import Foundation
#if canImport(Darwin)
import Darwin
#endif

private let releaseAPIURL = "https://api.github.com/repos/runnon/devkat/releases/latest"
private let releaseAssetNeedle = "macos"

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

func runUpdate(force: Bool = false) {
    do {
        print("devkat-push: checking latest release...")
        let release = try fetchLatestRelease()
        let latestVersion = normalizedVersion(release.tagName)
        let currentVersion = normalizedVersion(cliVersion)

        if !force,
           !currentVersion.isEmpty,
           cliVersion != "DEVKAT_CLI_VERSION_PLACEHOLDER",
           compareVersions(currentVersion, latestVersion) >= 0 {
            print("devkat-push: already up to date (\(release.tagName))")
            return
        }

        guard let asset = release.assets.first(where: {
            $0.name.lowercased().contains(releaseAssetNeedle) && $0.name.lowercased().hasSuffix(".tar.gz")
        }) else {
            throw UpdateError.noCompatibleAsset
        }

        let targetURL = try currentExecutableURL()
        print("devkat-push: downloading \(asset.name)...")

        let workDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let archiveURL = try downloadAsset(asset, into: workDir)
        let binaryURL = try extractBinary(from: archiveURL, into: workDir)
        try replaceCurrentBinary(with: binaryURL, at: targetURL)

        print("devkat-push: installed \(release.tagName)")
        reinstallDaemon(with: targetURL)
    } catch {
        print("devkat-push: update failed - \(error.localizedDescription)")
        exit(1)
    }
}

private enum UpdateError: LocalizedError {
    case invalidReleaseURL
    case invalidAssetURL
    case noReleaseData
    case noCompatibleAsset
    case downloadFailed
    case archiveExtractionFailed
    case binaryMissing
    case executableNotFound
    case replacementFailed

    var errorDescription: String? {
        switch self {
        case .invalidReleaseURL:
            return "release URL is invalid"
        case .invalidAssetURL:
            return "release asset URL is invalid"
        case .noReleaseData:
            return "GitHub did not return release data"
        case .noCompatibleAsset:
            return "latest release does not include a macOS devkat-push tarball"
        case .downloadFailed:
            return "release asset download failed"
        case .archiveExtractionFailed:
            return "release archive could not be extracted"
        case .binaryMissing:
            return "release archive did not contain devkat-push"
        case .executableNotFound:
            return "could not locate the current devkat-push binary"
        case .replacementFailed:
            return "could not replace the current devkat-push binary"
        }
    }
}

private func fetchLatestRelease() throws -> GitHubRelease {
    guard let url = URL(string: releaseAPIURL) else { throw UpdateError.invalidReleaseURL }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("devkat-push/\(cliVersion)", forHTTPHeaderField: "User-Agent")

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>?

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    let session = URLSession(configuration: config)

    session.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            result = .failure(error)
            return
        }
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let data else {
            result = .failure(UpdateError.noReleaseData)
            return
        }
        result = .success(data)
    }.resume()

    _ = semaphore.wait(timeout: .now() + 30)
    let data = try result?.get() ?? { throw UpdateError.noReleaseData }()
    return try JSONDecoder().decode(GitHubRelease.self, from: data)
}

private func downloadAsset(_ asset: GitHubReleaseAsset, into directory: URL) throws -> URL {
    guard let url = URL(string: asset.browserDownloadURL) else { throw UpdateError.invalidAssetURL }

    let destination = directory.appendingPathComponent(asset.name)
    var request = URLRequest(url: url)
    request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
    request.setValue("devkat-push/\(cliVersion)", forHTTPHeaderField: "User-Agent")

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<URL, Error>?

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 300
    let session = URLSession(configuration: config)

    session.downloadTask(with: request) { temporaryURL, response, error in
        defer { semaphore.signal() }
        if let error {
            result = .failure(error)
            return
        }
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let temporaryURL else {
            result = .failure(UpdateError.downloadFailed)
            return
        }

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            result = .success(destination)
        } catch {
            result = .failure(error)
        }
    }.resume()

    _ = semaphore.wait(timeout: .now() + 300)
    return try result?.get() ?? { throw UpdateError.downloadFailed }()
}

private func extractBinary(from archiveURL: URL, into directory: URL) throws -> URL {
    let extractionDir = directory.appendingPathComponent("release")
    try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)

    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.arguments = ["-xzf", archiveURL.path, "-C", extractionDir.path]
    try tar.run()
    tar.waitUntilExit()
    guard tar.terminationStatus == 0 else { throw UpdateError.archiveExtractionFailed }

    let directBinary = extractionDir.appendingPathComponent("devkat-push")
    if FileManager.default.isExecutableFile(atPath: directBinary.path) {
        return directBinary
    }

    guard let enumerator = FileManager.default.enumerator(
        at: extractionDir,
        includingPropertiesForKeys: nil
    ) else {
        throw UpdateError.binaryMissing
    }

    for case let url as URL in enumerator where url.lastPathComponent == "devkat-push" {
        if FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
    }

    throw UpdateError.binaryMissing
}

private func replaceCurrentBinary(with newBinaryURL: URL, at targetURL: URL) throws {
    let fileManager = FileManager.default
    let targetDirectory = targetURL.deletingLastPathComponent()
    let replacementURL = targetDirectory.appendingPathComponent(".devkat-push.new.\(ProcessInfo.processInfo.processIdentifier)")
    let backupURL = targetDirectory.appendingPathComponent(".devkat-push.old.\(ProcessInfo.processInfo.processIdentifier)")

    try? fileManager.removeItem(at: replacementURL)
    try? fileManager.removeItem(at: backupURL)

    do {
        try fileManager.copyItem(at: newBinaryURL, to: replacementURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: replacementURL.path)

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.moveItem(at: targetURL, to: backupURL)
        }

        do {
            try fileManager.moveItem(at: replacementURL, to: targetURL)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: targetURL)
            }
            throw error
        }

        try? fileManager.removeItem(at: backupURL)
    } catch {
        try? fileManager.removeItem(at: replacementURL)
        throw UpdateError.replacementFailed
    }
}

private func reinstallDaemon(with binaryURL: URL) {
    let install = Process()
    install.executableURL = binaryURL
    install.arguments = ["--install"]

    do {
        try install.run()
        install.waitUntilExit()
        if install.terminationStatus != 0 {
            print("devkat-push: updated binary, but daemon refresh failed. Run: devkat-push --install")
        }
    } catch {
        print("devkat-push: updated binary, but daemon refresh failed. Run: devkat-push --install")
    }
}

private func currentExecutableURL() throws -> URL {
    let fileManager = FileManager.default
    let executable = CommandLine.arguments[0]

    if executable.contains("/") {
        let path = executable.hasPrefix("/")
            ? executable
            : fileManager.currentDirectoryPath + "/" + executable
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }

    let pathEntries = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
    for entry in pathEntries {
        let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(executable)
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.resolvingSymlinksInPath()
        }
    }

    throw UpdateError.executableNotFound
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("devkat-push-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func normalizedVersion(_ version: String) -> String {
    version.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"^v"#, with: "", options: [.regularExpression, .caseInsensitive])
}

private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
    let left = lhs.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
    let right = rhs.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
    let count = max(left.count, right.count)

    for index in 0..<count {
        let diff = (left.indices.contains(index) ? left[index] : 0) - (right.indices.contains(index) ? right[index] : 0)
        if diff != 0 { return diff }
    }

    return 0
}
