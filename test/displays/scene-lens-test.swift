import Foundation

@main struct SceneLensTests {
    static func main() {
        // Mixed sizes/scales, portrait, and outputs left or above the host.
        let outputs: [(Double, Double, Double, Double)] = [
            (0, 0, 2560, 1440), (2560, 0, 1280, 800),
            (-1280, -800, 1280, 800), (0, -1920, 1080, 1920),
        ]
        var checks = 0
        for (left, top, width, height) in outputs {
            let focal = width / (2 * tan(70 * Double.pi / 360))
            let lens = DesktopSceneLens(width: width, height: height, focal: focal)
            precondition(lens.shiftX == 0 && lens.shiftY == 0)
            for (x, y, z) in [(0.0, 0.0, -4.0), (2.0, 1.0, -8.0), (-3.0, -2.0, -6.0)] {
                let nx = (x / lens.tanHalfFovX + lens.shiftX * z) / -z
                let ny = (y / (lens.tanHalfFovX / (width / height)) + lens.shiftY * z) / -z
                let px = (nx + 1) * width / 2
                let py = (1 - ny) * height / 2
                // Texture pixels and window hit tests agree in virtual coordinates.
                precondition(abs(left + px - (left + width / 2 + focal * x / -z)) < 1e-8)
                precondition(abs(top + py - (top + height / 2 - focal * y / -z)) < 1e-8)
                // Recover a ray from this output's pointer, including negative origins.
                precondition(abs(((left + px) - (left + width / 2)) / focal - x / -z) < 1e-8)
                precondition(abs(((top + height / 2) - (top + py)) / focal - y / -z) < 1e-8)
                checks += 4
            }
        }
        print("  ✔ independent display lenses: \(checks) checks passed")
    }
}
