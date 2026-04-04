//
//  ProxyDelayHistoryMenu.swift
//  ClashX
//
//  Created by yicheng on 2020/4/25.
//  Copyright © 2020 west2online. All rights reserved.
//

import Cocoa
import FlexibleDiff

class ProxyDelayHistoryMenu: NSMenu {
    var currentHistory: [ClashProxySpeedHistory]?

    init(proxy: ClashProxy) {
        super.init(title: "")
        updateHistoryMenu(proxy: proxy)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateHistoryMenu(proxy: ClashProxy) {
        let historys = Array(proxy.history.reversed())
        let change = Changeset(previous: currentHistory, current: historys, identifier: { $0.time })
        currentHistory = historys
        if change.moves.isEmpty && change.mutations.isEmpty {
            for idx in change.removals.reversed() {
                removeItem(at: idx)
            }
            for idx in change.inserts {
                let his = historys[idx]
                let item = NSMenuItem(title: his.displayString, action: nil, keyEquivalent: "")
                insertItem(item, at: idx)
            }
        } else {
            historys.map { his in
                NSMenuItem(title: his.displayString, action: nil, keyEquivalent: "")
            }.forEach { item in
                addItem(item)
            }
        }
    }
}

extension ClashProxySpeedHistory: Equatable {
    static func == (lhs: ClashProxySpeedHistory, rhs: ClashProxySpeedHistory) -> Bool {
        return lhs.displayString == rhs.displayString
    }
}
