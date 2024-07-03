//
//  Footer.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct Footer: View {
    @EnvironmentObject var appState: AppState
    let backgroundColor = Color(hue: 0.62, saturation: 0.34, brightness: 0.20, opacity: 1.00)
    
    var body: some View {
        HStack {
            Spacer()
            ModeSwitcher()
            Spacer()
            Transport()
            Spacer()
            HStack {
                Image(systemName: "tuningfork")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                Text(appState.selectedNote.longDescription)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(backgroundColor)
        .foregroundColor(.white)
    }
}

struct Footer_Previews: PreviewProvider {
    static var previews: some View {
        Footer()
    }
}
