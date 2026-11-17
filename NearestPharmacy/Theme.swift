import CoreText
import SwiftUI

/// The FireRed/LeafGreen battle-screen look: teal dialogue box with a gold frame, cream info panels with
/// a dark olive border, HP-style bars and a pixel font.
enum Theme {
    static let panel = Color(red: 248 / 255, green: 248 / 255, blue: 216 / 255)
    static let panelBorder = Color(red: 64 / 255, green: 80 / 255, blue: 64 / 255)
    static let panelShadow = Color(red: 104 / 255, green: 136 / 255, blue: 112 / 255)
    static let panelText = Color(red: 64 / 255, green: 64 / 255, blue: 64 / 255)
    static let panelTextShadow = Color(red: 216 / 255, green: 208 / 255, blue: 176 / 255)
    static let muted = Color(red: 104 / 255, green: 112 / 255, blue: 96 / 255)
    static let dialogue = Color(red: 40 / 255, green: 80 / 255, blue: 104 / 255)
    static let dialogueTextShadow = Color(red: 104 / 255, green: 96 / 255, blue: 120 / 255)
    static let gold = Color(red: 200 / 255, green: 168 / 255, blue: 80 / 255)
    static let goldDark = Color(red: 120 / 255, green: 96 / 255, blue: 48 / 255)
    static let frameLight = Color(red: 232 / 255, green: 232 / 255, blue: 240 / 255)
    static let link = Color(red: 248 / 255, green: 216 / 255, blue: 112 / 255)
    static let red = Color(red: 232 / 255, green: 48 / 255, blue: 48 / 255)
    static let hpLabel = Color(red: 248 / 255, green: 168 / 255, blue: 0)
    static let hpGreen = Color(red: 112 / 255, green: 248 / 255, blue: 168 / 255)
    static let hpYellow = Color(red: 248 / 255, green: 208 / 255, blue: 56 / 255)
    static let hpRed = Color(red: 248 / 255, green: 88 / 255, blue: 56 / 255)

    /// Pixelify Sans (SIL Open Font License), bundled in Fonts/ and registered at launch.
    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Pixelify Sans", size: size, relativeTo: style)
    }

    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "PixelifySans", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension View {
    /// Cream info panel, like the name and HP boxes in battle.
    func panel(padding: CGFloat = 16) -> some View {
        self
            .shadow(color: Theme.panelTextShadow, radius: 0, x: 1.5, y: 1.5)
            .foregroundStyle(Theme.panelText)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.panelBorder, lineWidth: 4))
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelShadow).offset(x: 8, y: 8))
    }

    /// Teal dialogue box with a gold frame, like the text box at the bottom of the screen.
    func dialogue(padding: CGFloat = 16) -> some View {
        self
            .shadow(color: Theme.dialogueTextShadow, radius: 0, x: 2, y: 2)
            .foregroundStyle(.white)
            .tint(Theme.link)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.dialogue, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.frameLight, lineWidth: 3).padding(5))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.gold, lineWidth: 5))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.goldDark, lineWidth: 1.5))
    }
}

/// Buttons look like small dialogue boxes.
struct DialogueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(17, relativeTo: .headline).weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .dialogue(padding: 0)
            .fixedSize()
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}

/// A sprite drawn with whole-number scaling and no smoothing, so the pixels stay crisp.
struct Sprite: View {
    let name: String
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        Image(name)
            .interpolation(.none)
            .resizable()
            .frame(width: size.width * scale, height: size.height * scale)
            .accessibilityHidden(true)
    }

    static func nurseJoy(scale: CGFloat) -> Sprite { Sprite(name: "NurseJoy", size: CGSize(width: 16, height: 20), scale: scale) }
}

/// Nurse Joy next to a dialogue box, with the little red "more" arrow in the corner.
struct JoySays<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: Actions

    init(_ message: String, @ViewBuilder actions: () -> Actions) {
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            HStack(alignment: .bottom, spacing: 12) {
                Sprite.nurseJoy(scale: 5)
                Text(message)
                    .font(Theme.font(19))
                    .lineSpacing(6)
                    .padding(.bottom, 10)
                    .dialogue(padding: 18)
                    .overlay(alignment: .bottomTrailing) { MoreArrow().padding(14) }
            }
            actions
        }
    }
}

extension JoySays where Actions == EmptyView {
    init(_ message: String) {
        self.init(message) { EmptyView() }
    }
}

private struct MoreArrow: View {
    @State private var down = false

    var body: some View {
        Triangle()
            .fill(Theme.red)
            .frame(width: 14, height: 9)
            .offset(y: down ? 3 : 0)
            .animation(.easeInOut(duration: 0.3).repeatForever(), value: down)
            .onAppear { down = true }
            .accessibilityHidden(true)
    }
}

/// Downward triangle for the "more" arrow.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// The queue drawn exactly like an HP bar: full at `full` people.
struct QueueBar: View {
    let crowd: Crowd
    static let full = 9

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 0) {
                Text("QUEUE")
                    .font(Theme.font(13).weight(.bold))
                    .foregroundStyle(Theme.hpLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.panelBorder, in: UnevenRoundedRectangle(topLeadingRadius: 99, bottomLeadingRadius: 99))
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * min(1, CGFloat(crowd.people) / CGFloat(Self.full))))
                }
                .frame(height: 8)
                .padding(3)
                .background(.white, in: UnevenRoundedRectangle(bottomTrailingRadius: 99, topTrailingRadius: 99))
                .overlay(UnevenRoundedRectangle(bottomTrailingRadius: 99, topTrailingRadius: 99).strokeBorder(Theme.panelBorder, lineWidth: 3))
            }
            Text(text).font(Theme.font(15))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Queue: \(text)")
    }

    private var text: String {
        let label = crowd.level.label
        guard crowd.people > 0 else { return "\(label) · no queue" }
        return "\(label) · ~\(crowd.people) \(crowd.people == 1 ? "person" : "people"), ~\(crowd.waitMinutes) min wait"
    }

    private var color: Color {
        switch crowd.level {
        case .quiet: Theme.hpGreen
        case .moderate: Theme.hpYellow
        case .busy: Theme.hpRed
        }
    }
}

extension Crowd.Level {
    var label: String {
        switch self {
        case .quiet: "Quiet"
        case .moderate: "A bit busy"
        case .busy: "Busy"
        }
    }
}
