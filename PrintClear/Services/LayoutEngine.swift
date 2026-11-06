import Foundation

/// 排版类型：选一种，自动排版就按它来。
/// 智能推荐会按图片大小、方向算一算，挑裁得最少的那种。
enum LayoutTemplate: String, CaseIterable, Identifiable {
    case smart = "智能推荐"
    case fill = "平铺铺满"
    case top2bottom1 = "上二下一"
    case top1bottom2 = "上一下二"
    case grid2x2 = "田字格"
    case leftRight = "左右两栏"
    case topBottom = "上下两栏"
    case single = "单张铺满"

    var id: String { rawValue }

    /// 固定模板有几个格子；智能推荐、平铺铺满不限个数。
    var slotCount: Int? {
        switch self {
        case .smart, .fill: return nil
        case .top2bottom1, .top1bottom2: return 3
        case .grid2x2: return 4
        case .leftRight, .topBottom: return 2
        case .single: return 1
        }
    }
}

/// 排版引擎：固定模板、平铺铺满、智能推荐。
/// A4 纸 210×297mm，四边留白 10mm，间距 5mm。
enum LayoutEngine {
    static let pageW = 210.0
    static let pageH = 297.0
    static let margin = 10.0
    static let spacing = 5.0
    static var availW: Double { pageW - 2 * margin }
    static var availH: Double { pageH - 2 * margin }

    /// 按选中的排版类型排一版。返回排好的项 + 一句说明。
    static func apply(template: LayoutTemplate, to items: [PageItem]) -> (items: [PageItem], note: String) {
        guard !items.isEmpty else { return (items, "页上没有内容，先加素材或文字。") }
        switch template {
        case .smart:
            let picked = smartPick(items: items)
            let (placed, note) = apply(template: picked, to: items)
            return (placed, "智能推荐选了“\(picked.rawValue)”：\(note)")
        case .fill:
            return packFill(items: items)
        default:
            return applyFixed(template: template, to: items)
        }
    }

    // MARK: - 固定模板

    /// 固定模板的格子（毫米，左上角原点）。
    static func slots(for template: LayoutTemplate) -> [CGRect] {
        let m = margin
        let s = spacing
        let w = availW
        let h = availH
        let halfW = (w - s) / 2
        let halfH = (h - s) / 2
        switch template {
        case .top2bottom1:
            return [
                CGRect(x: m, y: m, width: halfW, height: halfH),
                CGRect(x: m + halfW + s, y: m, width: halfW, height: halfH),
                CGRect(x: m, y: m + halfH + s, width: w, height: halfH),
            ]
        case .top1bottom2:
            return [
                CGRect(x: m, y: m, width: w, height: halfH),
                CGRect(x: m, y: m + halfH + s, width: halfW, height: halfH),
                CGRect(x: m + halfW + s, y: m + halfH + s, width: halfW, height: halfH),
            ]
        case .grid2x2:
            return [
                CGRect(x: m, y: m, width: halfW, height: halfH),
                CGRect(x: m + halfW + s, y: m, width: halfW, height: halfH),
                CGRect(x: m, y: m + halfH + s, width: halfW, height: halfH),
                CGRect(x: m + halfW + s, y: m + halfH + s, width: halfW, height: halfH),
            ]
        case .leftRight:
            return [
                CGRect(x: m, y: m, width: halfW, height: h),
                CGRect(x: m + halfW + s, y: m, width: halfW, height: h),
            ]
        case .topBottom:
            return [
                CGRect(x: m, y: m, width: w, height: halfH),
                CGRect(x: m, y: m + halfH + s, width: w, height: halfH),
            ]
        case .single:
            return [CGRect(x: m, y: m, width: w, height: h)]
        default:
            return []
        }
    }

    /// 固定模板：大的先进大格子，按格子方向转一转、放大填满格子。
    static func applyFixed(template: LayoutTemplate, to items: [PageItem]) -> (items: [PageItem], note: String) {
        let slotList = slots(for: template)
        guard !slotList.isEmpty else { return (items, "") }
        // 大的先进大格子。
        let sortedItems = items.sorted { $0.widthMM * $0.heightMM > $1.widthMM * $1.heightMM }
        let sortedSlots = slotList.sorted { $0.width * $0.height > $1.width * $1.height }
        var placed: [UUID: PageItem] = [:]
        for (index, var item) in sortedItems.enumerated() {
            guard index < sortedSlots.count else { break }
            let slot = sortedSlots[index]
            let slotAspect = slot.width / slot.height
            let itemAspect = item.widthMM / item.heightMM
            // 横着放还是竖着放，哪个裁得少就用哪个。
            let crop0 = cropFraction(itemAspect: itemAspect, slotAspect: slotAspect)
            let crop90 = cropFraction(itemAspect: 1 / itemAspect, slotAspect: slotAspect)
            if crop90 < crop0 {
                item.rotation = (item.rotation + 90) % 360
                let w = item.widthMM
                item.widthMM = item.heightMM
                item.heightMM = w
            }
            item.xMM = slot.minX
            item.yMM = slot.minY
            item.widthMM = slot.width
            item.heightMM = slot.height
            placed[item.id] = item
        }
        let result = items.map { placed[$0.id] ?? $0 }
        var note = "已按“\(template.rawValue)”排好，四边留白 10mm。"
        if items.count > slotList.count {
            note += "需要 \(slotList.count) 项，当前 \(items.count) 项，多余的 \(items.count - slotList.count) 项保持原位。"
        } else if items.count < slotList.count {
            note += "需要 \(slotList.count) 项，当前 \(items.count) 项，空了 \(slotList.count - items.count) 个格子。"
        }
        return (result, note)
    }

    /// 一项塞进一个格子要裁掉多少（0 = 正好，越大裁得越多）。
    static func cropFraction(itemAspect: Double, slotAspect: Double) -> Double {
        guard itemAspect > 0, slotAspect > 0 else { return 1 }
        if itemAspect > slotAspect {
            return 1 - slotAspect / itemAspect
        } else {
            return 1 - itemAspect / slotAspect
        }
    }

    // MARK: - 智能推荐

    /// 按个数和裁切量挑固定模板；个数对不上就平铺铺满。
    static func smartPick(items: [PageItem]) -> LayoutTemplate {
        let candidates: [LayoutTemplate] = [.top2bottom1, .top1bottom2, .grid2x2, .leftRight, .topBottom, .single]
        var best: LayoutTemplate?
        var bestScore = Double.greatestFiniteMagnitude
        for template in candidates {
            guard template.slotCount == items.count else { continue }
            let score = totalCrop(template: template, items: items)
            if score < bestScore {
                bestScore = score
                best = template
            }
        }
        return best ?? .fill
    }

    /// 某个模板排这组图一共要裁掉多少（越小越合适）。
    static func totalCrop(template: LayoutTemplate, items: [PageItem]) -> Double {
        let slotList = slots(for: template)
        guard slotList.count == items.count else { return .greatestFiniteMagnitude }
        let sortedItems = items.sorted { $0.widthMM * $0.heightMM > $1.widthMM * $1.heightMM }
        let sortedSlots = slotList.sorted { $0.width * $0.height > $1.width * $1.height }
        var total = 0.0
        for (item, slot) in zip(sortedItems, sortedSlots) {
            let slotAspect = slot.width / slot.height
            let itemAspect = item.widthMM / item.heightMM
            total += min(
                cropFraction(itemAspect: itemAspect, slotAspect: slotAspect),
                cropFraction(itemAspect: 1 / itemAspect, slotAspect: slotAspect)
            )
        }
        return total
    }

    // MARK: - 平铺铺满

    /// 一行一行摆，方向不够就转一转；排完统一放大（或缩小）到铺满整页，
    /// 四边留白 10mm。放大太多会发虚，会在说明里讲。
    static func packFill(items: [PageItem]) -> (items: [PageItem], note: String) {
        let m = margin
        let s = spacing
        let right = pageW - m
        let sorted = items.sorted { $0.widthMM * $0.heightMM > $1.widthMM * $1.heightMM }
        var placed: [PageItem] = []
        var x = m
        var y = m
        var rowH = 0.0
        for var item in sorted {
            var w = item.widthMM
            var h = item.heightMM
            let fitsRow = { (ww: Double, hh: Double) in
                x + ww <= right + 0.01 && hh <= rowH + 0.01
            }
            if rowH > 0 {
                // 先试原方向，放不下就转一转再试。
                if !fitsRow(w, h), fitsRow(h, w) {
                    item.rotation = (item.rotation + 90) % 360
                    swap(&w, &h)
                }
                if !fitsRow(w, h) {
                    // 另起一行。
                    x = m
                    y += rowH + s
                    rowH = 0
                }
            }
            item.xMM = x
            item.yMM = y
            item.widthMM = w
            item.heightMM = h
            placed.append(item)
            x += w + s
            rowH = max(rowH, h)
        }
        // 包围盒，统一缩放到铺满（留白不动）。
        let minX = placed.map { $0.xMM }.min() ?? m
        let minY = placed.map { $0.yMM }.min() ?? m
        let maxX = placed.map { $0.xMM + $0.widthMM }.max() ?? m
        let maxY = placed.map { $0.yMM + $0.heightMM }.max() ?? m
        let boxW = max(maxX - minX, 1)
        let boxH = max(maxY - minY, 1)
        let scale = min(availW / boxW, availH / boxH)
        var result = placed
        if abs(scale - 1) > 0.001 {
            for i in result.indices {
                result[i].xMM = m + (result[i].xMM - minX) * scale
                result[i].yMM = m + (result[i].yMM - minY) * scale
                result[i].widthMM *= scale
                result[i].heightMM *= scale
                if case .text(let content, let fontSize) = result[i].kind {
                    result[i].kind = .text(content, max(fontSize * scale, 6))
                }
            }
        }
        // 按原来顺序还回去。
        var byId: [UUID: PageItem] = [:]
        result.forEach { byId[$0.id] = $0 }
        let ordered = items.map { byId[$0.id] ?? $0 }
        var note = "已平铺铺满，四边留白 10mm。"
        if scale > 1.001 {
            let dpi = Int(300 / scale)
            note += "整体放大了 \(String(format: "%.1f", scale)) 倍，有效约 \(dpi) DPI。"
            if scale > 2 {
                note += "放得有点大，印出来可能发虚。"
            }
        } else if scale < 0.999 {
            note += "内容太多，整体缩小到能放下。"
        }
        return (ordered, note)
    }
}
