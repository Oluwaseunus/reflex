import Foundation

actor ArtworkDataCache {
    static let shared = ArtworkDataCache()

    private let maxItems = 128
    private var cachedData: [URL: Data] = [:]
    private var cacheOrder: [URL] = []
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    func data(for url: URL) async -> Data? {
        if let data = cachedData[url] {
            return data
        }
        if let task = inFlight[url] {
            return await task.value
        }

        let task = Task<Data?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }

        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil

        if let data {
            store(data, for: url)
        }

        return data
    }

    private func store(_ data: Data, for url: URL) {
        if cachedData[url] == nil {
            cacheOrder.append(url)
        }
        cachedData[url] = data

        while cacheOrder.count > maxItems, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cachedData.removeValue(forKey: oldest)
        }
    }
}
