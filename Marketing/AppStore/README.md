# App Store assets

`listing.md` holds the keywords, description, promotional text and subtitle,
with the character count for each field.

`screenshots/` holds captures at the two sizes App Store Connect asks for:

| Folder        | Device             | Pixels      |
|---------------|--------------------|-------------|
| `iphone-6.7`  | iPhone 14 Plus     | 1284 × 2778 |
| `ipad-13`     | iPad Pro 13-inch   | 2064 × 2752 |

Regenerate with `Tools/capture-screenshots.sh <out-dir> <device>`; read the top
of that script first for what it can and cannot reach.

These are captured against the public Jellyfin demo server, never a personal
one — a listing should not ship somebody's actual library.
