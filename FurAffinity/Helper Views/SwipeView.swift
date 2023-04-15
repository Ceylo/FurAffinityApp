//
//  SwipeView.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import CoreHaptics

let supportHaptics = CHHapticEngine
    .capabilitiesForHardware()
    .supportsHaptics
let hapticsEngine = try! CHHapticEngine()

struct SwipeView<FrontView: View, BackView: View>: View {
    private let frontContent: () -> FrontView
    private let backContent: () -> BackView
    private let onAction: () -> ()
    private let backgroundColor: Color
    
    @State private var offset = CGSize.zero
    @State private var swipedBeyondThreshold = false
    
    init(backgroundColor: Color,
         @ViewBuilder frontContent: @escaping () -> FrontView,
         @ViewBuilder backContent: @escaping () -> BackView,
         onAction: @escaping () -> Void) {
        self.backgroundColor = backgroundColor
        self.frontContent = frontContent
        self.backContent = backContent
        self.onAction = onAction
    }
    
    var body: some View {
        ZStack {
            HStack {
                Spacer()
                    .frame(width: 10)
                
                HStack {
                    Spacer()
                    backContent()
                }
                .background(backgroundColor)
            }
            
            frontContent()
                .offset(offset)
            // minimumDistance 30 to prevent drag gesture from breaking scroll
                .gesture(DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onChanged { gesture in
                        offset.width = min(0, gesture.translation.width)
                        
                        let fullWidth = UIScreen.main.bounds.width
                        let newSwipedBeyondThreshold = abs(offset.width) > fullWidth / 4
                        if swipedBeyondThreshold != newSwipedBeyondThreshold {
                            swipedBeyondThreshold = newSwipedBeyondThreshold
                            Task.detached {
                                try hapticFeedback()
                            }
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.width < 0 {
                            withAnimation(.spring()) {
                                self.offset = .zero
                            }
                            
                            if swipedBeyondThreshold {
                                onAction()
                                swipedBeyondThreshold = false
                            }
                        }
                    }
                )
        }
    }
    
    func hapticFeedback() throws {
        try signposter.withIntervalSignpost(#function) {
            guard supportHaptics else { return }
            let hapticDict = [
                CHHapticPattern.Key.pattern: [
                    [CHHapticPattern.Key.event: [
                        CHHapticPattern.Key.eventType: CHHapticEvent.EventType.hapticTransient,
                        CHHapticPattern.Key.time: CHHapticTimeImmediate,
                        CHHapticPattern.Key.eventDuration: 1.0
                    ] as [CHHapticPattern.Key : Any]
                    ]
                ]
            ]
            
            let pattern = try CHHapticPattern(dictionary: hapticDict)
            let player = try hapticsEngine.makePlayer(with: pattern)
            hapticsEngine.notifyWhenPlayersFinished { error in
                return .stopEngine
            }
            
            try hapticsEngine.start()
            try player.start(atTime: 0)
        }
    }
}

struct SwipeView_Previews: PreviewProvider {
    static var previews: some View {
        SwipeView(backgroundColor: .blue) {
            HStack {
                Spacer()
                Text("Swipe me")
                Spacer()
            }
            .background(.pink)
        } backContent: {
            Text("hello")
        } onAction: {
            print("action!")
        }
        .padding()
    }
}
