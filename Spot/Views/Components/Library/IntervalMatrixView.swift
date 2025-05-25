//
//  IntervalBannerView.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI

struct IntervalMatrixView: View {
    
    var key: Note = .A
    var scale: ScaleType = .Major
    var chordStyle: ChordStyle = .Triad
    var theme: Theme
    
    @State var markerSize: CGFloat = 30;
    
    private func getChordIntervals(_ index: Int) -> [Interval] {
        return []
    }
    
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
        VStack(spacing: 0) {
            ForEach(0..<chordStyle.rawValue, id: \.self) { chordIndex in
                HStack(spacing: 4) {
                    ForEach(getChordIntervals(chordIndex)) { interval in
                        drawMarker(interval.description, markerColor: theme.intervalColors[interval.noteIndex])
                    }
                }
                .padding([.vertical], 4)
            }
        }
        .padding([.top], 4)
        .padding([.bottom], 12)
        .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
        .background(Color(hue: 1.00, saturation: 0.00, brightness: 0.93, opacity: 1.00))
        
    }
}
