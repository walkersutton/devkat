import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Image("CatIcon")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Subtle dark overlay so the text pops
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            Text("DEVKAT")
                .font(.custom("LEDLIGHT", size: 36).weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}
