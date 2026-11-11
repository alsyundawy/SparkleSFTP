import AppKit
import SparkleCore
import SparkleDesignSystem

extension ConnectionListCoordinator: NSMenuDelegate {
    func makeHeaderLabel(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.identifier = identifier
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func makeProfileCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.imageView = icon

        let titleField = NSTextField(labelWithString: "")
        titleField.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.tag = 101
        cell.addSubview(titleField)
        cell.textField = titleField

        let subtitleField = NSTextField(labelWithString: "")
        subtitleField.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subtitleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.tag = 102
        cell.addSubview(subtitleField)

        let protoField = NSTextField(labelWithString: "")
        protoField.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        protoField.alignment = .right
        protoField.translatesAutoresizingMaskIntoConstraints = false
        protoField.tag = 103
        cell.addSubview(protoField)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: protoField.leadingAnchor, constant: -6),
            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            subtitleField.trailingAnchor.constraint(lessThanOrEqualTo: protoField.leadingAnchor, constant: -6),
            protoField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            protoField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            protoField.widthAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        return cell
    }

    func configureProfileCell(_ cell: NSTableCellView, profile: ConnectionProfile) {
        let palette = parent.palette
        let isEncrypted = profile.protocolType.isEncryptedByDefault
        let star = profile.isFavorite ? " ★" : ""
        (cell.viewWithTag(101) as? NSTextField)?.stringValue = "\(profile.name)\(star)"
        (cell.viewWithTag(101) as? NSTextField)?.textColor = NSColor(hex: palette.primaryTextHex)

        let subtitle = cell.viewWithTag(102) as? NSTextField
        subtitle?.stringValue = "\(profile.username)@\(profile.host):\(profile.port)"
        subtitle?.textColor = NSColor(hex: palette.secondaryTextHex)

        let proto = cell.viewWithTag(103) as? NSTextField
        proto?.stringValue = profile.protocolType.rawValue.uppercased()
        proto?.textColor = NSColor(hex: palette.secondaryTextHex)

        let symName = isEncrypted ? SparkleTheme.Symbols.sftp : SparkleTheme.Symbols.ftpInsecure
        cell.imageView?.image = NSImage(systemSymbolName: symName, accessibilityDescription: profile.name)
        cell.imageView?.contentTintColor = isEncrypted ? NSColor(hex: palette.accentHex) : NSColor.systemRed
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Connections")
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clicked = tableView?.clickedRow ?? -1
        let targetRow = clicked >= 0 ? clicked : (tableView?.selectedRow ?? -1)
        guard targetRow >= 0, targetRow < cachedRows.count else { return }

        switch cachedRows[targetRow] {
        case let .section(_, _, groupID):
            if let groupID {
                let deleteGroup = NSMenuItem(
                    title: parent.strings.t("common.delete"),
                    action: #selector(handleDeleteGroup(_:)),
                    keyEquivalent: ""
                )
                deleteGroup.target = self
                deleteGroup.representedObject = groupID
                menu.addItem(deleteGroup)
            }
        case let .profile(profile, _):
            addMenuItem(parent.strings.connect, action: #selector(handleConnectMenu(_:)), obj: profile, to: menu)
            if profile.protocolType == .sftp || profile.protocolType == .scp {
                addMenuItem(
                    parent.strings.t("nav.openInITerm"),
                    action: #selector(handleExternalTerminalMenu(_:)),
                    obj: profile,
                    to: menu
                )
            }
            addMenuItem(parent.strings.t("common.edit"), action: #selector(handleEditMenu(_:)), obj: profile, to: menu)
            addMenuItem(
                parent.strings.t("conn.cloneConnection"),
                action: #selector(handleCloneMenu(_:)),
                obj: profile,
                to: menu
            )
            menu.addItem(.separator())
            if parent.selectedIDs.count > 1, parent.selectedIDs.contains(profile.id) {
                let title = "\(parent.strings.t("conn.deleteSelected")) (\(parent.selectedIDs.count))"
                addMenuItem(title, action: #selector(handleBatchDeleteMenu), obj: nil, to: menu)
            } else {
                addMenuItem(
                    parent.strings.t("common.delete"),
                    action: #selector(handleDeleteSingleMenu(_:)),
                    obj: profile,
                    to: menu
                )
            }
        }
    }

    private func addMenuItem(_ title: String, action: Selector, obj: Any?, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = obj
        menu.addItem(item)
    }

    @objc private func handleConnectMenu(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? ConnectionProfile {
            parent.onConnect(profile)
        }
    }

    @objc private func handleExternalTerminalMenu(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? ConnectionProfile {
            parent.onOpenExternalTerminal(profile)
        }
    }

    @objc private func handleEditMenu(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? ConnectionProfile {
            parent.onEdit(profile)
        }
    }

    @objc private func handleCloneMenu(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? ConnectionProfile {
            parent.onClone(profile)
        }
    }

    @objc private func handleDeleteSingleMenu(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? ConnectionProfile {
            parent.onRequestDelete([profile.id])
        }
    }

    @objc private func handleBatchDeleteMenu() {
        parent.onRequestDelete(parent.selectedIDs)
    }

    @objc private func handleDeleteGroup(_ sender: NSMenuItem) {
        if let groupID = sender.representedObject as? UUID {
            parent.onDeleteGroup(groupID)
        }
    }
}
