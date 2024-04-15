//
//  Header.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct Header: View {
    let backgroundColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    
    var body: some View {
        Text("Spot")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(backgroundColor)
            .foregroundColor(.white)
    }
}

struct Header_Previews: PreviewProvider {
    static var previews: some View {
        Header()
    }
}
