import ARKit
import simd

/// Live room structure from ARKit's classified scene mesh (RoomPlan-style, but inside Vantage's own
/// session): a top-down obstacle map for routing around blockages, and door positions. Mesh anchors
/// are processed on a background queue; queries are thread-safe.
final class RoomMap: @unchecked Sendable {
    /// One 25 cm square of floor, in world x/z.
    struct Cell: Hashable {
        let x: Int32
        let z: Int32
    }

    struct Door {
        let center: SIMD3<Float>
        let faces: Int
    }

    static let cellSize: Float = 0.25
    /// Obstacles are surfaces between these heights above the floor (ankle to head).
    private static let obstacleBand: ClosedRange<Float> = 0.2...2.0
    /// A door cluster needs this many mesh faces to count.
    private static let minDoorFaces = 12

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "vantage.roommap", qos: .utility)
    // Guarded by `lock`.
    private var cellsByAnchor: [UUID: Set<Cell>] = [:]
    private var cellCounts: [Cell: Int] = [:]
    private var doorFacesByAnchor: [UUID: [SIMD3<Float>]] = [:]
    private var floorSamples: [Float] = []
    private var floorHint: Float?
    private var pending: [UUID: ARMeshAnchor] = [:]
    private var removed: Set<UUID> = []
    private var draining = false

    // MARK: - Ingest

    /// Camera height minus a chest-to-floor guess, until the mesh has seen enough floor.
    func setFloorHint(cameraY: Float) {
        lock.withLock { floorHint = cameraY - 1.3 }
    }

    func update(_ anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshes.isEmpty else { return }
        lock.withLock { for mesh in meshes { pending[mesh.identifier] = mesh } }
        scheduleDrain()
    }

    func remove(_ anchors: [ARAnchor]) {
        let ids = anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier }
        guard !ids.isEmpty else { return }
        lock.withLock { for id in ids { pending[id] = nil; removed.insert(id) } }
        scheduleDrain()
    }

    func reset() {
        lock.withLock {
            cellsByAnchor = [:]
            cellCounts = [:]
            doorFacesByAnchor = [:]
            floorSamples = []
            pending = [:]
            removed = []
        }
    }

    /// Coalesces updates: ARKit re-sends an anchor often; only its latest mesh gets processed.
    private func scheduleDrain() {
        let start = lock.withLock { () -> Bool in
            if draining { return false }
            draining = true
            return true
        }
        guard start else { return }
        queue.async { [weak self] in self?.drain() }
    }

    private func drain() {
        while true {
            let (batch, gone) = lock.withLock { () -> ([ARMeshAnchor], Set<UUID>) in
                let batch = Array(pending.values)
                let gone = removed
                pending = [:]
                removed = []
                if batch.isEmpty && gone.isEmpty { draining = false }
                return (batch, gone)
            }
            if batch.isEmpty && gone.isEmpty { return }
            for id in gone { replace(id, cells: [], doors: []) }
            for anchor in batch { ingest(anchor) }
        }
    }

    private func ingest(_ anchor: ARMeshAnchor) {
        let geometry = anchor.geometry
        guard let classification = geometry.classification else { return }
        let vertices = geometry.vertices
        let faces = geometry.faces
        guard faces.indexCountPerPrimitive == 3 else { return }

        let vertexBase = vertices.buffer.contents().advanced(by: vertices.offset)
        let indexBase = faces.buffer.contents()
        let classBase = classification.buffer.contents().advanced(by: classification.offset)
        let transform = anchor.transform

        func vertex(_ index: Int) -> SIMD3<Float> {
            let p = vertexBase.advanced(by: vertices.stride * index).assumingMemoryBound(to: Float.self)
            let world = transform * SIMD4(p[0], p[1], p[2], 1)
            return SIMD3(world.x, world.y, world.z)
        }
        func index(_ face: Int, _ corner: Int) -> Int {
            let at = indexBase.advanced(by: (face * 3 + corner) * faces.bytesPerIndex)
            return faces.bytesPerIndex == 4
                ? Int(at.assumingMemoryBound(to: UInt32.self).pointee)
                : Int(at.assumingMemoryBound(to: UInt16.self).pointee)
        }

        var centroids: [(point: SIMD3<Float>, kind: ARMeshClassification)] = []
        centroids.reserveCapacity(faces.count)
        var floorYs: [Float] = []
        for face in 0..<faces.count {
            let raw = classBase.advanced(by: classification.stride * face).assumingMemoryBound(to: UInt8.self).pointee
            let kind = ARMeshClassification(rawValue: Int(raw)) ?? .none
            let centroid = (vertex(index(face, 0)) + vertex(index(face, 1)) + vertex(index(face, 2))) / 3
            if kind == .floor { floorYs.append(centroid.y) }
            centroids.append((centroid, kind))
        }

        let floor = lock.withLock { () -> Float? in
            floorSamples.append(contentsOf: floorYs.prefix(200))
            if floorSamples.count > 2000 { floorSamples.removeFirst(floorSamples.count - 2000) }
            return Self.median(floorSamples) ?? floorHint
        }
        guard let floor else { return }

        var cells = Set<Cell>()
        var doors: [SIMD3<Float>] = []
        for (point, kind) in centroids {
            switch kind {
            case .door:
                doors.append(point)
            case .floor, .ceiling:
                continue
            default:
                let height = point.y - floor
                if Self.obstacleBand.contains(height) { cells.insert(Self.cell(point)) }
            }
        }
        replace(anchor.identifier, cells: cells, doors: doors)
    }

    private func replace(_ id: UUID, cells: Set<Cell>, doors: [SIMD3<Float>]) {
        lock.withLock {
            for cell in cellsByAnchor[id] ?? [] {
                let count = (cellCounts[cell] ?? 1) - 1
                cellCounts[cell] = count > 0 ? count : nil
            }
            for cell in cells { cellCounts[cell, default: 0] += 1 }
            cellsByAnchor[id] = cells.isEmpty ? nil : cells
            doorFacesByAnchor[id] = doors.isEmpty ? nil : doors
        }
    }

    // MARK: - Doors

    /// Door surfaces clustered into individual doors.
    func doors() -> [Door] {
        let points = lock.withLock { doorFacesByAnchor.values.flatMap { $0 } }
        var clusters: [Cell: (sum: SIMD3<Float>, count: Int)] = [:]
        for point in points {
            // 75 cm buckets: roughly one door each.
            let key = Cell(x: Int32((point.x / 0.75).rounded(.down)), z: Int32((point.z / 0.75).rounded(.down)))
            let existing = clusters[key] ?? (SIMD3(repeating: 0), 0)
            clusters[key] = (existing.sum + point, existing.count + 1)
        }
        return clusters.values
            .filter { $0.count >= Self.minDoorFaces }
            .map { Door(center: $0.sum / Float($0.count), faces: $0.count) }
    }

    /// The detected door nearest to `point`, if one is within `radius` metres (horizontally).
    func door(near point: SIMD3<Float>, within radius: Float) -> SIMD3<Float>? {
        doors()
            .map { ($0.center, simd_distance(SIMD2($0.center.x, $0.center.z), SIMD2(point.x, point.z))) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: - Steering

    /// If the straight line from `position` to `target` is blocked, the next point to head for on a
    /// short route around it; nil when the way is clear (or no route was found).
    func steer(from position: SIMD3<Float>, to target: SIMD3<Float>) -> SIMD3<Float>? {
        let window: Int32 = 32          // ±8 m around the wearer
        let origin = Self.cell(position)
        let blocked = inflatedObstacles(around: origin, radius: window)
        guard !blocked.isEmpty else { return nil }

        // Goal: the target, or a point 7.5 m along the line if it's beyond the window.
        var goalPoint = target
        let flat = SIMD2(target.x - position.x, target.z - position.z)
        if simd_length(flat) > 7.5 {
            let along = simd_normalize(flat) * 7.5
            goalPoint = SIMD3(position.x + along.x, target.y, position.z + along.y)
        }
        let goal = Self.cell(goalPoint)
        if lineIsClear(from: origin, to: goal, blocked: blocked) { return nil }
        if blocked.contains(goal) { return nil }

        guard let path = Self.aStar(from: origin, to: goal, blocked: blocked, window: window, around: origin) else {
            return nil
        }
        // Head for the farthest point on the route that's in clear line of sight, up to ~4 m away.
        var lookahead = path.first ?? goal
        for cell in path {
            let distance = simd_length(SIMD2(Float(cell.x - origin.x), Float(cell.z - origin.z))) * Self.cellSize
            if distance > 4 { break }
            if lineIsClear(from: origin, to: cell, blocked: blocked) { lookahead = cell }
        }
        return SIMD3(
            (Float(lookahead.x) + 0.5) * Self.cellSize,
            target.y,
            (Float(lookahead.z) + 0.5) * Self.cellSize
        )
    }

    /// Obstacle cells near the wearer, grown by one cell (~35 cm clearance for a person).
    private func inflatedObstacles(around center: Cell, radius: Int32) -> Set<Cell> {
        let occupied = lock.withLock {
            cellCounts.keys.filter { abs($0.x - center.x) <= radius + 1 && abs($0.z - center.z) <= radius + 1 }
        }
        var blocked = Set<Cell>()
        for cell in occupied {
            for dx in -1...1 {
                for dz in -1...1 {
                    blocked.insert(Cell(x: cell.x + Int32(dx), z: cell.z + Int32(dz)))
                }
            }
        }
        // Never block the wearer's own spot — inflation near a wall would otherwise trap the search.
        for dx in -1...1 {
            for dz in -1...1 { blocked.remove(Cell(x: center.x + Int32(dx), z: center.z + Int32(dz))) }
        }
        return blocked
    }

    private func lineIsClear(from start: Cell, to end: Cell, blocked: Set<Cell>) -> Bool {
        let dx = Float(end.x - start.x), dz = Float(end.z - start.z)
        let steps = max(1, Int(max(abs(dx), abs(dz)) * 2))
        for step in 0...steps {
            let t = Float(step) / Float(steps)
            let cell = Cell(x: start.x + Int32((dx * t).rounded()), z: start.z + Int32((dz * t).rounded()))
            if blocked.contains(cell) { return false }
        }
        return true
    }

    /// 8-connected A* on the local grid. Cells the mesh hasn't seen count as free.
    private static func aStar(from start: Cell, to goal: Cell, blocked: Set<Cell>, window: Int32, around center: Cell) -> [Cell]? {
        func h(_ cell: Cell) -> Float {
            let dx = Float(abs(cell.x - goal.x)), dz = Float(abs(cell.z - goal.z))
            return max(dx, dz) + 0.414 * min(dx, dz)
        }
        var open: [Cell: Float] = [start: h(start)]
        var cost: [Cell: Float] = [start: 0]
        var cameFrom: [Cell: Cell] = [:]
        var iterations = 0
        while let current = open.min(by: { $0.value < $1.value })?.key, iterations < 6000 {
            iterations += 1
            if current == goal {
                var path = [current]
                var node = current
                while let previous = cameFrom[node], previous != start { path.append(previous); node = previous }
                return path.reversed()
            }
            open[current] = nil
            for dx: Int32 in -1...1 {
                for dz: Int32 in -1...1 where dx != 0 || dz != 0 {
                    let next = Cell(x: current.x + dx, z: current.z + dz)
                    guard abs(next.x - center.x) <= window, abs(next.z - center.z) <= window,
                          !blocked.contains(next) else { continue }
                    let step: Float = (dx != 0 && dz != 0) ? 1.414 : 1
                    let candidate = (cost[current] ?? .infinity) + step
                    if candidate < (cost[next] ?? .infinity) {
                        cost[next] = candidate
                        cameFrom[next] = current
                        open[next] = candidate + h(next)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    static func cell(_ point: SIMD3<Float>) -> Cell {
        Cell(x: Int32((point.x / cellSize).rounded(.down)), z: Int32((point.z / cellSize).rounded(.down)))
    }

    private static func median(_ values: [Float]) -> Float? {
        guard values.count >= 30 else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
