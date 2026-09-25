import Foundation

/// Ridge regression solved through the normal equations.
///
/// The systems Nod solves are tiny (at most ~10 unknowns, a few hundred rows),
/// so a straightforward Gaussian elimination with partial pivoting is both
/// exact enough and dependency free.
public enum LeastSquares {
    /// Solves `min ||X w - y||² + ridge * ||w[1...]||²` for `w`.
    /// The intercept (column 0) is not regularised.
    /// Returns nil when the system is degenerate.
    public static func ridge(rows: [[Double]], targets: [Double], ridge: Double) -> [Double]? {
        guard let n = rows.first?.count, n > 0, rows.count == targets.count, !rows.isEmpty else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var b = [Double](repeating: 0, count: n)
        for (row, t) in zip(rows, targets) {
            guard row.count == n else { return nil }
            for i in 0..<n {
                b[i] += row[i] * t
                for j in i..<n { a[i][j] += row[i] * row[j] }
            }
        }
        for i in 0..<n {
            for j in 0..<i { a[i][j] = a[j][i] }
            if i > 0 { a[i][i] += ridge }
        }
        return solve(a, b)
    }

    /// Solves `A x = b` for a square system. Returns nil if singular.
    public static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        let n = rhs.count
        guard matrix.count == n else { return nil }
        var a = matrix
        var b = rhs
        for col in 0..<n {
            // Partial pivot.
            var pivot = col
            var best = abs(a[col][col])
            for r in (col + 1)..<max(n, col + 1) where abs(a[r][col]) > best {
                best = abs(a[r][col])
                pivot = r
            }
            guard best > 1e-12 else { return nil }
            if pivot != col {
                a.swapAt(pivot, col)
                b.swapAt(pivot, col)
            }
            for r in (col + 1)..<max(n, col + 1) {
                let f = a[r][col] / a[col][col]
                if f == 0 { continue }
                for c in col..<n { a[r][c] -= f * a[col][c] }
                b[r] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for c in (r + 1)..<max(n, r + 1) { s -= a[r][c] * x[c] }
            x[r] = s / a[r][r]
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }
}
