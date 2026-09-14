import Foundation

/// One genre as the server names it, with the id it uses for filtering.
public struct CatalogGenre: Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The lean, catalogue-tier view of an item — everything grids, rails, filters and
/// search need, and nothing they do not.
///
/// This is what the sync engine consumes and what `catalog_items` stores. It is
/// deliberately not `MediaItem`: that type carries overview, people, media streams
/// and chapters, which are detail-tier and fetched lazily. Keeping the two apart is
/// the storage argument in `.agents/features/local-first-sync.md` §5.2.
public struct CatalogEntry: Hashable, Sendable {
    public let id: String
    /// The top-level library view this item was reached through. Stamped by the
    /// sync engine from the pass it came from; the server does not put it on the item.
    public var libraryId: String
    public let parentId: String?
    public let seriesId: String?
    public let seasonId: String?
    /// The server's own type string — `Movie`, `Series`, `Season`, `Episode`, `BoxSet`.
    public let type: String
    public let mediaType: MediaType
    public let name: String
    public let sortName: String
    public let productionYear: Int?
    public let premiereDate: Date?
    public let dateCreated: Date
    public let runTimeTicks: Int64?
    public let communityRating: Double?
    public let criticRating: Double?
    public let officialRating: String?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let seriesName: String?
    public let imageTags: [ImageType: String]?
    public let genres: [CatalogGenre]
    public let studios: [String]
    public let userData: UserData?

    public init(
        id: String,
        libraryId: String,
        parentId: String? = nil,
        seriesId: String? = nil,
        seasonId: String? = nil,
        type: String,
        mediaType: MediaType,
        name: String,
        sortName: String,
        productionYear: Int? = nil,
        premiereDate: Date? = nil,
        dateCreated: Date,
        runTimeTicks: Int64? = nil,
        communityRating: Double? = nil,
        criticRating: Double? = nil,
        officialRating: String? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        seriesName: String? = nil,
        imageTags: [ImageType: String]? = nil,
        genres: [CatalogGenre] = [],
        studios: [String] = [],
        userData: UserData? = nil
    ) {
        self.id = id
        self.libraryId = libraryId
        self.parentId = parentId
        self.seriesId = seriesId
        self.seasonId = seasonId
        self.type = type
        self.mediaType = mediaType
        self.name = name
        self.sortName = sortName
        self.productionYear = productionYear
        self.premiereDate = premiereDate
        self.dateCreated = dateCreated
        self.runTimeTicks = runTimeTicks
        self.communityRating = communityRating
        self.criticRating = criticRating
        self.officialRating = officialRating
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.seriesName = seriesName
        self.imageTags = imageTags
        self.genres = genres
        self.studios = studios
        self.userData = userData
    }
}

/// A page of catalogue entries with the server's clock at the moment it answered.
///
/// `serverDate` comes from the HTTP `Date` header. It is the only server timestamp
/// a client can obtain — `DateLastSaved` is requestable but never returned — and it
/// is the cursor for the next delta. Never substitute the device clock.
public struct CatalogPage: Sendable {
    public let entries: [CatalogEntry]
    public let totalCount: Int
    public let serverDate: Date?

    public init(entries: [CatalogEntry], totalCount: Int, serverDate: Date?) {
        self.entries = entries
        self.totalCount = totalCount
        self.serverDate = serverDate
    }
}

/// A page of bare ids, for reconciliation.
public struct CatalogIdPage: Sendable {
    public let ids: [String]
    public let totalCount: Int
    public let serverDate: Date?

    public init(ids: [String], totalCount: Int, serverDate: Date?) {
        self.ids = ids
        self.totalCount = totalCount
        self.serverDate = serverDate
    }
}

/// One item's user data as a sweep returns it.
public struct CatalogUserDataRow: Sendable, Equatable {
    public let itemId: String
    public let userData: UserData

    public init(itemId: String, userData: UserData) {
        self.itemId = itemId
        self.userData = userData
    }
}
