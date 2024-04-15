//
//  TabView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct TabView: View {
    let backgroundColor = Color(hue: 0.62, saturation: 0.38, brightness: 0.24, opacity: 1.00)
    
    var body: some View {
        Text("Tab View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(backgroundColor)
    }
}

struct TabView_Previews: PreviewProvider {
    static var previews: some View {
        TabView()
    }
}
