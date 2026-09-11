import UIKit

enum BrowserbaseLogo {
    private static let orange = UIColor(red: 1, green: 69 / 255, blue: 0, alpha: 1)

    static func image(size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let graphics = context.cgContext
            graphics.scaleBy(x: size / 200, y: size / 200)

            orange.setFill()
            graphics.fill(CGRect(x: 0, y: 0, width: 200, height: 200))

            let glyph = UIBezierPath()
            glyph.move(to: CGPoint(x: 55.4453, y: 147.815))
            glyph.addLine(to: CGPoint(x: 128.678, y: 147.815))
            glyph.addLine(to: CGPoint(x: 145.259, y: 131.234))
            glyph.addLine(to: CGPoint(x: 145.259, y: 111.891))
            glyph.addLine(to: CGPoint(x: 131.441, y: 98.0723))
            glyph.addLine(to: CGPoint(x: 142.495, y: 87.0186))
            glyph.addLine(to: CGPoint(x: 142.495, y: 69.0557))
            glyph.addLine(to: CGPoint(x: 125.914, y: 52.4756))
            glyph.addLine(to: CGPoint(x: 55.4453, y: 52.4756))
            glyph.close()
            UIColor.white.setFill()
            glyph.fill()

            orange.setFill()
            graphics.fill(CGRect(x: 83.168, y: 79.208, width: 28, height: 7))
            graphics.fill(CGRect(x: 83.168, y: 109.901, width: 28, height: 7))
        }
    }
}
