import AppKit
import SparkleDesignSystem

extension FilePaneTableView.Coordinator {
    func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Commander Actions")
        let strings = parent.strings

        addItem(strings.t("common.open"), action: .open, to: menu)
        addSubmenu(strings.t("common.edit"), items: buildEditSubmenu(strings), to: menu)
        addItem(parent.isLocalPane ? parent.strings.upload : parent.strings.download, action: .transfer, to: menu)
        addItem(strings.t("pane.copyTo"), action: .copyTo, key: "", to: menu)
        addItem(strings.t("pane.moveTo"), action: .moveTo, key: "", to: menu)
        addItem(strings.t("common.delete"), action: .delete, to: menu)
        addItem(strings.t("common.rename"), action: .rename, to: menu)
        addItem(strings.t("pane.copyClipboard"), action: .copyClipboard, to: menu)
        menu.addItem(.separator())

        addSubmenu(strings.t("pane.customCommands"), items: buildCustomCommandsSubmenu(strings), to: menu)
        addSubmenu(strings.t("pane.fileNames"), items: buildFileNamesSubmenu(strings), to: menu)
        menu.addItem(.separator())

        addItem(strings.t("pane.getInfo"), action: .inspect, to: menu)
        addItem(strings.t("nav.quickLook"), action: .quickLook, to: menu)
        if !parent.isLocalPane {
            addItem(strings.t("pane.chmod"), action: .permissions, to: menu)
        }
        addItem(parent.strings.newFolder, action: .newFolder, to: menu)
        addItem(strings.t("conn.selectAll"), action: .selectAll, to: menu)
        if parent.isLocalPane {
            addItem(strings.t("pane.showInFinder"), action: .showInFinder, to: menu)
        }
        return menu
    }

    private func buildEditSubmenu(_ strings: AppStrings) -> NSMenu {
        let sub = NSMenu(title: strings.t("common.edit"))
        addItem(strings.t("pane.openInNotepad"), action: .edit, to: sub)
        addItem(strings.t("editor.openExternal"), action: .openExternalApp, to: sub)
        sub.addItem(.separator())
        addItem(strings.t("pane.configureEditor"), action: .configureEditor, to: sub)
        return sub
    }

    private func buildCustomCommandsSubmenu(_ strings: AppStrings) -> NSMenu {
        let sub = NSMenu(title: strings.t("pane.customCommands"))
        addItem(strings.t("pane.compareFiles"), action: .compareFiles, to: sub)
        if parent.isLocalPane {
            addItem(strings.t("pane.compressUpload"), action: .compressAndUpload, to: sub)
        }
        addItem(strings.t("pane.verifyChecksum"), action: .verifyChecksum, to: sub)
        if !parent.isLocalPane {
            sub.addItem(.separator())
            addItem(strings.t("pane.executeCustomSSH"), action: .customSSHCommand, to: sub)
        }
        return sub
    }

    private func buildFileNamesSubmenu(_ strings: AppStrings) -> NSMenu {
        let sub = NSMenu(title: strings.t("pane.fileNames"))
        addItem(strings.t("pane.insertCommandLine"), action: .insertCommandLine, to: sub)
        addItem(strings.t("pane.copyFileNames"), action: .copyFileNames, to: sub)
        addItem(strings.t("pane.copyFullPaths"), action: .copyFullPaths, to: sub)
        return sub
    }

    private func addSubmenu(_ title: String, items submenu: NSMenu, to parentMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        parentMenu.addItem(item)
    }

    private func addItem(
        _ title: String,
        action: FilePaneContextAction,
        key: String = "",
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(handleContextMenuClick(_:)), keyEquivalent: key)
        item.target = self
        item.tag = action.rawValue
        menu.addItem(item)
    }

    @objc func handleContextMenuClick(_ sender: NSMenuItem) {
        guard let action = FilePaneContextAction(rawValue: sender.tag) else { return }
        parent.onFocusPane()
        let clickedRow = tableView?.clickedRow ?? -1
        let selectedRow = tableView?.selectedRow ?? -1
        let targetIndex = clickedRow >= 0 ? clickedRow : selectedRow
        let targetFile = (targetIndex >= 0 && targetIndex < cachedFiles.count) ? cachedFiles[targetIndex] : nil
        parent.onContextAction(action, targetFile)
    }

    static func buildReusableCell(
        identifier: NSUserInterfaceItemIdentifier,
        includeIcon: Bool
    ) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField

        if includeIcon {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        return cell
    }
}
