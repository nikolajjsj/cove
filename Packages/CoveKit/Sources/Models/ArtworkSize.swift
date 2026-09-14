import Foundation

/// The sizes the app asks the server for. Three, on purpose.
///
/// An image request is cached by its URL, and the URL carries the size. Every
/// view that shows a poster asks for *this* poster size, so one download serves
/// the grid, the search row, the detail page and the offline prefetch alike.
/// Adding a fourth size adds a fourth copy of every image on disk.
public enum ArtworkSize {
    /// Portrait posters — cards, rows, detail pages. Displayed at ≤ 150 pt.
    public static let poster = CGSize(width: 300, height: 450)
    /// Landscape cards — Continue Watching, episode thumbnails.
    public static let landscape = CGSize(width: 480, height: 270)
    /// Full-width heroes — detail backdrops, episode stills.
    public static let backdrop = CGSize(width: 1280, height: 720)
}
