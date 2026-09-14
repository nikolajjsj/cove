import Foundation
import JellyfinAPI
import MediaServerKit
import Models

extension JellyfinServerProvider: CatalogSyncSource {
    // `libraries()` is the MediaServerProvider method; it satisfies this protocol too.

    public func catalogDetail(id: String) async throws -> MediaItem {
        try await item(id: ItemID(id))
    }

    public func collectionMemberIds(collectionId: String) async throws -> [String] {
        let (client, userId) = try authenticatedClient()
        let (result, _) = try await client.getCatalogItems(
            userId: userId,
            queryItems: [
                URLQueryItem(name: "ParentId", value: collectionId),
                URLQueryItem(name: "Fields", value: ""),
                URLQueryItem(name: "EnableImages", value: "false"),
                URLQueryItem(name: "EnableUserData", value: "false"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ])
        return (result.items ?? []).compactMap(\.id)
    }

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

    // MARK: - User-data sweeps

    public func resumeUserData() async throws -> [CatalogUserDataRow] {
        let (client, userId) = try authenticatedClient()
        let result = try await client.getResumeItems(userId: userId, mediaTypes: ["Video"], limit: 100)
        return Self.userDataRows(result.items ?? [])
    }

    public func favoriteIds() async throws -> Set<String> {
        var ids = Set<String>()
        var index = 0
        var total = 0
        repeat {
            let (result, _) = try await catalogClient().getCatalogItems(
                userId: try authenticatedClient().1,
                queryItems: [
                    URLQueryItem(name: "Recursive", value: "true"),
                    URLQueryItem(name: "IsFavorite", value: "true"),
                    URLQueryItem(name: "Fields", value: ""),
                    URLQueryItem(name: "EnableImages", value: "false"),
                    URLQueryItem(name: "EnableUserData", value: "false"),
                    URLQueryItem(name: "StartIndex", value: String(index)),
                    URLQueryItem(name: "Limit", value: "500"),
                    URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
                ])
            let page = (result.items ?? []).compactMap(\.id)
            ids.formUnion(page)
            total = result.totalRecordCount ?? 0
            index += page.count
            if page.isEmpty { break }
        } while index < total
        return ids
    }

    public func recentlyPlayedUserData(limit: Int) async throws -> [CatalogUserDataRow] {
        let (client, userId) = try authenticatedClient()
        let (result, _) = try await client.getCatalogItems(
            userId: userId,
            queryItems: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IsPlayed", value: "true"),
                URLQueryItem(name: "SortBy", value: "DatePlayed"),
                URLQueryItem(name: "SortOrder", value: "Descending"),
                URLQueryItem(name: "Fields", value: ""),
                URLQueryItem(name: "EnableImages", value: "false"),
                URLQueryItem(name: "Limit", value: String(limit)),
            ])
        return Self.userDataRows(result.items ?? [])
    }

    public func userDataPage(
        libraryId: String, itemTypes: [String], startIndex: Int, limit: Int
    ) async throws -> (rows: [CatalogUserDataRow], totalCount: Int) {
        let (client, userId) = try authenticatedClient()
        let (result, _) = try await client.getCatalogItems(
            userId: userId,
            queryItems: [
                URLQueryItem(name: "ParentId", value: libraryId),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: itemTypes.joined(separator: ",")),
                URLQueryItem(name: "Fields", value: ""),
                URLQueryItem(name: "EnableImages", value: "false"),
                URLQueryItem(name: "SortBy", value: "DateCreated"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "StartIndex", value: String(startIndex)),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true"),
            ])
        return (Self.userDataRows(result.items ?? []), result.totalRecordCount ?? 0)
    }

    private func catalogClient() throws -> JellyfinAPIClient { try authenticatedClient().0 }

    private static func userDataRows(_ dtos: [BaseItemDto]) -> [CatalogUserDataRow] {
        dtos.compactMap { dto in
            guard let id = dto.id, let ud = dto.userData else { return nil }
            return CatalogUserDataRow(itemId: id, userData: JellyfinMapper.mapUserData(ud))
        }
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
