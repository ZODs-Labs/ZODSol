import AppKit
import Foundation

/// Shared thumbnail pipeline for asset rows and NFT tiles. Pulls bytes through
/// a configured `URLSession` whose `URLCache` holds the HTTP body on disk,
/// keeps decoded `NSImage`s in an `NSCache` so re-renders never touch the
/// network and dedupes concurrent requests for the same URL through a
/// per-URL `Task` map.
///
/// Construction is intentionally a normal initializer - we own one loader in
/// `StatusItemController` and inject it through SwiftUI's environment, so
/// previews and tests can substitute their own (or omit it entirely).
public actor ImageLoader {
    private let memoryCache: NSCache<NSURL, ImageBox>
    private let session: URLSession
    private var inflight: [URL: Task<ImageBox?, Never>] = [:]

    public init(
        memoryCapacityBytes: Int = 32 * 1_048_576,
        diskCapacityBytes: Int = 256 * 1_048_576,
        diskCacheDirectoryName: String = "dev.zods.zodsol/images")
    {
        let urlCache = URLCache(
            memoryCapacity: memoryCapacityBytes,
            diskCapacity: diskCapacityBytes,
            directory: Self.cacheDirectory(named: diskCacheDirectoryName))
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)

        let cache = NSCache<NSURL, ImageBox>()
        cache.totalCostLimit = memoryCapacityBytes
        cache.countLimit = 512
        self.memoryCache = cache
    }

    /// Returns the first decoded image found in cache, or the result of
    /// fetching candidates in order. A nil result means every candidate
    /// failed (4xx/5xx, transport error or undecodable bytes).
    public func image(for url: URL, fallbacks: [URL] = []) async -> NSImage? {
        let candidates = [url] + fallbacks
        for candidate in candidates {
            if let cached = self.memoryCache.object(forKey: candidate as NSURL) {
                return cached.image
            }
        }
        for candidate in candidates {
            if let image = await self.fetch(candidate) {
                return image
            }
        }
        return nil
    }

    public func evictAll() {
        self.memoryCache.removeAllObjects()
        self.session.configuration.urlCache?.removeAllCachedResponses()
    }

    // MARK: - Private

    private func fetch(_ url: URL) async -> NSImage? {
        if let inflight = self.inflight[url] {
            return await inflight.value?.image
        }
        let task = Task<ImageBox?, Never> { [session = self.session] in
            await Self.download(url: url, session: session)
        }
        self.inflight[url] = task
        let box = await task.value
        self.inflight[url] = nil
        if let box {
            self.memoryCache.setObject(box, forKey: url as NSURL, cost: box.byteSize)
        }
        return box?.image
    }

    private static func download(url: URL, session: URLSession) async -> ImageBox? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = NSImage(data: data)
            else { return nil }
            return ImageBox(image: image, byteSize: data.count)
        } catch {
            return nil
        }
    }

    private static func cacheDirectory(named: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(named, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// `NSImage` is not `Sendable`; the box is the bridge between the off-actor
/// download task and the actor's cache. After construction the image is read
/// only, which `NSImage` supports across threads.
final class ImageBox: @unchecked Sendable {
    let image: NSImage
    let byteSize: Int

    init(image: NSImage, byteSize: Int) {
        self.image = image
        self.byteSize = byteSize
    }
}
