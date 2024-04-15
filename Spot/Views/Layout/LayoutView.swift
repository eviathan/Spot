//
//  LayoutView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct LayoutView: View {
    
    let headerHeight: CGFloat = 80
    let footerHeight: CGFloat = 50
    
    var body: some View {
        VStack(alignment:.leading, spacing: 0) {
            Header()
                .frame(maxWidth: .infinity, maxHeight: headerHeight)
                

            InstrumentView()
                .frame(maxWidth: .infinity)

            TabView ()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Footer()
                .frame(maxWidth: .infinity, minHeight: footerHeight, maxHeight: footerHeight)
        }
        .edgesIgnoringSafeArea(.all)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LayoutView_Previews: PreviewProvider {
    static var previews: some View {
        LayoutView()
    }
}
