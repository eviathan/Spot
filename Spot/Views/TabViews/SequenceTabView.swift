//
//  SequenceTabView.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

/// Sequences open in their own windows; this tab starts or reopens one.
struct SequenceTabView: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(UIState.self) private var ui

    @State private var recent: [URL] = []

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Sequences")
                    .font(.largeTitle)
                Text("Put chords on a timeline, play them back and see what to play over each one. Each sequence is a .spot file and opens in its own window.")
                    .multilineTextAlignment(.center)
                    .opacity(0.7)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 16) {
                Button {
                    newDocument(SequenceDocument())
                } label: {
                    Label("New Sequence", systemImage: "plus")
                        .frame(minWidth: 160)
                }

                Button {
                    NSDocumentController.shared.openDocument(nil)
                } label: {
                    Label("Open…", systemImage: "folder")
                        .frame(minWidth: 160)
                }
            }
            .controlSize(.large)

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                    ForEach(recent, id: \.self) { url in
                        Button {
                            Task {
                                do {
                                    try await openDocument(at: url)
                                } catch {
                                    ui.errorMessage = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
                                }
                            }
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "music.note.list")
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            recent = NSDocumentController.shared.recentDocumentURLs.filter { $0.pathExtension == "spot" }
        }
    }
}
