import Foundation
import JellyfinAPI
import Models

/// `BaseItemDto` → `CatalogEntry`. Lean by construction: it reads only the fields
/// the catalogue tier stores, so a page fetched with the catalogue field set maps
/// without anything being silently nil.
enum JellyfinCatalogMapper {
    /// The `Fields` a catalogue page asks for. Anything not here is detail tier.
    static let fields: [String] = [
        "SortName", "DateCreated", "PremiereDate", "ProductionYear", "CommunityRating",
        "CriticRating", "OfficialRating", "RunTimeTicks", "Genres", "GenreItems", "Studios",
        "ParentId", "UserData",
    ]

    static func entry(from dto: BaseItemDto, libraryId: String) -> CatalogEntry? {
        guard let id = dto.id, let name = dto.name, let type = dto.type else { return nil }
        // A row with no DateCreated cannot be placed in the bootstrap order; the
        // server always sends one, so treat its absence as a malformed item.
        guard let created = dto.dateCreated.flatMap(JellyfinMapper.parseDate) else { return nil }

        let genres: [CatalogGenre]
        if let items = dto.genreItems, !items.isEmpty {
            genres = items.compactMap { g in
                guard let gid = g.id, let gname = g.name else { return nil }
                return CatalogGenre(id: gid, name: gname)
            }
        } else {
            // Older servers send names only; use the name as the id.
            genres = (dto.genres ?? []).map { CatalogGenre(id: $0, name: $0) }
        }

        return CatalogEntry(
            id: id,
            libraryId: libraryId,
            parentId: dto.parentId,
            seriesId: dto.seriesId,
            seasonId: dto.seasonId,
            type: type,
            mediaType: JellyfinMapper.mapMediaType(type),
            name: name,
            sortName: dto.sortName ?? name,
            productionYear: dto.productionYear,
            premiereDate: dto.premiereDate.flatMap(JellyfinMapper.parseDate),
            dateCreated: created,
            runTimeTicks: dto.runTimeTicks,
            communityRating: dto.communityRating,
            criticRating: dto.criticRating,
            officialRating: dto.officialRating,
            indexNumber: dto.indexNumber,
            parentIndexNumber: dto.parentIndexNumber,
            seriesName: dto.seriesName,
            imageTags: JellyfinMapper.mapImageTags(dto),
            genres: genres,
            studios: (dto.studios ?? []).compactMap(\.name),
            userData: dto.userData.map(JellyfinMapper.mapUserData))
    }
}
