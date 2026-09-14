import Foundation
import JellyfinAPI
import MediaServerKit
import Models

extension JellyfinServerProvider: CatalogSyncSource {
    public func catalogPage(
        libraryId: String, itemTypes: [String], startIndex: Int, limit: Int
    ) async throws -> CatalogPage {
        try await fetchPage(
            libraryId: libraryId, itemTypes: itemTypes, startIndex: startIndex, limit: limit,
            extra: [])
    }

    public func catalogChanges(
        libraryId: String, itemTypes: [String], since: Date, startIndex: Int, limit: Int
    ) async throws -> CatalogPage {
        try await fetchPage(
            libraryId: libraryId, itemTypes: itemTypes, startIndex: startIndex, limit: limit,
            extra: [URLQueryItem(name: "MinDateLastSaved", value: since.formatted(.iso8601))])
    }

    public func catalogIds(
        libraryId: String, itemTypes: [String], startIndex: Int, limit: Int
    ) async throws -> CatalogIdPage {
        let (client, userId) = try authenticatedClient()
        let (result, date) = try await client.getCatalogItems(
            userId: userId,
            queryItems: [
                URLQueryItem(name: "ParentId", value: libraryId),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: itemTypes.joined(separator: ",")),
                URLQueryItem(name: "Fields", value: ""),
                URLQueryItem(name: "EnableImages", value: "false"),
                URLQueryItem(name: "EnableUserData", value: "false"),
                URLQueryItem(name: "SortBy", value: "DateCreated"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            ])
        return CatalogIdPage(
            ids: (result.items ?? []).compactMap(\.id),
            totalCount: result.totalRecordCount ?? 0,
            serverDate: date)
    }

    public func catalogEntries(ids: [String], libraryId: String) async throws -> [CatalogEntry] {
        guard !ids.isEmpty else { return [] }
        let (client, userId) = try authenticatedClient()
        var out: [CatalogEntry] = []
        for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
            let (result, _) = try await client.getCatalogItems(
                userId: userId,
                queryItems: [
                    URLQueryItem(name: "Ids", value: chunk.joined(separator: ",")),
                    URLQueryItem(name: "Fields", value: JellyfinCatalogMapper.fields.joined(separator: ",")),
                ])
            out += (result.items ?? []).compactMap {
                JellyfinCatalogMapper.entry(from: $0, libraryId: libraryId)
            }
        }
        return out
    }

    private func fetchPage(
        libraryId: String, itemTypes: [String], startIndex: Int, limit: Int, extra: [URLQueryItem]
    ) async throws -> CatalogPage {
        let (client, userId) = try authenticatedClient()
        let (result, date) = try await client.getCatalogItems(
            userId: userId,
            queryItems: [
                URLQueryItem(name: "ParentId", value: libraryId),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: itemTypes.joined(separator: ",")),
                URLQueryItem(name: "Fields", value: JellyfinCatalogMapper.fields.joined(separator: ",")),
                URLQueryItem(name: "SortBy", value: "DateCreated"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            ] + extra)
        return CatalogPage(
            entries: (result.items ?? []).compactMap {
                JellyfinCatalogMapper.entry(from: $0, libraryId: libraryId)
            },
            totalCount: result.totalRecordCount ?? 0,
            serverDate: date)
    }

}
