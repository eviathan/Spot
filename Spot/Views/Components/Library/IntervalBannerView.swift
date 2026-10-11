//
//  IntervalBannerView.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI
import SpotCore

struct IntervalBannerView: View {
    @Environment(\.theme) private var theme
    
    var degrees: [Degree]
    
    @State var markerSize: CGFloat = 30;
    
    func drawMarker(_ label: String, markerColor: Color) -> some View {
        return ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: markerSize, height: markerSize)
            Circle()
                .stroke(markerColor, lineWidth: 5)
                .frame(width: markerSize - 4, height: markerSize - 4)
            Text(label)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(degrees, id: \.self) { degree in
                drawMarker(degree.intervalName, markerColor: theme.intervalColors[degree.pitchClassOffset])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
