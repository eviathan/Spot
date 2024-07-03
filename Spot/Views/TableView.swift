//
//  TableView.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import SwiftUI

struct DataModel: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let item: LibraryItem
    let tags: String = ""
    let rating: String = ""
}

struct TableView: View {
    @State private var selection: UUID? = nil
    
    var data: [DataModel]
    var onSelect: (_ model: DataModel) -> Void
    
    var body: some View {
        CustomTableView(data: data, onSelect: onSelect)
        .background(Color(hue: 0.63, saturation: 0.28, brightness: 0.20, opacity: 1.00))
        .tableStyle(BorderedTableStyle())
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
    }
}

struct CustomTableView: NSViewRepresentable {
    @State var data: [DataModel]
    @State private var sortOrder: [NSSortDescriptor] = []
    
    var onSelect: (_ model: DataModel) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        tableView.wantsLayer = true  // Enable layer-backed views

        scrollView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)
        tableView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        // Use the custom header view
        let headerView = CustomTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 25))
        tableView.headerView = headerView

        let column1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        column1.title = "Name"
        column1.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        tableView.addTableColumn(column1)

        let column2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Type"))
        column2.title = "Type"
        column2.sortDescriptorPrototype = NSSortDescriptor(key: "type", ascending: true)
        tableView.addTableColumn(column2)

        let column3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Tags"))
        column3.title = "Tags"
        column3.sortDescriptorPrototype = NSSortDescriptor(key: "tags", ascending: true)
        tableView.addTableColumn(column3)

        let column4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Rating"))
        column4.title = "Rating"
        column4.sortDescriptorPrototype = NSSortDescriptor(key: "rating", ascending: true)
        tableView.addTableColumn(column4)

        scrollView.documentView = tableView

        // Disable scroll bars
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay

        customizeTableView(tableView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let tableView = nsView.documentView as? NSTableView {
            tableView.sortDescriptors = sortOrder
        }
    }

    func findTableView(in view: NSView) -> NSTableView? {
        for subview in view.subviews {
            if let tableView = subview as? NSTableView {
                return tableView
            }
            if let foundView = findTableView(in: subview) {
                return foundView
            }
        }
        return nil
    }

    func customizeTableView(_ tableView: NSTableView) {
        for column in tableView.tableColumns {
            let headerTextColor = NSColor.white
            let customHeaderCell = CustomHeaderCell(textCell: column.headerCell.stringValue)
            customHeaderCell.textColor = headerTextColor
            column.headerCell = customHeaderCell
        }

        tableView.headerView?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, onSelect: onSelect, sortOrder: $sortOrder)
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        @Binding var sortOrder: [NSSortDescriptor]
        
        var onSelect: (_ model: DataModel) -> Void
        var parent: CustomTableView

        init(_ parent: CustomTableView, onSelect: @escaping (_ model: DataModel) -> Void, sortOrder: Binding<[NSSortDescriptor]>) {
            self.parent = parent
            self.onSelect = onSelect
            _sortOrder = sortOrder
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            return parent.data.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("CustomCell")

            guard let tableColumn = tableColumn else { return nil }

            let text: String
            switch tableColumn.identifier.rawValue {
            case "Name":
                text = parent.data[row].name
            case "Type":
                text = parent.data[row].type
            case "Tags":
                text = parent.data[row].tags
            case "Rating":
                text = parent.data[row].rating
            default:
                text = ""
            }

            let cell: CustomTableCellView
            if let existingCell = tableView.makeView(withIdentifier: identifier, owner: self) as? CustomTableCellView {
                cell = existingCell
            } else {
                cell = CustomTableCellView()
                cell.identifier = identifier
            }

            cell.configure(text: text)
            
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = CustomTableRowView()
            rowView.rowIndex = row
            return rowView
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            return 30
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            if let sortDescriptor = tableView.sortDescriptors.first {
                sortOrder = [sortDescriptor]
                parent.data = parent.data.sorted {
                    let lhs: String
                    let rhs: String
                    
                    switch sortDescriptor.key {
                    case "name":
                        lhs = $0.name
                        rhs = $1.name
                    case "type":
                        lhs = $0.type
                        rhs = $1.type
                    case "tags":
                        lhs = $0.tags
                        rhs = $1.tags
                    case "rating":
                        lhs = $0.rating
                        rhs = $1.rating
                    default:
                        return false
                    }
                    
                    return sortDescriptor.ascending ? lhs < rhs : lhs > rhs
                }
                tableView.reloadData()
            }
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 && selectedRow < parent.data.count {
                onSelect(parent.data[selectedRow])
            }
        }
    }
}

class CustomTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        // Set the background color for the header view
        NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 1.00).setFill()
        __NSRectFill(dirtyRect)
        
        // Draw the column dividers
        super.draw(dirtyRect)
        
        let path = NSBezierPath()
        let numberOfColumns = self.tableView?.numberOfColumns ?? 0
        for columnIndex in 0..<numberOfColumns {
            let columnRect = self.headerRect(ofColumn: columnIndex)
            path.move(to: NSPoint(x: columnRect.maxX, y: columnRect.minY))
            path.line(to: NSPoint(x: columnRect.maxX, y: columnRect.maxY))
        }
        NSColor.gray.setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }
}


class CustomHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Set the background color for the header cell
        NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 1.00).setFill()
        __NSRectFill(cellFrame)

        // Draw the text centered vertically and horizontally with custom padding
        let textRect = self.titleRect(forBounds: cellFrame)
        let textStyle = NSMutableParagraphStyle()
        textStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
            .paragraphStyle: textStyle
        ]

        let attributedString = NSAttributedString(string: self.stringValue, attributes: attributes)

        // Calculate the y position to center the text vertically
        let yOffset = (cellFrame.height - attributedString.size().height) / 2
        let textOrigin = NSPoint(x: textRect.origin.x, y: textRect.origin.y + yOffset)
        attributedString.draw(at: textOrigin)

        // Draw a border around the cell
        NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 1.00).setStroke()
        let borderRect = NSInsetRect(cellFrame, 0.5, 0.5)
        let borderPath = NSBezierPath(rect: borderRect)
        borderPath.lineWidth = 1.0
        borderPath.stroke()
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        // Adjust the titleRect to control padding
        let padding: CGFloat = 5.0
        let newRect = NSRect(x: rect.origin.x + padding, y: rect.origin.y, width: rect.width - 2 * padding, height: rect.height)
        return super.titleRect(forBounds: newRect)
    }
}



class CustomTableRowView: NSTableRowView {
    var rowIndex: Int = 0

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        let color: NSColor
        if rowIndex % 2 == 0 {
            color = NSColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)
        } else {
            color = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.2)
        }
        color.setFill()

        __NSRectFill(dirtyRect)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if self.selectionHighlightStyle != .none {
//            NSColor(red: 0.93, green: 0.92, blue: 0.92, alpha: 1.00).setFill()
//            NSColor(red: 0.19, green: 0.22, blue: 0.30, alpha: 1.00).setFill()
            NSColor(red: 0.39, green: 0.50, blue: 0.84, alpha: 1.00).setFill()
            __NSRectFill(dirtyRect)
        }
    }

    override func drawSeparator(in dirtyRect: NSRect) {
        let separatorColor = NSColor.gray
        separatorColor.setFill()
        let separatorRect = NSRect(x: dirtyRect.origin.x, y: dirtyRect.maxY - 1, width: dirtyRect.width, height: 1)
        __NSRectFill(separatorRect)
    }
}

class CustomTableCellView: NSTableCellView {
    var customTextField: NSTextField = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        customTextField = NSTextField()
        customTextField.isBordered = false
        customTextField.isEditable = false
        customTextField.backgroundColor = .clear
        customTextField.translatesAutoresizingMaskIntoConstraints = false
        customTextField.textColor = .white
        customTextField.alignment = .left
        customTextField.lineBreakMode = .byTruncatingTail
        customTextField.drawsBackground = false

        addSubview(customTextField)

        NSLayoutConstraint.activate([
            customTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            customTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            customTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(text: String) {
        customTextField.stringValue = text
    }
}


struct CustomRowView: View {
    var text: String

    var body: some View {
        HStack {
            Text(text)
            Spacer()
        }
        .padding()
    }
}
