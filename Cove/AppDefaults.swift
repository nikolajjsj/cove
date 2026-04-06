import Defaults
import Foundation

extension Defaults.Keys {
    /// Whether downloads are allowed over cellular connections.
    /// When `false` (the default), downloads only proceed on WiFi.
    static let downloadOverCellular = Key<Bool>("downloadOverCellular", default: false)
}
