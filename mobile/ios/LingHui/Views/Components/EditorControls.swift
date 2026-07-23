import SwiftUI

struct ModeTabs: View {
    @Binding var selectedMode: EditorMode
    let onSelect: (EditorMode) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(EditorMode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(mode.shortTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selectedMode == mode ? .white : LHTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedMode == mode ? LHTheme.ink : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(LHTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LHTheme.hairline, lineWidth: 1)
        }
    }
}

struct CapsulePicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let symbol: ((Option) -> String)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol {
                            Image(systemName: symbol(option))
                        }
                        Text(title(option))
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(selection == option ? .white : LHTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(selection == option ? LHTheme.repairBlue : LHTheme.mist)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HoldToCompareButton: View {
    @Binding var isShowingOriginal: Bool

    var body: some View {
        Label("按住看原图", systemImage: "eye")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(isShowingOriginal ? .white : LHTheme.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(isShowingOriginal ? LHTheme.ink : LHTheme.mist)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isShowingOriginal = true }
                    .onEnded { _ in isShowingOriginal = false }
            )
            .accessibilityLabel("按住显示原图")
    }
}

struct ComparisonSlider: View {
    @Binding var position: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let knobSize: CGFloat = 22
            let usableWidth = max(1, proxy.size.width - knobSize)
            let knobX = knobSize / 2 + usableWidth * position

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LHTheme.hairline)
                    .frame(height: 6)

                Capsule()
                    .fill(LHTheme.repairBlue)
                    .frame(width: max(3, knobX), height: 6)

                Circle()
                    .fill(LHTheme.paper)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Circle().stroke(LHTheme.repairBlue, lineWidth: 3)
                    }
                    .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                    .position(x: knobX, y: proxy.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        position = min(
                            max((value.location.x - knobSize / 2) / usableWidth, 0),
                            1
                        )
                    }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("原图与修复结果对比")
        .accessibilityValue("\(Int(position * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                position = min(position + 0.05, 1)
            case .decrement:
                position = max(position - 0.05, 0)
            @unknown default:
                break
            }
        }
    }
}
