//
//  ProjectReportPDF.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-10-06.
//

import SwiftUI

enum ProjectReportPDFError: LocalizedError {
    case contextUnavailable

    var errorDescription: String? {
        switch self {
        case .contextUnavailable:
            return "PDF-filen kunde inte skapas."
        }
    }
}

/// Renders ProjectReportData to an A4 PDF in the temp directory. Each page
/// is a SwiftUI view drawn by ImageRenderer straight into a PDF CGContext,
/// so text and shapes stay vector, not bitmaps.
@MainActor
enum ProjectReportPDF {
    private struct Page {
        let sectionTitle: String
        let continued: Bool
        let blocks: [AnyView]
    }

    static func render(_ data: ProjectReportData) throws -> URL {
        let pages = ProjectReportContent(data: data).sections.flatMap(paginate)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectReports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: data))
        try? FileManager.default.removeItem(at: url)

        var mediaBox = CGRect(origin: .zero, size: ReportLayout.pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ProjectReportPDFError.contextUnavailable
        }
        for (index, page) in pages.enumerated() {
            let renderer = ImageRenderer(content: ReportPageView(
                sectionTitle: page.sectionTitle,
                continued: page.continued,
                projectName: data.projectName,
                generatedAt: data.generatedAt,
                pageNumber: index + 1,
                pageCount: pages.count,
                blocks: page.blocks
            ))
            renderer.proposedSize = ProposedViewSize(ReportLayout.pageSize)
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// data.projectName is already "Team A" when anonymized, so the real
    /// name never reaches the file name then.
    static func fileName(for data: ProjectReportData) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let name = data.projectName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .unicodeScalars
            .filter { allowed.contains($0) }
        let safeName = String(String.UnicodeScalarView(name))
        let day = data.generatedAt.formatted(.iso8601.year().month().day())
        return "Projektrapport-\(safeName.isEmpty ? "projekt" : safeName)-\(day).pdf"
    }

    /// Packs a section's blocks onto pages by measured height. A block with
    /// keepWithNext moves to a new page unless the next block fits too; a
    /// block taller than a whole page gets a page of its own (clipped).
    private static func paginate(_ section: ReportSection) -> [Page] {
        let heights = section.blocks.map { measure($0.view) }
        let limit = ReportLayout.bodyHeight
        let spacing = ReportLayout.blockSpacing

        var pages: [Page] = []
        var current: [AnyView] = []
        var used: CGFloat = 0
        for (i, block) in section.blocks.enumerated() {
            var needed = heights[i] + (current.isEmpty ? 0 : spacing)
            if block.keepWithNext, i + 1 < heights.count {
                needed += spacing + heights[i + 1]
            }
            if !current.isEmpty && used + needed > limit {
                pages.append(Page(sectionTitle: section.title, continued: !pages.isEmpty, blocks: current))
                current = []
                used = 0
            }
            used += heights[i] + (current.isEmpty ? 0 : spacing)
            current.append(block.view)
        }
        if !current.isEmpty || pages.isEmpty {
            pages.append(Page(sectionTitle: section.title, continued: !pages.isEmpty, blocks: current))
        }
        return pages
    }

    /// The block's height at content width, in the same frame the page uses.
    private static func measure(_ view: AnyView) -> CGFloat {
        let renderer = ImageRenderer(content: ReportBlockFrame { view })
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }
}
