import SwiftUI
import UIKit
import VV00PCore

enum DiaryPDF {
    static func write(
        profile: DogProfile,
        dayTitle: String,
        today: PeriodTotals,
        week: PeriodTotals,
        strain: Double,
        unit: DistanceUnit,
        rows: [HistoryRow],
        photo: Data? = nil,
        destination: URL? = nil
    ) -> URL? {
        MilitaryFont.register()
        let url = destination ?? FileManager.default.temporaryDirectory.appendingPathComponent("Max-Werba.pdf")
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let canvas = Page(page: page)
        do {
            try renderer.writePDF(to: url) { context in
                canvas.context = context
                canvas.start()
                if let photo, let image = UIImage(data: photo) {
                    canvas.photo(canvas.fitted(image, side: 280))
                }
                canvas.centered(profile.name, size: 28, bold: true, color: .white)
                canvas.gap(4)
                canvas.centered(profile.breed, size: 14, bold: false, color: Palette.dim)
                canvas.gap(2)
                canvas.centered(
                    "\(Bulldog.sex) · \(profile.ageYears) years old · \(profile.weightPounds) lb",
                    size: 12,
                    bold: false,
                    color: Palette.dim
                )
                canvas.gap(18)
                canvas.centered(dayTitle, size: 13, bold: false, color: Palette.dim)
                canvas.gap(14)
                canvas.rings(today: today, strain: strain, unit: unit)
                canvas.gap(22)
                canvas.week(week, unit: unit)
                canvas.gap(22)
                canvas.bars(rows, unit: unit)
            }
            return url
        } catch {
            return nil
        }
    }
}

private enum Palette {
    static let dim = UIColor(white: 0.62, alpha: 1)
    static let card = UIColor(white: 0.12, alpha: 1)
    static let rest = UIColor(red: 0.36, green: 0.72, blue: 0.98, alpha: 1)
    static let movement = UIColor(red: 0.20, green: 0.84, blue: 0.38, alpha: 1)
    static let strain = UIColor(red: 0.98, green: 0.27, blue: 0.35, alpha: 1)
}

private final class Page {
    let page: CGRect
    var context: UIGraphicsPDFRendererContext?
    var y: CGFloat = 40

    init(page: CGRect) {
        self.page = page
    }

    func start() {
        context?.beginPage()
        UIColor.black.setFill()
        UIRectFill(page)
        y = 40
    }

    func gap(_ amount: CGFloat) {
        y += amount
    }

    func ensure(_ height: CGFloat) {
        guard y + height > page.height - 36 else { return }
        start()
    }

    func font(_ size: CGFloat, bold: Bool) -> UIFont {
        let name = bold ? MilitaryFont.bold : MilitaryFont.regular
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    func centered(_ text: String, size: CGFloat, bold: Bool, color: UIColor) {
        let font = font(size, bold: bold)
        let width = page.width - 64
        let height = ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: 80),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font],
            context: nil
        ).height)
        ensure(height)
        (text as NSString).draw(
            in: CGRect(x: 32, y: y, width: width, height: height),
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: centeredStyle,
            ]
        )
        y += height
    }

    func fitted(_ image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    func photo(_ image: UIImage) {
        let side: CGFloat = 78
        ensure(side + 8)
        let rect = CGRect(x: (page.width - side) / 2, y: y, width: side, height: side)
        context?.cgContext.saveGState()
        UIBezierPath(ovalIn: rect).addClip()
        image.draw(in: rect)
        context?.cgContext.restoreGState()
        y += side + 12
    }

    func rings(today: PeriodTotals, strain: Double, unit: DistanceUnit) {
        let count: CGFloat = 3
        let gap: CGFloat = 18
        let width = page.width - 64
        let side = min(146, (width - gap * (count - 1)) / count)
        let block = side + 36
        ensure(block)
        let originY = y
        let rest = min(1, CGFloat(today.resting) / CGFloat(Bulldog.dailyRestingSeconds))
        let movement = min(1, CGFloat(today.distance / ActivityReport.dailyMeters))
        let strainFill = min(1, CGFloat(strain / 21))
        drawRing(
            x: 32,
            y: originY,
            side: side,
            progress: rest,
            color: Palette.rest,
            value: duration(today.resting),
            label: "Rest",
            caption: "of \(Bulldog.dailyRestingHours)h"
        )
        drawRing(
            x: 32 + side + gap,
            y: originY,
            side: side,
            progress: movement,
            color: Palette.movement,
            value: unit.text(meters: today.distance),
            label: "Movement",
            caption: "of \(unit.text(meters: ActivityReport.dailyMeters))"
        )
        drawRing(
            x: 32 + (side + gap) * 2,
            y: originY,
            side: side,
            progress: strainFill,
            color: Palette.strain,
            value: String(format: "%.1f", strain),
            label: "Strain",
            caption: "of 21"
        )
        y = originY + block
    }

    func week(_ week: PeriodTotals, unit: DistanceUnit) {
        let height: CGFloat = 78
        ensure(height)
        let card = CGRect(x: 32, y: y, width: page.width - 64, height: height)
        Palette.card.setFill()
        UIBezierPath(roundedRect: card, cornerRadius: 16).fill()
        let title = "This week"
        (title as NSString).draw(
            at: CGPoint(x: card.minX + 16, y: card.minY + 12),
            withAttributes: [.font: font(13, bold: true), .foregroundColor: UIColor.white]
        )
        let detail = "\(unit.text(meters: week.distance)) · \(duration(week.moving)) moving"
        (detail as NSString).draw(
            at: CGPoint(x: card.minX + 16, y: card.minY + 32),
            withAttributes: [.font: font(12, bold: false), .foregroundColor: Palette.dim]
        )
        let span = card.width - 32
        let track = CGRect(x: card.minX + 16, y: card.maxY - 18, width: span, height: 6)
        Palette.movement.withAlphaComponent(0.25).setFill()
        UIBezierPath(roundedRect: track, cornerRadius: 3).fill()
        let fraction = min(1, CGFloat(week.distance / ActivityReport.weeklyMeters))
        if fraction > 0 {
            Palette.movement.setFill()
            UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: max(6, span * fraction), height: 6), cornerRadius: 3).fill()
        }
        y += height
    }

    func bars(_ rows: [HistoryRow], unit _: DistanceUnit) {
        let chartHeight: CGFloat = 100
        let block: CGFloat = rows.isEmpty ? 52 : 28 + chartHeight + 48
        ensure(block)
        ("Diary" as NSString).draw(
            at: CGPoint(x: 32, y: y),
            withAttributes: [.font: font(16, bold: true), .foregroundColor: UIColor.white]
        )
        y += 28
        guard !rows.isEmpty else {
            centered("No saved rows.", size: 13, bold: false, color: Palette.dim)
            return
        }
        let width = page.width - 64
        let peak = max(rows.map(\.totals.distance).max() ?? 0, 1)
        let count = CGFloat(rows.count)
        let spacing: CGFloat = count > 10 ? 4 : 8
        let barWidth = max(4, (width - spacing * (count - 1)) / count)
        let base = y + chartHeight - 8
        for (index, row) in rows.enumerated() {
            let x = 32 + CGFloat(index) * (barWidth + spacing)
            let fraction = CGFloat(row.totals.distance / peak)
            let barHeight = max(2, (chartHeight - 36) * fraction)
            let rect = CGRect(x: x, y: base - barHeight, width: barWidth, height: barHeight)
            Palette.movement.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: min(4, barWidth / 2)).fill()
            let label = row.label
            let labelRect = CGRect(x: x - 2, y: base + 4, width: barWidth + 4, height: 22)
            (label as NSString).draw(
                in: labelRect,
                withAttributes: [
                    .font: font(count > 12 ? 7 : 9, bold: false),
                    .foregroundColor: Palette.dim,
                    .paragraphStyle: centeredStyle,
                ]
            )
        }
        y = base + 28
        gap(8)
        centered("Green bars are distance. The tallest bar is the busiest stretch.", size: 10, bold: false, color: Palette.dim)
    }

    private func drawRing(
        x: CGFloat,
        y: CGFloat,
        side: CGFloat,
        progress: CGFloat,
        color: UIColor,
        value: String,
        label: String,
        caption: String
    ) {
        let center = CGPoint(x: x + side / 2, y: y + side / 2 - 6)
        let radius = side / 2 - 10
        let track = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + .pi * 2,
            clockwise: true
        )
        track.lineWidth = 8
        color.withAlphaComponent(0.22).setStroke()
        track.stroke()
        let amount = min(1, max(0, progress))
        if amount > 0 {
            let arc = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: -.pi / 2,
                endAngle: -.pi / 2 + .pi * 2 * amount,
                clockwise: true
            )
            arc.lineWidth = 8
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }
        let valueFont = font(13, bold: true)
        let valueSize = (value as NSString).size(withAttributes: [.font: valueFont])
        (value as NSString).draw(
            at: CGPoint(x: center.x - valueSize.width / 2, y: center.y - valueSize.height / 2),
            withAttributes: [.font: valueFont, .foregroundColor: UIColor.white]
        )
        let labelFont = font(12, bold: true)
        let labelSize = (label as NSString).size(withAttributes: [.font: labelFont])
        (label as NSString).draw(
            at: CGPoint(x: center.x - labelSize.width / 2, y: y + side - 8),
            withAttributes: [.font: labelFont, .foregroundColor: color]
        )
        let captionFont = font(10, bold: false)
        let captionSize = (caption as NSString).size(withAttributes: [.font: captionFont])
        (caption as NSString).draw(
            at: CGPoint(x: center.x - captionSize.width / 2, y: y + side + 8),
            withAttributes: [.font: captionFont, .foregroundColor: Palette.dim]
        )
    }

    private var centeredStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityShare: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
