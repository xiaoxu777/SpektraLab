//  Theme.swift — shared colours, type and spacing for the Mac interface.
//
//  Views use these tokens so a theme change reaches the whole page. Appearance selects the light
//  or dark values. Type uses fixed system-font sizes; Settings › Appearance scales the complete
//  interface through InterfaceScale, keeping controls and their contents together.

import SwiftUI
import UIKit

enum Theme {

    // MARK: colours (gen.py's names in the comments)

    /// `BG` — the page. The host's ground is black, not the desktop's grey
    /// canvas surround: an OLED page under a photograph. A Mac's and a window's
    /// is a dark blue-grey (`tone`): the owner, 2026-10-24, "the current black
    /// background makes it hard to tell the shadow around the edges" — lighter
    /// than black, darker than Capture One's greys (#2B2D30–#333). Since the same
    /// day it may be chosen there, per mode (Settings › Appearance, `AppBackground`),
    /// and the surfaces marked `ground` below follow it.
    static let background = ground(dark: 0x1C1D20, light: 0xF4F4F5)
    /// FilmLab 暗房 (the owner chose design A, 2026-11-23): the picture's surround — darker than the column in Dark, a
    /// mid grey in Light so a photograph never looks dim against white. Follows a chosen ground.
    static let well = ground(dark: 0x111214, light: 0xD9DADD)
    /// The window's bar and the filmstrip under the picture (design A).
    static let chrome = ground(dark: 0x1A1B1E, light: 0xEFEFF1)
    /// `CARD` — `Theme.card`: round buttons, chips, cards, grouped rows.
    static let card = ground(dark: 0x28292D, light: 0xE3E4E7)
    /// `PLOT` — `Theme.plot`: the Latitude card and plot grounds.
    static let plot = ground(dark: 0x232528, light: 0xFBFBFC)
    /// `SHEET` — a sheet's surface over the black app. The plot colour, on purpose.
    static let sheet = plot
    /// `RULE` — `Theme.rule`: hairlines.
    static let rule = ground(dark: 0x2D2F34, light: 0xD2D4D8)
    /// `FIELD` — a segmented control's track inside a grouped row.
    static let field = ground(dark: 0x323439, light: 0xD8DADE)
    /// `PANEL` — in-frame panels and banners.
    static let panel = ground(dark: 0x151618, light: 0xE6E7EA)
    /// A popover's or a toast's surface: the copy and paste panels, the notes that say what just happened (design A).
    static let popover = tone(dark: 0x26282C, light: 0xFFFFFF)
    /// `TEXT` — primary text and glyphs.
    static let text = tone(dark: 0xECEAE6, light: 0x1C1D20)
    /// `TEXT2` — `Theme.secondaryText`.
    static let secondaryText = tone(dark: 0xA6A39D, light: 0x55575D)
    /// `DIM` — captions and anything the page is not asking you to read.
    static let dim = tone(dark: 0x7E7C78, light: 0x7A7C82)
    /// A note's second, quieter paragraph (`#6d6d6b` in gen_flow.py).
    static let faint = tone(dark: 0x5E5D5A, light: 0x9A9CA1)
    /// `ACCENT` — **actions and state only**: Process, Export, develop
    /// progress, the selected lens, the level. Selection is never accent.
    static let accent = tone(dark: 0xE8A33D, light: 0xB8741A)
    /// `SEL` — selection: the white capsule.
    static let selection = tone(dark: 0xFFFFFF, light: 0x1C1D20)
    /// `ONSEL` — text on a selection capsule, and on an accent button.
    static let onSelection = tone(dark: 0x0F0E0E, light: 0xFFFFFF)
    /// `SELFRAME` — selection as a frame: a chosen card, a chosen tile.
    static let selectionFrame = tone(dark: 0xFAF8F4, light: 0x1C1D20)
    /// `DANGER` — remove, missing, not connected.
    static let danger = tone(dark: 0xE8796B, light: 0xC4473A)
    /// The Latitude meter (the desktop's v4 graph).
    static let latitudeInside = tone(dark: 0x9C9C9A, light: 0x8C9096)
    static let latitudeInsideEdge = tone(dark: 0xD6D5D2, light: 0x5B5F66)
    static let latitudeBeyond = ground(dark: 0x41464E, light: 0xCCD0D6)
    /// An off switch's track (the operating system's own `#3A3A3C`).
    /// A slider's round knob (design A): near-white on both grounds, lifted by its shadow.
    static let knob = tone(dark: 0xF2F0EC, light: 0xFFFFFF)
    /// A star not given, in the grid's five (design A): seen on the well in both modes, quieter than a given one.
    static let starOff = tone(dark: 0x3A3C41, light: 0xB4B6BB)
    static let toggleOff = ground(dark: 0x44464B, light: 0xC9CBCF)
    /// The film strip, as an inverted overscan reads (research/overscan/recreate).
    static let rebate = Color(hex: 0x1B120C)
    static let perforation = Color(hex: 0x010102)
    static let edgeInk = Color(hex: 0xF2B24E)

    /// The colour labels, as the strip, the grid and the info column draw them (design A): red, yellow, green, blue,
    /// purple. The same in both modes, so a label reads the same everywhere.
    static let labelRed = Color(hex: 0xE5484D)
    static let labelYellow = Color(hex: 0xF5C518)
    static let labelGreen = Color(hex: 0x3DB86B)
    static let labelBlue = Color(hex: 0x3E8EF7)
    static let labelPurple = Color(hex: 0xA06CE8)

    /// `SCRIM` — the black over whatever a sheet or a menu covers.
    static let scrimOpacity: Double = 0.62
    /// The desktop's one rule for a control that cannot be used: the whole
    /// row, label and control together.
    static let disabledOpacity: Double = 0.38

    // MARK: type

    enum Font {
        /// The one way a view gets a font: the drawing's size and weight.
        static func ui(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
        /// A reading in figures (EV, K, px): SF Mono, so columns of numbers line up (design A).
        static func mono(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// A page's own large title: Settings, Sources, Storage.
        static let pageTitle = ui(30, .bold)
        /// A sheet's title.
        static let sheetTitle = ui(19, .bold)
        /// A sheet's line under its title.
        static let sheetSub = ui(12.5)
        /// A row's label where the row is a control (rulers, export rows).
        static let rowLabel = ui(14, .semibold)
        /// A row's label in a grouped list (Settings, Info).
        static let listLabel = ui(15)
        /// A row's value at the trailing edge.
        static let rowValue = ui(14)
        /// `section_label`: small capitals over a group.
        static let sectionLabel = ui(11, .semibold)
        /// `note`: the paragraph under a group.
        static let note = ui(11.5)
        /// The status line under the picture.
        static let status = ui(12)
        /// A chip, off and on.
        static let chip = ui(12.5)
        static let chipOn = ui(12.5, .semibold)
        /// A develop tab, off and on.
        static let tab = ui(13)
        static let tabOn = ui(13, .semibold)
        /// A capsule button's label.
        static let button = ui(16, .semibold)
    }

    // MARK: metrics (points; the drawings are 1 unit = 1 pt)

    enum Metric {
        /// The drawings' page: reference device. A layout may assume nothing
        /// wider or narrower than a host; it must not assume exactly this.
        static let designWidth: CGFloat = 393
        static let designHeight: CGFloat = 852
        /// A page's side margin.
        static let margin: CGFloat = 16
        /// A grouped box's corner, and a sheet's top corners.
        static let groupRadius: CGFloat = 12
        static let sheetRadius: CGFloat = 26
        /// A film or paper card.
        static let cardRadius: CGFloat = 10
        /// Round buttons: the library's bar, the develop page's actions.
        static let roundButton: CGFloat = 44
        /// The Mac develop page's picture bar — its circles, and the Export capsule's height (the owner,
        /// 2026-10-26: in full screen the row "touches the top edge of the display" and wanted smaller).
        /// One number moves every interface scale, which multiplies the whole page (`InterfaceScale`) —
        /// 80, 100, 120 and 150 % all draw it 36 × f. 44 → 36; the row stays 44 pt tall because the
        /// bar's back button is, so the 36 pt discs sit 4 pt inside it.
        static let barRound: CGFloat = 36
        /// The capsule action button: Export, Next, Done.
        static let capsuleHeight: CGFloat = 44
        /// A hairline.
        static let rule: CGFloat = 1
        /// The picture on the develop page and the library's top frame: 3:2 at
        /// the drawing's width.
        static let canvasAspect: CGFloat = 393.0 / 262.0
        /// The library grid.
        static let gridGap: CGFloat = 2
        static let gridColumns = 3
    }
}

extension Theme {
    /// a token whose value is `dark` in Dark
    /// Mode and `light` in Light Mode (浅色模式, `AppAppearance`), resolved where it is drawn, by the traits
    /// it is drawn with.
    static func tone(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .light ? light : dark)
        })
    }

    /// a surface that **follows the page's
    /// ground** chosen in Settings › Appearance (`AppBackground`): `dark` and `light` are its values on the
    /// default grounds, and on a chosen ground it is derived from them (`AppBackground.derive`), so the
    /// panel, card, plot, rule and wall keep their places around any ground. At the default ground,
    /// exactly `tone`.
    static func ground(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            _ = traits[AppGroundTrait.self]     // a chosen ground's change is a change of these traits
            let isLight = traits.userInterfaceStyle == .light
            let standard = isLight ? AppBackground.lightDefault : AppBackground.darkDefault
            let token = isLight ? light : dark
            return UIColor(hex: AppBackground.derive(token, standard: standard, ground: AppBackground.ground(light: isLight),
                                                     light: isLight))
        })
    }
}

extension UIColor {
    /// `0xRRGGBB`, sRGB, as `Color(hex:)`.
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// `0xRRGGBB`, sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// `"#rrggbb"`, as the stock catalogue stores a swatch. Falls back to the
    /// card colour, which is visibly "no swatch" rather than a wrong one.
    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if let v = UInt32(s, radix: 16), s.count == 6 { self.init(hex: v) } else { self = Theme.card }
    }

    /// A point on the line between two colours, in sRGB, as `gen.lerp_hex`.
    static func lerp(_ a: UInt32, _ b: UInt32, _ u: Double) -> Color {
        let t = min(max(u, 0), 1)
        func ch(_ shift: UInt32) -> Double {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return (x + (y - x) * t) / 255
        }
        return Color(.sRGB, red: ch(16), green: ch(8), blue: ch(0), opacity: 1)
    }
}

extension View {
    /// The desktop's rule for a control that cannot be used.
    func rowEnabled(_ enabled: Bool) -> some View {
        opacity(enabled ? 1 : Theme.disabledOpacity).allowsHitTesting(enabled)
    }
}
