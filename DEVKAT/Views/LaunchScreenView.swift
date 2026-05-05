import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Image("CatIcon")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Text("DEVKAT")
                .font(.custom("LEDLIGHT", size: 36).weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}
