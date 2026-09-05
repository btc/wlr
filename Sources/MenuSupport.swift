import AppKit

/// NSMenuItem that calls a closure, so the menu can be built declaratively in one place
/// instead of scattered across @objc selectors.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(
        title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        state: NSControl.StateValue = .off,
        enabled: Bool = true,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        self.target = self
        self.keyEquivalentModifierMask = modifiers
        self.state = state
        self.isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func fire() { handler() }
}

/// A labelled slider hosted inside a menu item. Dragging keeps the menu open and reports
/// continuously, so the effect of the slider is visible while it is being moved.
final class SliderMenuItemView: NSView {
    private let slider = NSSlider()
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let title: String
    private let onChange: (Double) -> Void

    init(
        title: String, minValue: Double, maxValue: Double, value: Double,
        onChange: @escaping (Double) -> Void
    ) {
        self.title = title
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 46))

        titleLabel.font = .menuFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.stringValue = title

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = value
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)

        for view in [titleLabel, valueLabel, slider] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
        ])

        updateValueLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func sliderMoved() {
        updateValueLabel()
        onChange(slider.doubleValue)
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
    }
}
