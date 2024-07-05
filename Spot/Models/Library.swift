//
//  Library.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import Foundation

class Library: ObservableObject {
    @Published var items: [LibraryItem] = []
    @Published var query: String? = nil
    
    let fuse: Fuse = Fuse()
    
    init() {
        refresh()
    }
    
    func refresh() {
        items = getItems()
    }
    
    func getItems() -> [LibraryItem] {
         var output: [LibraryItem] = []
        
        for scale in ScaleType.allCases {
            let item = LibraryItem(name: scale.description, type: .Scale)
            item.scaleType = scale
            output.append(item)
        }
        
        for chord in ChordType.allCases {
            let item = LibraryItem(name: chord.description, type: .Chord)
            item.chordType = chord
            output.append(item)
        }
        
        output.append(contentsOf: getIntervals())
        
        if(query == nil || query!.isEmpty) {
            return output
        }
        
        if let query = query, !query.isEmpty {
            let results = fuse.searchSync(query, in: output, by: \LibraryItem.properties)
            return results.map { result in output[result.index] }
        }
        
        return []
    }
    
    private func getIntervals() -> [LibraryItem] {
        return [
            LibraryItem(name: Interval.I.prettyName, type: .Interval),
            LibraryItem(name: Interval.bII.prettyName, type: .Interval),
            LibraryItem(name: Interval.II.prettyName, type: .Interval),
            LibraryItem(name: Interval.bIII.prettyName, type: .Interval),
            LibraryItem(name: Interval.III.prettyName, type: .Interval),
            LibraryItem(name: Interval.IV.prettyName, type: .Interval),
            LibraryItem(name: Interval.TT.prettyName, type: .Interval),
            LibraryItem(name: Interval.V.prettyName, type: .Interval),
            LibraryItem(name: Interval.bVI.prettyName, type: .Interval),
            LibraryItem(name: Interval.VI.prettyName, type: .Interval),
            LibraryItem(name: Interval.bVII.prettyName, type: .Interval),
            LibraryItem(name: Interval.VII.prettyName, type: .Interval),
        ]
    }
}
