//
//  Header.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct Header: View {
    var body: some View {
        Text("Header")
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .padding(.bottom, 1)
    }
}

struct Header_Previews: PreviewProvider {
    static var previews: some View {
        Header()
    }
}
