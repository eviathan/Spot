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
    let tags: String = ""
    let rating: String = ""
}

struct TableView: View {
    @State private var selection: UUID? = nil
    
    var body: some View {
        CustomTableView(data: [
            DataModel(name: "Major", type: "Scale"),
            DataModel(name: "Ionian", type: "Mode"),
            DataModel(name: "Dorian", type: "Mode"),
            DataModel(name: "Phrygian", type: "Mode"),
            DataModel(name: "Lydian", type: "Mode"),
            DataModel(name: "Mixolydian", type: "Mode"),
            DataModel(name: "Aeolian", type: "Mode"),
            DataModel(name: "Locrian", type: "Mode"),
            DataModel(name: "Blues", type: "Scale"),
            DataModel(name: "Minor", type: "Scale"),
            DataModel(name: "Pentatonic", type: "Scale"),
            DataModel(name: "Chromatic", type: "Scale"),
            DataModel(name: "Wholetone", type: "Scale"),
            DataModel(name: "Maj7", type: "Chord"),
            DataModel(name: "Maj", type: "Chord"),
            DataModel(name: "Min", type: "Chord"),
            DataModel(name: "Dim", type: "Chord"),
            DataModel(name: "Maj7b5", type: "Chord"),
            DataModel(name: "M7", type: "Chord")
        ])
        .background(Color(hue: 0.63, saturation: 0.28, brightness: 0.20, opacity: 1.00))
        .tableStyle(BorderedTableStyle())
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
    }
}

struct CustomTableView: NSViewRepresentable {
    @State var data: [DataModel]
    @State private var sortOrder: [NSSortDescriptor] = []

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        scrollView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)
        tableView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

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
        if let headerView = tableView.headerView {
            headerView.wantsLayer = true
            headerView.layer?.backgroundColor = CGColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)
        }

        for column in tableView.tableColumns {
            let headerTextColor = NSColor.white
            let customHeaderCell = CustomHeaderCell(textCell: column.headerCell.stringValue)
            customHeaderCell.textColor = headerTextColor
            column.headerCell = customHeaderCell
        }

        tableView.headerView?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, sortOrder: $sortOrder)
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        @Binding var sortOrder: [NSSortDescriptor]
        var parent: CustomTableView

        init(_ parent: CustomTableView, sortOrder: Binding<[NSSortDescriptor]>) {
            self.parent = parent
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

            if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? CustomTableCellView {
                cell.configure(text: text)
                return cell
            } else {
                let cell = CustomTableCellView()
                cell.identifier = identifier
                cell.configure(text: text)
                return cell
            }
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
    }
}

class CustomHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Set the background color for the header cell
        NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.20, alpha: 1.00).set()
        __NSRectFill(cellFrame)

        // Draw the text centered vertically
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
            NSColor(red: 0.19, green: 0.22, blue: 0.31, alpha: 1.00).setFill()
            __NSRectFill(dirtyRect)
        }
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
