//
//  Footer.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct Footer: View {
    let backgroundColor = Color(hue: 0.62, saturation: 0.38, brightness: 0.20, opacity: 1.00)
    
    var body: some View {
        Text("Footer")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(backgroundColor)
    }
}

struct Footer_Previews: PreviewProvider {
    static var previews: some View {
        Footer()
    }
}
