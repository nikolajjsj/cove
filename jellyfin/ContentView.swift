//
//  ContentView.swift
//  jellyfin
//
//  Created by neo on 05/04/2026.
//

import Models
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.circle.fill")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Cove")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Media client for Jellyfin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
