//
//  TabView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct TabView: View {
    var body: some View {
        Text("Tab View")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color.green)
    }
}

struct TabView_Previews: PreviewProvider {
    static var previews: some View {
        TabView()
    }
}
