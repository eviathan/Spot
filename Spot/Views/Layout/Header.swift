//
//  Header.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct Header: View {
    @EnvironmentObject var appState: AppState
    
    let backgroundColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    
    func dragWindow(value: DragGesture.Value) {
        let window = NSApplication.shared.windows.first
        let currentLocation = window?.frame.origin ?? CGPoint.zero
        window?.setFrameOrigin(
            CGPoint(x: currentLocation.x + value.translation.width,
                    y: currentLocation.y - value.translation.height)
        )
    }
    
    var body: some View {
        HStack {
            Text("♮")
                .font(.system(size: 36))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(backgroundColor)
                .foregroundColor(.white)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            self.dragWindow(value: value)
                        }
                )
        }
        
    }
}

struct Header_Previews: PreviewProvider {
    static var previews: some View {
        Header()
    }
}
