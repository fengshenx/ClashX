//
//  MenuItemFactory.swift
//  ClashX
//
//  Created by CYC on 2018/8/4.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa
import RxCocoa
import SwiftyJSON

class ProxyDelayCache {
    static let shared = ProxyDelayCache()

    private var delays = [ClashProxyName: (display: String, raw: Int)]()
    private(set) var generation: UInt64 = 0

    func update(name: ClashProxyName, delay: String, raw: Int) {
        delays[name] = (display: delay, raw: raw)
        generation &+= 1
    }

    func updateFromProxies(_ proxiesMap: [ClashProxyName: ClashProxy]) {
        for (name, proxy) in proxiesMap {
            if proxy.alive == false {
                delays[name] = (display: NSLocalizedString("fail", comment: ""), raw: 0)
            } else if let last = proxy.history.last {
                delays[name] = (display: last.delayDisplay, raw: last.delay)
            }
        }
        generation &+= 1
    }

    func get(_ name: ClashProxyName) -> (display: String, raw: Int)? {
        return delays[name]
    }
}

class MenuItemFactory {
    private static var cachedProxyData: ClashProxyResp?
    private static var cachedMenuItems: [NSMenuItem]?
    private static var dataHash: Int = 0

    private static func computeProxyDataHash(_ info: ClashProxyResp?) -> Int {
        guard let info = info else { return 0 }
        var hasher = Hasher()
        for group in info.proxyGroups {
            hasher.combine(group.name)
            hasher.combine(group.type.rawValue)
            hasher.combine(group.now)
            if let all = group.all {
                for name in all {
                    hasher.combine(name)
                }
            }
        }
        return hasher.finalize()
    }

    static let useViewToRenderProxy: Bool = AppDelegate.isAboveMacOS152

    static func shouldUseViewToRenderProxy(for group: ClashProxy) -> Bool {
        guard useViewToRenderProxy, group.isSpeedTestable else { return false }
        return true
    }

    // MARK: - Public

    static func refreshExistingMenuItems() {
        if let cached = cachedMenuItems {
            updateProxyList(withMenus: cached)
        }

        ApiRequest.getMergedProxyData {
            info in
            guard let info = info else { return }

            // Always update the global delay cache
            ProxyDelayCache.shared.updateFromProxies(info.proxiesMap)

            let newHash = computeProxyDataHash(info)
            if newHash == self.dataHash {
                // Data unchanged — update group headers only
                NotificationCenter.default.post(
                    name: .proxyBatchUpdate,
                    object: nil,
                    userInfo: ["proxiesMap": info.proxiesMap]
                )
                return
            }

            // Data changed — update cache and rebuild
            self.dataHash = newHash
            self.cachedProxyData = info
            self.refreshMenuItems(mergedData: info)

            NotificationCenter.default.post(
                name: .proxyBatchUpdate,
                object: nil,
                userInfo: ["proxiesMap": info.proxiesMap]
            )
        }
    }

    static func recreateProxyMenuItems() {
        ApiRequest.getMergedProxyData {
            proxyInfo in
            self.dataHash = self.computeProxyDataHash(proxyInfo)
            self.cachedProxyData = proxyInfo
            self.cachedMenuItems = nil
            if let proxyInfo = proxyInfo {
                ProxyDelayCache.shared.updateFromProxies(proxyInfo.proxiesMap)
            }
            self.refreshMenuItems(mergedData: proxyInfo)
        }
    }

    static func refreshMenuItems(mergedData proxyInfo: ClashProxyResp?) {
        let leftPadding = AppDelegate.shared.hasMenuSelected()
        guard let proxyInfo = proxyInfo else { return }
        var menuItems = [NSMenuItem]()
        for proxy in proxyInfo.proxyGroups {
            var menu: NSMenuItem?
            switch proxy.type {
            case .select: menu = generateSelectorMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo, leftPadding: leftPadding)
            case .urltest, .fallback: menu = generateUrlTestFallBackMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo, leftPadding: leftPadding)
            case .loadBalance:
                menu = generateLoadBalanceMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo, leftPadding: leftPadding)
            case .relay:
                menu = generateListOnlyMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo)
            default: continue
            }

            if let menu = menu {
                menuItems.append(menu)
                menu.isEnabled = true
            }
        }
        let items = Array(menuItems.reversed())
        cachedMenuItems = items
        updateProxyList(withMenus: items)
    }

    static func generateSwitchConfigMenuItems(complete: @escaping (([NSMenuItem]) -> Void)) {
        let generateMenuItem: ((String) -> NSMenuItem) = {
            config in
            let item = NSMenuItem(title: config, action: #selector(MenuItemFactory.actionSelectConfig(sender:)), keyEquivalent: "")
            item.target = MenuItemFactory.self
            item.state = ConfigManager.selectConfigName == config ? .on : .off
            return item
        }

        if RemoteControlManager.selectConfig != nil {
            complete([])
            return
        }

        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getConfigFilesList {
                complete($0.map { generateMenuItem($0) })
            }
        } else {
            complete(ConfigManager.getConfigFilesList().map { generateMenuItem($0) })
        }
    }

    // MARK: - Lazy Population (called by ProxyGroupMenu.menuNeedsUpdate)

    static func populateMenu(_ submenu: ProxyGroupMenu,
                             type: ProxyGroupMenu.GroupMenuType,
                             proxyGroup: ClashProxy,
                             proxyInfo: ClashProxyResp,
                             leftPadding: Bool) {
        switch type {
        case .select:
            populateSelectorMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        case .urltest, .fallback:
            populateUrlTestFallBackMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        case .loadBalance:
            populateLoadBalanceMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        case .relay:
            populateRelayMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        }
    }

    // MARK: - Private

    // MARK: Updaters

    static func updateProxyList(withMenus menus: [NSMenuItem]) {
        let app = AppDelegate.shared
        let startIndex = app.statusMenu.items.firstIndex(of: app.separatorLineTop)! + 1
        let endIndex = app.statusMenu.items.firstIndex(of: app.sepatatorLineEndProxySelect)!
        app.sepatatorLineEndProxySelect.isHidden = menus.isEmpty
        for _ in 0 ..< endIndex - startIndex {
            app.statusMenu.removeItem(at: startIndex)
        }
        for each in menus {
            app.statusMenu.insertItem(each, at: startIndex)
        }
    }

    // MARK: Skeleton Generators

    private static func generateSelectorMenuItem(proxyGroup: ClashProxy,
                                                 proxyInfo: ClashProxyResp,
                                                 leftPadding: Bool) -> NSMenuItem? {
        let isGlobalMode = ConfigManager.shared.currentConfig?.mode == .global
        if !isGlobalMode {
            if proxyGroup.name == "GLOBAL" { return nil }
        }

        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        let selectedName = proxyGroup.now ?? ""
        if !Settings.disableShowCurrentProxyInMenu {
            menu.view = ProxyGroupMenuItemView(group: proxyGroup.name, targetProxy: selectedName, hasLeftPadding: leftPadding)
        }
        let submenu = ProxyGroupMenu(title: proxyGroup.name)
        submenu.proxyGroup = proxyGroup
        submenu.proxyInfo = proxyInfo
        submenu.menuType = .select
        submenu.leftPadding = leftPadding
        populateSelectorMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        submenu.isPopulated = true
        menu.submenu = submenu
        return menu
    }

    private static func generateUrlTestFallBackMenuItem(proxyGroup: ClashProxy,
                                                        proxyInfo: ClashProxyResp,
                                                        leftPadding: Bool) -> NSMenuItem? {
        let selectedName = proxyGroup.now ?? ""
        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        if !Settings.disableShowCurrentProxyInMenu {
            menu.view = ProxyGroupMenuItemView(group: proxyGroup.name, targetProxy: selectedName, hasLeftPadding: leftPadding)
        }
        let submenu = ProxyGroupMenu(title: proxyGroup.name)
        submenu.proxyGroup = proxyGroup
        submenu.proxyInfo = proxyInfo
        submenu.menuType = proxyGroup.type == .urltest ? .urltest : .fallback
        submenu.leftPadding = leftPadding
        populateUrlTestFallBackMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        submenu.isPopulated = true
        menu.submenu = submenu
        return menu
    }

    private static func generateLoadBalanceMenuItem(proxyGroup: ClashProxy, proxyInfo: ClashProxyResp, leftPadding: Bool) -> NSMenuItem? {
        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        if !Settings.disableShowCurrentProxyInMenu {
            menu.view = ProxyGroupMenuItemView(group: proxyGroup.name, targetProxy: NSLocalizedString("Load Balance", comment: ""), hasLeftPadding: leftPadding, observeUpdate: false)
        }
        let submenu = ProxyGroupMenu(title: proxyGroup.name)
        submenu.proxyGroup = proxyGroup
        submenu.proxyInfo = proxyInfo
        submenu.menuType = .loadBalance
        submenu.leftPadding = leftPadding
        populateLoadBalanceMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        submenu.isPopulated = true
        menu.submenu = submenu
        return menu
    }

    private static func generateListOnlyMenuItem(proxyGroup: ClashProxy, proxyInfo: ClashProxyResp) -> NSMenuItem? {
        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        let submenu = ProxyGroupMenu(title: proxyGroup.name)
        submenu.proxyGroup = proxyGroup
        submenu.proxyInfo = proxyInfo
        submenu.menuType = .relay
        populateRelayMenu(submenu, proxyGroup: proxyGroup, proxyInfo: proxyInfo)
        submenu.isPopulated = true
        menu.submenu = submenu
        return menu
    }

    // MARK: Population Methods

    private static func populateSelectorMenu(_ submenu: ProxyGroupMenu,
                                             proxyGroup: ClashProxy,
                                             proxyInfo: ClashProxyResp) {
        let proxyMap = proxyInfo.proxiesMap
        let selectedName = proxyGroup.now ?? ""
        for proxy in proxyGroup.all ?? [] {
            guard let proxyModel = proxyMap[proxy] else { continue }
            let proxyItem = ProxyMenuItem(proxy: proxyModel,
                                          group: proxyGroup,
                                          action: #selector(MenuItemFactory.actionSelectProxy(sender:)))
            proxyItem.target = MenuItemFactory.self
            if proxyModel.name == selectedName {
                proxyItem.state = .on
            }
            submenu.add(delegate: proxyItem)
            submenu.addItem(proxyItem)
        }

        if shouldUseViewToRenderProxy(for: proxyGroup) {
            submenu.minimumWidth = proxyGroup.maxProxyNameLength + ProxyItemView.fixedPlaceHolderWidth
        }

        addSpeedTestMenuItem(submenu, proxyGroup: proxyGroup)
    }

    private static func populateUrlTestFallBackMenu(_ submenu: ProxyGroupMenu,
                                                    proxyGroup: ClashProxy,
                                                    proxyInfo: ClashProxyResp) {
        let proxyMap = proxyInfo.proxiesMap
        let selectedName = proxyGroup.now ?? ""
        for proxyName in proxyGroup.all ?? [] {
            guard let proxy = proxyMap[proxyName] else { continue }
            let proxyMenuItem = ProxyMenuItem(proxy: proxy, group: proxyGroup, action: #selector(empty), simpleItem: true)
            proxyMenuItem.target = MenuItemFactory.self
            if proxy.name == selectedName {
                proxyMenuItem.state = .on
            }
            proxyMenuItem.needsDelayHistory = true
            submenu.addItem(proxyMenuItem)
        }
        addSpeedTestMenuItem(submenu, proxyGroup: proxyGroup)
    }

    private static func populateLoadBalanceMenu(_ submenu: ProxyGroupMenu,
                                                proxyGroup: ClashProxy,
                                                proxyInfo: ClashProxyResp) {
        let proxyMap = proxyInfo.proxiesMap
        for proxy in proxyGroup.all ?? [] {
            guard let proxyModel = proxyMap[proxy] else { continue }
            let proxyItem = ProxyMenuItem(proxy: proxyModel,
                                          group: proxyGroup,
                                          action: #selector(empty))
            proxyItem.target = MenuItemFactory.self
            submenu.add(delegate: proxyItem)
            submenu.addItem(proxyItem)
        }
        if shouldUseViewToRenderProxy(for: proxyGroup) {
            submenu.minimumWidth = proxyGroup.maxProxyNameLength + ProxyItemView.fixedPlaceHolderWidth
        }
        addSpeedTestMenuItem(submenu, proxyGroup: proxyGroup)
    }

    private static func populateRelayMenu(_ submenu: ProxyGroupMenu,
                                          proxyGroup: ClashProxy,
                                          proxyInfo: ClashProxyResp) {
        let proxyMap = proxyInfo.proxiesMap
        for proxy in proxyGroup.all ?? [] {
            guard let proxyModel = proxyMap[proxy] else { continue }
            let proxyItem = ProxyMenuItem(proxy: proxyModel,
                                          group: proxyGroup,
                                          action: #selector(empty),
                                          simpleItem: true)
            proxyItem.target = MenuItemFactory.self
            submenu.add(delegate: proxyItem)
            submenu.addItem(proxyItem)
        }
    }

    private static func addSpeedTestMenuItem(_ menu: NSMenu, proxyGroup: ClashProxy) {
        guard !proxyGroup.speedtestAble.isEmpty else { return }
        let speedTestItem = ProxyGroupSpeedTestMenuItem(group: proxyGroup)
        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: 0)
        menu.insertItem(speedTestItem, at: 0)
        (menu as? ProxyGroupMenu)?.add(delegate: speedTestItem)
    }
}

// MARK: - Action

extension MenuItemFactory {
    @objc static func actionSelectProxy(sender: ProxyMenuItem) {
        guard let proxyGroup = sender.menu?.title else { return }
        let proxyName = sender.proxyName

        ApiRequest.updateProxyGroup(group: proxyGroup, selectProxy: proxyName) { success in
            if success {
                for items in sender.menu?.items ?? [NSMenuItem]() {
                    items.state = .off
                }
                sender.state = .on
                // remember select proxy
                let newModel = SavedProxyModel(group: proxyGroup, selected: proxyName, config: ConfigManager.selectConfigName)
                ConfigManager.selectedProxyRecords.removeAll { model -> Bool in
                    return model.key == newModel.key
                }
                ConfigManager.selectedProxyRecords.append(newModel)
                // terminal Connections for this group
                ConnectionManager.closeConnection(for: proxyGroup)
                // Update cached data immediately so subsequent menuNeedsUpdate reads the correct now
                if let groupIndex = MenuItemFactory.cachedProxyData?.proxyGroups.firstIndex(where: { $0.name == proxyGroup }) {
                    MenuItemFactory.cachedProxyData?.proxyGroups[groupIndex].now = proxyName
                }
                // refresh menu items
                MenuItemFactory.refreshExistingMenuItems()
            }
        }
    }

    @objc static func actionSelectConfig(sender: NSMenuItem) {
        let config = sender.title
        AppDelegate.shared.updateConfig(configName: config, showNotification: false) {
            err in
            if err == nil {
                ConnectionManager.closeAllConnection()
            }
        }
    }

    @objc static func empty() {}
}
