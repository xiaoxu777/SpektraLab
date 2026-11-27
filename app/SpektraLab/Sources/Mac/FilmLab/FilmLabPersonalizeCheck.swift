//  FilmLabPersonalizeCheck.swift — screenshot launch arguments, in Debug and Release.
//
//  With --develop --frame NAME --filmlab-mode personalize:
//    --filmlab-edge "format=135;turn=across;numbers=reroll;camera=reroll;mode=strip"
//    --filmlab-edge off
//      format: FilmEdgeFormat.rawValue (135, 120_645, 8_super, 135_xpan, ...).
//      turn: across | upright | auto (forget the explicit orientation; follow the photo).
//      mode: strip | thin. Unknown keys/values are ignored; omitted fields stay as kept.
//      scan: clean | natural | strong (also writes that preset's fog and spool leaks).
//    --filmlab-open edge | edge-detail | date | mark
//      Expand and scroll to the section without changing its switch. edge-detail opens More details in 专业.
//    --filmlab-mark "text=xiaoxu 摄;style=hand;face=HanziPenSC-W3"
//      style: hand | print (default print); face is the handwriting PostScript name.
//    --filmlab-signature-pad [--filmlab-signature-demo]
//      Scroll to Watermark and open Draw one; demo also seeds a few fixed strokes, without saving them.
//  With --develop --frame NAME --filmlab-mode grade, in 专业 (filmlab.showAdvanced):
//    --filmlab-grade-tab effects --filmlab-grade-open format
//  Edge/text edits use the ordinary session history and persistence: launch in a scratch home/catalog.
//  No argument means no action. Each edit/presentation is consumed once per process, never once per view.

import CoreGraphics
import Foundation

@MainActor
enum FilmLabPersonalizeCheck {
    enum Section: String { case edge, edgeDetail = "edge-detail", date, mark }
    enum Action: Hashable { case edge, mark, scroll, signature, demo }
    private static var consumed: Set<Action> = []

    static let edge = FilmLabCheckArgs.value("--filmlab-edge")
    static let edgeFields = fields(edge)
    static let open = FilmLabCheckArgs.value("--filmlab-open").flatMap(Section.init(rawValue:))
    static let mark: FilmLabTextRecipe? = {
        let f = fields(FilmLabCheckArgs.value("--filmlab-mark"))
        guard let text = f["text"], !text.isEmpty else { return nil }
        let style = f["style"].flatMap(FilmLabTextStyle.init(rawValue:)) ?? .print
        return FilmLabTextRecipe(text: text, style: style,
                                 postScriptName: style == .hand ? (f["face"] ?? FilmLabHandwriting.faces[0].id) : nil)
    }()
    static let signatureDemo = CommandLine.arguments.contains("--filmlab-signature-demo")
    static let signaturePad = signatureDemo || CommandLine.arguments.contains("--filmlab-signature-pad")
    static let gradeTab = FilmLabCheckArgs.value("--filmlab-grade-tab") == "effects" ? FilmLabGradeTab.effects : nil
    static let gradeFormat = FilmLabCheckArgs.value("--filmlab-grade-open") == "format"

    static var scrollTarget: String? {
        // A pad must have its section in view even when no --filmlab-open was given.
        if signaturePad { return "watermark" }
        switch open {
        case .edge, .edgeDetail: return "film-edge"
        case .date: return "date-back"
        case .mark: return "watermark"
        case nil: return nil
        }
    }

    static func expands(_ id: String) -> Bool {
        if signaturePad, id == "watermark" { return true }
        switch open {
        case .edge, .edgeDetail: return id == "film-edge"
        case .date: return id == "date-back"
        case .mark: return id == "watermark"
        case nil: return false
        }
    }

    static func consume(_ action: Action) -> Bool { consumed.insert(action).inserted }

    /// Split only the first '=': spaces, Unicode and '=' inside text survive shell quoting.
    private static func fields(_ argument: String?) -> [String: String] {
        var result: [String: String] = [:]
        for part in (argument ?? "").split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            result[String(pair[0]).trimmingCharacters(in: .whitespacesAndNewlines)] =
                String(pair[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// The column is installed with the frame's session; let the page's open() and first layout finish first.
    static func settle(_ session: OpenFrameSession, frameID: LibraryFrame.ID) async -> Bool {
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return false }
        return !Task.isCancelled && session.frame?.id == frameID && !session.exportHolds()
    }

    static func applyEdge(_ session: OpenFrameSession, frame: LibraryFrame, body: Int) async {
        guard edge != nil, await settle(session, frameID: frame.id),
              session.edit.appliesFilm, frame.pair == nil, session.pair == nil, consume(.edge) else { return }
        let aspect = frame.originalSize.aspect
        let shownAspect = session.edit.geometry.quarterTurns % 2 == 0 ? aspect : 1 / max(aspect, 0.0001)
        session.change { edit in
            FilmLabEdgeSection.setFilmEdge(edge != "off", in: &edit, pictureAspect: shownAspect, body: body)
            guard edge != "off" else { return }
            if let raw = edgeFields["format"], let format = FilmEdgeFormat(rawValue: raw) {
                FilmLabEdgeSection.pick(format, in: &edit, pictureAspect: shownAspect)
            }
            if let turn = edgeFields["turn"], turn == "auto" || FilmEdgeOrientation(rawValue: turn) != nil {
                edit = FilmLabEdgeSection.oriented(edit, to: FilmEdgeOrientation(rawValue: turn),
                                                  source: CGSize(width: frame.originalSize.width, height: frame.originalSize.height))
            }
            if edgeFields["numbers"] == "reroll" { FilmLabEdgeSection.rollNumbers(in: &edit) }
            if edgeFields["camera"] == "reroll" { FilmLabEdgeSection.rollBody(in: &edit) }
            if let scan = edgeFields["scan"].flatMap(FilmEdgeScan.init(rawValue:)) { edit.filmEdge.chooseScan(scan) }
            switch edgeFields["mode"] {
            case "strip": edit.filmEdge.mode = .strip
            case "thin": edit.filmEdge.mode = .filed
            default: break
            }
        }
    }
}
