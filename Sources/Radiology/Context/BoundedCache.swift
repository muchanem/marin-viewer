/// A small least-recently-inserted cache for immutable query results. Reads
/// do not reorder; the bound only keeps memory flat across long sessions.
struct BoundedCache<Key: Hashable, Value> {
    let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) { self.capacity = capacity }

    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            guard let newValue else {
                values[key] = nil
                order.removeAll { $0 == key }
                return
            }
            if values.updateValue(newValue, forKey: key) == nil { order.append(key) }
            while order.count > capacity { values[order.removeFirst()] = nil }
        }
    }

    var count: Int { values.count }

    mutating func removeAll() {
        values.removeAll()
        order.removeAll()
    }
}
