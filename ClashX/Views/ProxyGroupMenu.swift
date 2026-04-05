//
//  ProxyGroupMenu.swift
//  ClashX
//
//  Created by yicheng on 2020/2/22.
//  Copyright © 2020 west2online. All rights reserved.
//
import AppKit

@objc protocol ProxyGroupMenuHighlightDelegate: AnyObject {
    func highlight(item: NSMenuItem?)
}

class ProxyGroupMenu: NSMenu {
    enum GroupMenuType {
        case select
        case urltest
        case fallback
        case loadBalance
        case relay
    }

    var highlightDelegates = NSHashTable<ProxyGroupMenuHighlightDelegate>.weakObjects()

    var proxyGroup: ClashProxy?
    var proxyInfo: ClashProxyResp?
    var menuType: GroupMenuType = .select
    var leftPadding: Bool = false
    var isPopulated: Bool = false
    private var lastRefreshGeneration: UInt64 = 0
    private var lastRefreshNow: String = ""

    override init(title: String) {
        super.init(title: title)
        delegate = self
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    func add(delegate: ProxyGroupMenuHighlightDelegate) {
        highlightDelegates.add(delegate)
    }

    func remove(_ delegate: ProxyGroupMenuHighlightDelegate) {
        highlightDelegates.remove(delegate)
    }

    /// Refresh all existing items from cache without rebuilding
    private func refreshItemsFromCache() {
        let group = proxyInfo?.proxiesMap[proxyGroup?.name ?? ""]
        let currentGeneration = ProxyDelayCache.shared.generation
        let currentNow = group?.now ?? ""
        if currentGeneration == lastRefreshGeneration && currentNow == lastRefreshNow {
            return
        }
        lastRefreshGeneration = currentGeneration
        lastRefreshNow = currentNow
        for item in items {
            if let proxyItem = item as? ProxyMenuItem {
                proxyItem.refreshFromCache(group: group)
            }
        }
    }
}

extension ProxyGroupMenu: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if isPopulated {
            // Already populated — just refresh delay/selection from cache
            refreshItemsFromCache()
            return
        }
        guard let proxyGroup = proxyGroup, let proxyInfo = proxyInfo else { return }
        removeAllItems()
        MenuItemFactory.populateMenu(self, type: menuType, proxyGroup: proxyGroup, proxyInfo: proxyInfo, leftPadding: leftPadding)
        isPopulated = true
    }

    func menuDidClose(_ menu: NSMenu) {
        highlightDelegates.allObjects.forEach { $0.highlight(item: nil) }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        highlightDelegates.allObjects.forEach { $0.highlight(item: item) }
        // Lazy ProxyDelayHistoryMenu creation for urltest/fallback
        if menuType == .urltest || menuType == .fallback,
           let proxyItem = item as? ProxyMenuItem,
           proxyItem.needsDelayHistory,
           let proxy = proxyInfo?.proxiesMap[proxyItem.proxyName] {
            proxyItem.submenu = ProxyDelayHistoryMenu(proxy: proxy)
            proxyItem.needsDelayHistory = false
        }
    }
}
