//
//  NoteCollectiontype.swift
//  Spot
//
//  Created by Brian Williams on 20/04/2024.
//

import Foundation

protocol NoteCollection : Hashable {
    var intervals: [Interval] { get }
    
    func getNotes(_ key: Note, inversion: Inversion) -> [Note]
}
