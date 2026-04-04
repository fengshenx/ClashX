//
//  ProxyMenuItem.swift
//  ClashX
//
//  Created by CYC on 2019/2/18.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

class ProxyMenuItem: NSMenuItem {
    let proxyName: String
    let groupName: String
    let maxProxyNameLength: CGFloat
    var needsDelayHistory: Bool = false
    private let isSimpleItem: Bool

    var enableShowUsingView: Bool {
        MenuItemFactory.useViewToRenderProxy
    }

    init(proxy: ClashProxy,
         group: ClashProxy,
         action selector: Selector?,
         simpleItem: Bool = false) {
        proxyName = proxy.name
        groupName = group.name
        isSimpleItem = simpleItem
        maxProxyNameLength = simpleItem ? 0 : group.maxProxyNameLength

        super.init(title: proxyName, action: selector, keyEquivalent: "")

        if !simpleItem && enableShowUsingView && group.isSpeedTestable {
            view = ProxyItemView(proxy: proxy)
        } else if !simpleItem {
            attributedTitle = getAttributedTitle(name: proxyName, delay: proxy.history.last?.delayDisplay)
        }
        let selected = group.now == proxy.name
        updateSelected(selected)

        // Apply cached delay (shared across groups for the same server)
        if let cached = ProxyDelayCache.shared.get(proxyName) {
            updateDelay(cached.display, rawValue: cached.raw)
        }
    }

    @available(*, unavailable)
    required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func didClick() {
        if let action = action {
            _ = target?.perform(action, with: self)
        }
        menu?.cancelTracking()
    }

    /// Called by ProxyGroupMenu when submenu opens or data refreshes
    func refreshFromCache(group: ClashProxy?) {
        // Update selection
        if let group = group {
            updateSelected(group.now == proxyName)
        }
        // Update delay from global cache
        if let cached = ProxyDelayCache.shared.get(proxyName) {
            updateDelay(cached.display, rawValue: cached.raw)
        }
    }

    private func updateSelected(_ selected: Bool) {
        if let v = view as? ProxyItemView {
            v.update(selected: selected)
        } else {
            state = selected ? .on : .off
        }
    }

    private func updateDelay(_ delay: String?, rawValue: Int?) {
        if let v = view as? ProxyItemView {
            v.update(str: delay, value: rawValue)
        } else {
            attributedTitle = getAttributedTitle(name: proxyName, delay: delay)
        }
    }
}

extension ProxyMenuItem: ProxyGroupMenuHighlightDelegate {
    func highlight(item: NSMenuItem?) {
        (view as? ProxyItemView)?.isHighlighted = item == self
    }
}

extension ProxyMenuItem {
    func getAttributedTitle(name: String, delay: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: 65 + maxProxyNameLength, options: [:])
        ]
        let proxyName = name.replacingOccurrences(of: "\t", with: " ")
        let str: String
        if let delay = delay {
            str = "\(proxyName)\t\(delay)"
        } else {
            str = proxyName.appending(" ")
        }

        let attributed = NSMutableAttributedString(
            string: str,
            attributes: [
                NSAttributedString.Key.paragraphStyle: paragraph,
                NSAttributedString.Key.font: NSFont.menuBarFont(ofSize: 14)
            ]
        )

        let hackAttr = [NSAttributedString.Key.font: NSFont.menuBarFont(ofSize: 15)]
        attributed.addAttributes(hackAttr, range: NSRange(name.utf16.count ..< name.utf16.count + 1))

        if delay != nil {
            let delayAttr = [NSAttributedString.Key.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
            attributed.addAttributes(delayAttr, range: NSRange(name.utf16.count + 1 ..< str.utf16.count))
        }
        return attributed
    }
}
