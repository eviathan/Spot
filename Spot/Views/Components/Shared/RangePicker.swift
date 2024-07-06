//
//  RangePicker.swift
//  Spot
//
//  Created by Brian Williams on 05/07/2024.
//

import SwiftUI

struct RangePicker<Data, Content>: View where 
        Data: RandomAccessCollection,
        Content: View, Data.Element: Equatable  {
    
    @State private var currentIndex: Data.Index
    @State var leftButtonHovered: Bool = false
    @State var rightButtonHovered: Bool = false
    
    var data: Data
    var onDecrement: () -> Void
    var onIncrement: () -> Void
    let content: (Data.Element) -> Content

    let unselectedColor: Color = Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00)
    
    init(data: Data, onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
        self.content = content
        _currentIndex = State(initialValue: data.startIndex)
    }

    var body: some View {
        HStack {
            Button(action: { onDecrement() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16))
                    .foregroundColor(leftButtonHovered ? .white : unselectedColor)
            }
            .onHover(perform: { hovered in
                leftButtonHovered = hovered
            })
            .buttonStyle(.plain)

            content(data[currentIndex])
            
            Button(action: { onIncrement() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundColor(rightButtonHovered ? .white : unselectedColor)
            }
            .onHover(perform: { hovered in
                rightButtonHovered = hovered
            })
            .buttonStyle(.plain)
        }
    }
}
