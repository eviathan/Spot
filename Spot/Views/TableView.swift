//
//  TableView.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import SwiftUI

struct Person: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let tags: String

    var fullName: String { name + " " + type }
}

struct DataModel: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let tags: String = ""
    let rating: String = ""
}

struct TableView: View {
    @State private var selection: UUID? = nil
    
    @State private var people = [
        Person(name: "Major", type: "Scale", tags: "bright, happy"),
        Person(name: "Min7b5", type: "Chord", tags: "sad, dark"),
        Person(name: "Pentatonic", type: "Scale", tags: ""),
        Person(name: "Blues", type: "Scale", tags: "gitakumar@icloud.com")
    ]
    
    var body: some View {
//        Table(people, selection: $selection) {
//            TableColumn("Name") { user in
//                Text(user.name)
//                    .foregroundColor(.white)
//            }
//            TableColumn("Type", value: \.type)
//            TableColumn("Tags", value: \.tags)
//        }
//        .background(.black)
//        .foregroundColor(.white)
//        .tableStyle(BorderedTableStyle())
//        .scrollContentBackground(.hidden)
//        .scrollIndicators(.never)
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
//        .foregroundColor(.white)
        .tableStyle(BorderedTableStyle())
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
    }
}


struct CustomTableView: NSViewRepresentable {
    var data: [DataModel]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        scrollView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)
        tableView.backgroundColor = NSColor(red: 0.14, green: 0.15, blue: 0.20, alpha: 1.00)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let column1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        column1.title = "Name"
        tableView.addTableColumn(column1)

        let column2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Type"))
        column2.title = "Type"
        tableView.addTableColumn(column2)
        
        let column3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Tags"))
        column3.title = "Tags"
        tableView.addTableColumn(column3)
        
        let column4 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Rating"))
        column4.title = "Rating"
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

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

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
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: CustomTableView

        init(_ parent: CustomTableView) {
            self.parent = parent
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
            default:
                text = ""
            }

            if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSHostingView<CustomRowView> {
                cell.rootView = CustomRowView(text: text)
                return cell
            } else {
                let cell = NSHostingView(rootView: CustomRowView(text: text))
                cell.identifier = identifier
                return cell
            }
        }


        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = CustomTableRowView()
            rowView.rowIndex = row
            return rowView
        }
    }

    struct Content: View {
        var data: [DataModel]

        var body: some View {
            Table(data) {
                TableColumn("Name", value: \.name)
                TableColumn("Type", value: \.type)
                TableColumn("Tags", value: \.tags)
                TableColumn("Rating", value: \.rating)
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
        
//        NSColor(red: 0, green: 0, blue: 0, alpha: 0.2).setFill()
        
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

struct CustomRowView: View {
    var text: String
    
    var body: some View {
        HStack {
            Text(text)
            Spacer()
//            HStack {
//                Image(systemName: "star.fill")
//                Image(systemName: "star.fill")
//                Image(systemName: "star.fill")
//                Image(systemName: "star")
//                Image(systemName: "star")
//            }
            
        }
        .padding()
    }
}
