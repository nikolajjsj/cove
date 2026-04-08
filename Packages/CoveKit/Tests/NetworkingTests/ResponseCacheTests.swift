import Foundation
import Testing

@testable import Networking

@Suite("ResponseCache")
struct ResponseCacheTests {

    @Test("Returns nil for missing key")
    func cacheMiss() async {
        let cache = ResponseCache()
        let result = await cache.get(forKey: "missing", maxAge: 60)
        #expect(result == nil)
    }

    @Test("Returns cached data within TTL")
    func cacheHit() async {
        let cache = ResponseCache()
        let data = Data("hello".utf8)
        await cache.set(data, forKey: "test")
        let result = await cache.get(forKey: "test", maxAge: 60)
        #expect(result == data)
    }

    @Test("Returns nil for expired entry")
    func expiredEntry() async {
        let cache = ResponseCache()
        let data = Data("old".utf8)
        await cache.set(data, forKey: "test")
        // maxAge of 0 means any entry is stale
        let result = await cache.get(forKey: "test", maxAge: 0)
        #expect(result == nil)
    }

    @Test("Remove specific key")
    func removeKey() async {
        let cache = ResponseCache()
        await cache.set(Data("a".utf8), forKey: "a")
        await cache.set(Data("b".utf8), forKey: "b")
        await cache.remove(forKey: "a")
        #expect(await cache.get(forKey: "a", maxAge: 60) == nil)
        #expect(await cache.get(forKey: "b", maxAge: 60) != nil)
    }

    @Test("Remove all matching substring")
    func removeAllMatching() async {
        let cache = ResponseCache()
        await cache.set(Data("1".utf8), forKey: "/items/abc/details")
        await cache.set(Data("2".utf8), forKey: "/items/abc/similar")
        await cache.set(Data("3".utf8), forKey: "/items/xyz/details")
        await cache.removeAll(matching: "abc")
        #expect(await cache.count == 1)
        #expect(await cache.get(forKey: "/items/xyz/details", maxAge: 60) != nil)
    }

    @Test("Remove all clears cache")
    func removeAll() async {
        let cache = ResponseCache()
        await cache.set(Data("a".utf8), forKey: "a")
        await cache.set(Data("b".utf8), forKey: "b")
        await cache.removeAll()
        #expect(await cache.count == 0)
    }

    @Test("Evicts oldest entries when at capacity")
    func eviction() async {
        let cache = ResponseCache(maxEntries: 4)
        // Fill to capacity
        for i in 0..<4 {
            await cache.set(Data("v\(i)".utf8), forKey: "key\(i)")
        }
        #expect(await cache.count == 4)

        // Adding one more should trigger eviction of oldest 25% (1 entry)
        await cache.set(Data("new".utf8), forKey: "newKey")
        #expect(await cache.count <= 4)
        // The newest entry should still be present
        #expect(await cache.get(forKey: "newKey", maxAge: 60) != nil)
    }

    @Test("Count reflects current entries")
    func countAccuracy() async {
        let cache = ResponseCache()
        #expect(await cache.count == 0)
        await cache.set(Data("a".utf8), forKey: "a")
        #expect(await cache.count == 1)
        await cache.set(Data("b".utf8), forKey: "b")
        #expect(await cache.count == 2)
        await cache.remove(forKey: "a")
        #expect(await cache.count == 1)
    }

    @Test("Overwriting a key replaces the value")
    func overwriteKey() async {
        let cache = ResponseCache()
        let original = Data("original".utf8)
        let replacement = Data("replacement".utf8)
        await cache.set(original, forKey: "key")
        await cache.set(replacement, forKey: "key")
        let result = await cache.get(forKey: "key", maxAge: 60)
        #expect(result == replacement)
        #expect(await cache.count == 1)
    }

    @Test("Expired entry is removed eagerly on get")
    func expiredEntryRemovedOnGet() async {
        let cache = ResponseCache()
        await cache.set(Data("stale".utf8), forKey: "stale")
        // Requesting with maxAge 0 should remove the entry
        let _ = await cache.get(forKey: "stale", maxAge: 0)
        #expect(await cache.count == 0)
    }

    @Test("Remove matching does not affect non-matching keys")
    func removeMatchingSelectivity() async {
        let cache = ResponseCache()
        await cache.set(Data("1".utf8), forKey: "/users/123/items")
        await cache.set(Data("2".utf8), forKey: "/users/456/items")
        await cache.set(Data("3".utf8), forKey: "/system/info")
        await cache.removeAll(matching: "/users/123")
        #expect(await cache.count == 2)
        #expect(await cache.get(forKey: "/users/123/items", maxAge: 60) == nil)
        #expect(await cache.get(forKey: "/users/456/items", maxAge: 60) != nil)
        #expect(await cache.get(forKey: "/system/info", maxAge: 60) != nil)
    }

    @Test("Remove matching with no matches does nothing")
    func removeMatchingNoMatches() async {
        let cache = ResponseCache()
        await cache.set(Data("a".utf8), forKey: "alpha")
        await cache.set(Data("b".utf8), forKey: "beta")
        await cache.removeAll(matching: "zzz_no_match")
        #expect(await cache.count == 2)
    }

    @Test("Large data can be cached and retrieved")
    func largeData() async {
        let cache = ResponseCache()
        let largeData = Data(repeating: 0xAB, count: 1_000_000)
        await cache.set(largeData, forKey: "large")
        let result = await cache.get(forKey: "large", maxAge: 60)
        #expect(result == largeData)
    }

    @Test("Eviction preserves newest entries")
    func evictionPreservesNewest() async {
        let cache = ResponseCache(maxEntries: 4)

        // Add entries with slight delay to ensure ordering
        for i in 0..<4 {
            await cache.set(Data("v\(i)".utf8), forKey: "key\(i)")
        }

        // Trigger eviction by adding a 5th entry
        await cache.set(Data("v4".utf8), forKey: "key4")

        // The newest entries should be present
        let newestResult = await cache.get(forKey: "key4", maxAge: 60)
        #expect(newestResult != nil)

        // Count should not exceed maxEntries
        #expect(await cache.count <= 4)
    }

    @Test("Empty cache removeAll does not crash")
    func removeAllEmpty() async {
        let cache = ResponseCache()
        await cache.removeAll()
        #expect(await cache.count == 0)
    }

    @Test("Remove non-existent key does not crash")
    func removeNonExistent() async {
        let cache = ResponseCache()
        await cache.remove(forKey: "does_not_exist")
        #expect(await cache.count == 0)
    }

    @Test("Same key set multiple times only counts once")
    func duplicateKeyCounting() async {
        let cache = ResponseCache()
        await cache.set(Data("v1".utf8), forKey: "key")
        await cache.set(Data("v2".utf8), forKey: "key")
        await cache.set(Data("v3".utf8), forKey: "key")
        #expect(await cache.count == 1)
    }

    @Test("Cache with maxEntries of 1 always keeps the latest")
    func singleEntryCache() async {
        let cache = ResponseCache(maxEntries: 1)
        await cache.set(Data("first".utf8), forKey: "a")
        #expect(await cache.count == 1)

        await cache.set(Data("second".utf8), forKey: "b")
        #expect(await cache.count <= 1)

        // The most recently set entry should be retrievable
        let result = await cache.get(forKey: "b", maxAge: 60)
        #expect(result == Data("second".utf8))
    }
}
