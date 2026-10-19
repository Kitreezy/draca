import CoreGraphics

/// Проективное преобразование плоскости (3×3, h33 = 1).
/// Строится методом наименьших квадратов по 4+ парам точек, поэтому переживает
/// поворот, отражение и перспективу между кадром камеры и экраном.
struct Homography {
    private let m: [Double]

    init?(from source: [CGPoint], to target: [CGPoint]) {
        guard source.count == target.count, source.count >= 4 else { return nil }

        // Для каждой пары (x, y) → (u, v):
        //   h0·x + h1·y + h2 − h6·x·u − h7·y·u = u
        //   h3·x + h4·y + h5 − h6·x·v − h7·y·v = v
        // Копим нормальные уравнения AᵀA·h = Aᵀb.
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var atb = [Double](repeating: 0, count: 8)
        func accumulate(_ row: [Double], _ b: Double) {
            for i in 0..<8 {
                atb[i] += row[i] * b
                for j in 0..<8 { ata[i][j] += row[i] * row[j] }
            }
        }
        for (s, t) in zip(source, target) {
            let x = Double(s.x), y = Double(s.y), u = Double(t.x), v = Double(t.y)
            accumulate([x, y, 1, 0, 0, 0, -x * u, -y * u], u)
            accumulate([0, 0, 0, x, y, 1, -x * v, -y * v], v)
        }
        guard let h = Self.solve(ata, atb) else { return nil }
        m = h + [1]
    }

    func apply(_ p: CGPoint) -> CGPoint? {
        let x = Double(p.x), y = Double(p.y)
        let w = m[6] * x + m[7] * y + m[8]
        guard abs(w) > 1e-9 else { return nil }
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w,
                       y: (m[3] * x + m[4] * y + m[5]) / w)
    }

    /// Гаусс с выбором ведущего элемента. nil — если система вырождена (например, все точки на одной прямой).
    private static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        let n = vector.count
        var a = matrix
        var b = vector
        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<n where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            b.swapAt(col, pivot)
            for row in (col + 1)..<n {
                let factor = a[row][col] / a[col][col]
                guard factor != 0 else { continue }
                for c in col..<n { a[row][c] -= factor * a[col][c] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for c in (row + 1)..<n { sum -= a[row][c] * x[c] }
            x[row] = sum / a[row][row]
        }
        return x
    }
}
