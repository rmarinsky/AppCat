import Foundation

/// Merge freshly detected items with saved configuration, preserving saved order and settings.
func mergeDetectedWithSaved<Item: Identifiable, Config>(
    detected: [Item],
    saved: [Config],
    configID: (Config) -> String,
    sortOrder: WritableKeyPath<Item, Int>,
    apply: (inout Item, Config) -> Void
) -> [Item] where Item.ID == String {
    let savedMap = Dictionary(saved.map { (configID($0), $0) }, uniquingKeysWith: { first, _ in first })
    let detectedMap = Dictionary(detected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    var result: [Item] = []
    var seenIDs: Set<String> = []

    // First: add items in saved order (if still installed)
    for config in saved {
        let id = configID(config)
        guard seenIDs.insert(id).inserted else { continue }
        if var item = detectedMap[id] {
            apply(&item, config)
            result.append(item)
        }
    }

    // Second: add newly detected items not in saved config
    let maxOrder = result.map { $0[keyPath: sortOrder] }.max() ?? -1
    var nextOrder = maxOrder + 1
    for item in detected where !savedMap.keys.contains(item.id) {
        var newItem = item
        newItem[keyPath: sortOrder] = nextOrder
        result.append(newItem)
        nextOrder += 1
    }

    return result.sorted { $0[keyPath: sortOrder] < $1[keyPath: sortOrder] }
}
