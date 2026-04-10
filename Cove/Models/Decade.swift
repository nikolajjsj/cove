import Foundation

/// A decade range used for year-based filtering.
enum Decade: String, CaseIterable, Equatable {
    case twenties = "2020s"
    case tens = "2010s"
    case noughties = "2000s"
    case nineties = "1990s"
    case eighties = "1980s"

    var years: [Int] {
        switch self {
        case .twenties: Array(2020...2029)
        case .tens: Array(2010...2019)
        case .noughties: Array(2000...2009)
        case .nineties: Array(1990...1999)
        case .eighties: Array(1980...1989)
        }
    }
}
