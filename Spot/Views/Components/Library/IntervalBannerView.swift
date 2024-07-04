//
//  IntervalBannerView.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI

struct IntervalBannerView: View {
    
    var intervals: [Interval]
    var theme: Theme
    
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
        HStack(spacing: 4) {
            ForEach(intervals) { interval in
                drawMarker(interval.description, markerColor: theme.intervalColors[interval.noteIndex])
            }
        }
        .padding([.top], 4)
        .padding([.bottom], 12)
        .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
        .background(Color(hue: 1.00, saturation: 0.00, brightness: 0.93, opacity: 1.00))
    }
}
