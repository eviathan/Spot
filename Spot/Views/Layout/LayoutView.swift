//
//  LayoutView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct LayoutView: View {
    
    let headerHeight: CGFloat = 50
    let footerHeight: CGFloat = 50
    
    var body: some View {
        VStack(spacing: 0) {
            Header()
                .frame(maxWidth: .infinity)

            InstrumentView()
                .frame(maxWidth: .infinity)

            TabView ()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Footer()
                .frame(maxWidth: .infinity, minHeight: footerHeight, maxHeight: footerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LayoutView_Previews: PreviewProvider {
    static var previews: some View {
        LayoutView()
    }
}
