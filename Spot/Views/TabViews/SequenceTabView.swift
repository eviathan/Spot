//
//  SequenceTabView.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

/// The open sequence, or a way to start or open one.
struct SequenceTabView: View {
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui

    var body: some View {
        if session.isOpen {
            SequenceEditorView()
        } else {
            launcher
        }
    }

    private var launcher: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Sequences")
                    .font(.largeTitle)
                Text("Put chords on a timeline, play them back and see what to play over each one. Each sequence is saved as a .spot file.")
                    .multilineTextAlignment(.center)
                    .opacity(0.7)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 16) {
                Button {
                    ui.requestSequenceAction(.new, session: session)
                } label: {
                    Label("New Sequence", systemImage: "plus")
                        .frame(minWidth: 160)
                }

                Button {
                    ui.requestSequenceAction(.open, session: session)
                } label: {
                    Label("Open…", systemImage: "folder")
                        .frame(minWidth: 160)
                }
            }
            .controlSize(.large)

            if !session.recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                    ForEach(session.recents) { recent in
                        HStack {
                            Button {
                                ui.requestSequenceAction(.openRecent(recent), session: session)
                            } label: {
                                Label(recent.name, systemImage: "music.note.list")
                            }
                            .buttonStyle(.link)
                            Spacer()
                            Button {
                                session.removeRecent(recent)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .opacity(0.5)
                            .help("Remove from this list")
                        }
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
