import AppKit
import SparkleDesignSystem

extension FilePaneTableView.Coordinator {
    func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Commander Actions")
        let specs: [(String, FilePaneContextAction)] = [
            (parent.strings.t("common.open"), .open),
            (parent.isLocalPane ? parent.strings.upload : parent.strings.download, .transfer),
            (parent.strings.t("nav.quickLook"), .quickLook),
            (parent.strings.t("pane.openInNotepad"), .edit),
            (parent.strings.t("common.rename"), .rename),
            (parent.strings.t("pane.chmod"), .permissions),
            (parent.strings.t("pane.getInfo"), .inspect),
            (parent.strings.newFolder, .newFolder),
            (parent.strings.t("common.delete"), .delete)
        ]
        for (title, action) in specs {
            if action == .permissions, parent.isLocalPane {
                continue
            }
            let item = NSMenuItem(title: title, action: #selector(handleContextMenuClick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = action.rawValue
            menu.addItem(item)
        }
        return menu
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
