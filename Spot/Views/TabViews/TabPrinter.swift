//
//  TabPrinter.swift
//  Spot
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import SpotCore

/// The tab on paper: a PDF of one track in pages (the size the printer is set up for), black on white, with
/// the title, artist, tuning, capo and tempo at the top of the first page, the chords above the staff, and page
/// numbers. Drawn by the same code as the screen, so it lays out the same way.
@MainActor
enum TabPrinter {
    struct Content {
        var score: TabScore
        var track: Int
        var title: String
        /// The tempo to show (the sequence's, for the sequence's tab).
        var tempo: Double?
        /// The sequence's chords, placed in the tab; nil to use the tab's own chord names.
        var chords: [(bar: Int, tick: Int, name: String)]?
    }

    private static let margin: CGFloat = 36
    /// The staff is drawn smaller than on screen, to fit more to a page.
    private static let scale: CGFloat = 0.72
    private static let lineGap: CGFloat = 4
    private static let footerHeight: CGFloat = 22

    static func pdf(_ content: Content) -> Data {
        let paper = NSPrintInfo.shared.paperSize
        let pageSize = paper.width > 100 && paper.height > 100 ? paper : CGSize(width: 595, height: 842)
        let printable = pageSize.width - margin * 2
        let layoutWidth = printable / scale
        // A little tighter than the screen's normal spacing, for more bars to a line
        let layout = TabLayout.make(score: content.score, track: content.track, width: layoutWidth, zoom: 0.8)
        let stringCount = content.score.tracks.indices.contains(content.track) ? content.score.tracks[content.track].stringCount : 6
        let metrics = TabMetrics(stringCount: stringCount)
        let lineHeight = metrics.lineHeight * scale

        // Lines into pages (the first has the header)
        let header = AnyView(PrintHeader(content: content).frame(width: printable, alignment: .leading))
        let headerHeight = ImageRenderer(content: header).nsImage?.size.height ?? 80
        var pages: [[Int]] = [[]]
        var room = pageSize.height - margin * 2 - footerHeight - headerHeight - 12
        for index in layout.lines.indices {
            if room < lineHeight, !pages[pages.count - 1].isEmpty {
                pages.append([])
                room = pageSize.height - margin * 2 - footerHeight
            }
            pages[pages.count - 1].append(index)
            room -= lineHeight + lineGap
        }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        let editor = TabEditorState()
        editor.track = content.track
        editor.cursor = TabEditorState.Cursor(bar: -1, beat: -1, string: 0)

        for (pageIndex, lines) in pages.enumerated() {
            pdf.beginPDFPage(nil)
            // From the top of the page down (PDF space counts up from the bottom)
            var top = margin
            func place(_ view: some View, width: CGFloat, height: CGFloat, scale: CGFloat = 1) {
                let renderer = ImageRenderer(content: view.frame(width: width, height: height))
                renderer.render { _, draw in
                    pdf.saveGState()
                    pdf.translateBy(x: margin, y: pageSize.height - top - height * scale)
                    pdf.scaleBy(x: scale, y: scale)
                    draw(pdf)
                    pdf.restoreGState()
                }
            }
            if pageIndex == 0 {
                place(header, width: printable, height: headerHeight)
                top += headerHeight + 12
            }
            for index in lines {
                let line = layout.lines[index]
                let bars = Set(line.bars.map(\.index))
                let view = TabLineView(score: content.score, editor: editor, line: line, metrics: metrics, width: layoutWidth,
                                       sequenceChords: content.chords?.filter { bars.contains($0.bar) },
                                       sequenceTempo: content.tempo, printing: true)
                    .environment(\.colorScheme, .light)
                place(view, width: layoutWidth, height: metrics.lineHeight, scale: scale)
                top += lineHeight + lineGap
            }
            // Page numbers
            top = pageSize.height - margin - footerHeight + 6
            place(Text("\(content.title)  ·  Page \(pageIndex + 1) of \(pages.count)")
                    .font(.system(size: 9)).foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .center),
                  width: printable, height: footerHeight - 6)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return data as Data
    }

    /// Opens the Print panel for the PDF.
    static func print(_ content: Content) {
        guard let document = PDFDocument(data: pdf(content)) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .spool
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: false) else { return }
        operation.jobTitle = content.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
    }
}

/// The top of the first page.
private struct PrintHeader: View {
    let content: TabPrinter.Content

    var body: some View {
        let track = content.score.tracks.indices.contains(content.track) ? content.score.tracks[content.track] : nil
        VStack(spacing: 4) {
            Text(content.title)
                .font(.system(size: 22, weight: .semibold))
            if !content.score.artist.isEmpty {
                Text(content.score.artist)
                    .font(.system(size: 13))
            }
            if let track {
                let tuning = track.tuning.strings.map { Tuning.noteName(midi: $0).filter { !$0.isNumber && $0 != "-" } }.joined(separator: " ")
                let details = [content.score.tracks.count > 1 ? track.name : nil,
                               "Tuning \(tuning)",
                               track.capo > 0 ? "Capo \(track.capo)" : nil,
                               "♩ = \(Int((content.tempo ?? content.score.tempo).rounded()))"].compactMap { $0 }
                Text(details.joined(separator: "   ·   "))
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
        }
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// A PDF, for the Save panel.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
