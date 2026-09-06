import AppKit

// ENGINE-OWNED · The Tasks board: columns of sticky notes.
// Add with the field at the top of a column; click a note to edit title/text;
// ◀ ▶ move between columns; ● cycles colour; ✕ deletes. Saves on every change.

final class TasksPage: NSView {
    private var handlers: [Handler] = []
    private var columnsStack = NSStackView()
    private var observer: Any?
    private var focusTaskId: String?
    private var titleFields: [String: NSTextField] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        observer = NotificationCenter.default.addObserver(forName: .tasksChanged, object: nil, queue: .main) { [weak self] _ in self?.build() }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    private func bind<T: NSControl>(_ c: T, _ fn: @escaping (T) -> Void) -> T {
        let h = Handler { fn($0 as! T) }; handlers.append(h); c.target = h; c.action = #selector(Handler.fire(_:)); return c
    }

    func build() {
        handlers.removeAll()
        subviews.forEach { $0.removeFromSuperview() }
        let store = TaskStore.shared

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([root.topAnchor.constraint(equalTo: topAnchor), root.leadingAnchor.constraint(equalTo: leadingAnchor),
                                     root.trailingAnchor.constraint(equalTo: trailingAnchor), root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)])

        let title = NSTextField(labelWithString: "Tasks")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        root.addArrangedSubview(title)

        // the pad: a small stack of blank notes; click one and it lands in Today with the caret in it
        let pad = NSStackView(); pad.orientation = .horizontal; pad.spacing = 10; pad.alignment = .centerY
        let padLabel = NSTextField(labelWithString: "New note"); padLabel.font = .systemFont(ofSize: 12, weight: .medium); padLabel.textColor = .secondaryLabelColor
        pad.addArrangedSubview(padLabel)
        for (i, c) in TaskStore.colors.enumerated() {
            let b = bind(PadNoteButton(color: NSColor(hex: c.hex))) { [weak self] _ in
                let t = TaskStore.shared.add(title: "", column: "Today", color: i)
                self?.focusTaskId = t.id
            }
            b.toolTip = "New \(c.name) note"
            pad.addArrangedSubview(b)
        }
        root.addArrangedSubview(pad)
        root.setCustomSpacing(18, after: pad)

        columnsStack = NSStackView()
        columnsStack.orientation = .horizontal
        columnsStack.alignment = .top
        columnsStack.distribution = .fillEqually
        columnsStack.spacing = 14
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(columnsStack)
        columnsStack.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true

        titleFields = [:]
        for (ci, col) in store.columns.enumerated() {
            let colView = NSStackView()
            colView.orientation = .vertical
            colView.alignment = .leading
            colView.distribution = .fill
            colView.spacing = 10
            colView.setHuggingPriority(.required, for: .vertical)
            let headRow = NSStackView(); headRow.orientation = .horizontal; headRow.spacing = 6; headRow.alignment = .centerY
            let head = NSTextField(labelWithString: col)
            head.font = .systemFont(ofSize: 13, weight: .semibold)
            let count = NSTextField(labelWithString: "\(store.tasks(in: col).count)")
            count.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            count.textColor = .secondaryLabelColor
            count.wantsLayer = true
            count.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            count.layer?.cornerRadius = 7
            count.alignment = .center
            count.translatesAutoresizingMaskIntoConstraints = false
            count.widthAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
            headRow.addArrangedSubview(head); headRow.addArrangedSubview(count)
            colView.addView(headRow, in: .top)

            // add row
            let addRow = NSStackView(); addRow.orientation = .horizontal; addRow.spacing = 6
            let field = NSTextField(string: "")
            field.placeholderString = "New task, press ⏎"
            field.font = .systemFont(ofSize: 12)
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
            _ = bind(field) { f in
                let t = f.stringValue.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                TaskStore.shared.add(title: t, column: col)
            }
            addRow.addArrangedSubview(field)
            colView.addView(addRow, in: .top)

            for t in store.tasks(in: col) {
                colView.addView(sticky(t, columnIndex: ci, columns: store.columns), in: .top)
            }
            columnsStack.addArrangedSubview(colView)
        }
        // a note just taken from the pad: start typing on it right away
        if let id = focusTaskId, let f = titleFields[id] {
            focusTaskId = nil
            DispatchQueue.main.async { [weak self, weak f] in
                guard let f = f else { return }
                self?.window?.makeFirstResponder(f)
                f.currentEditor()?.selectAll(nil)
            }
        }
    }

    private func sticky(_ t: Task, columnIndex ci: Int, columns: [String]) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        let hex = TaskStore.colors[min(t.color, TaskStore.colors.count - 1)].hex
        box.layer?.backgroundColor = NSColor(hex: hex).cgColor
        box.layer?.cornerRadius = 3
        box.layer?.shadowOpacity = 0.22
        box.layer?.shadowOffset = CGSize(width: 1, height: -2)
        box.layer?.shadowRadius = 2
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        let v = NSStackView()
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 6
        v.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: box.topAnchor), v.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                                     v.leadingAnchor.constraint(equalTo: box.leadingAnchor), v.trailingAnchor.constraint(equalTo: box.trailingAnchor)])

        let title = NSTextField(string: t.title)
        title.placeholderString = "Write the task…"
        titleFields[t.id] = title
        title.isBordered = false; title.drawsBackground = false
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .black
        title.lineBreakMode = .byWordWrapping; title.cell?.wraps = true; title.cell?.isScrollable = false
        title.preferredMaxLayoutWidth = 200
        _ = bind(title) { f in
            let v = f.stringValue.trimmingCharacters(in: .whitespaces)
            if v.isEmpty { TaskStore.shared.delete(t.id); return }      // an empty note goes back to the pad
            var u = t; u.title = v; TaskStore.shared.update(u)
        }
        v.addArrangedSubview(title)

        let text = NSTextField(string: t.text)
        text.placeholderString = "notes…"
        text.isBordered = false; text.drawsBackground = false
        text.font = .systemFont(ofSize: 12)
        text.textColor = NSColor.black.withAlphaComponent(0.72)
        text.lineBreakMode = .byWordWrapping; text.cell?.wraps = true; text.cell?.isScrollable = false
        text.preferredMaxLayoutWidth = 200
        _ = bind(text) { f in var u = t; u.text = f.stringValue; TaskStore.shared.update(u) }
        v.addArrangedSubview(text)

        let bar = NSStackView(); bar.orientation = .horizontal; bar.spacing = 6; bar.alignment = .centerY
        func small(_ s: String, _ tip: String, _ fn: @escaping () -> Void) -> NSButton {
            let b = bind(NSButton(title: "", target: nil, action: nil)) { _ in fn() }
            b.isBordered = false
            b.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.black.withAlphaComponent(0.8)])
            b.toolTip = tip
            b.setContentHuggingPriority(.required, for: .horizontal)
            return b
        }
        let when = NSTextField(labelWithString: t.isDone ? "done \(TasksPage.rel(t.doneAt ?? t.updatedAt))" : TasksPage.rel(t.createdAt))
        when.font = .systemFont(ofSize: 10)
        when.textColor = NSColor.black.withAlphaComponent(0.55)
        bar.addArrangedSubview(when)
        let gap = NSView(); gap.translatesAutoresizingMaskIntoConstraints = false; gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(gap)
        if ci > 0 { bar.addArrangedSubview(small("←", "Move to \(columns[ci - 1])") { TaskStore.shared.move(t.id, to: columns[ci - 1]) }) }
        if ci < columns.count - 1 { bar.addArrangedSubview(small(ci == columns.count - 2 ? "✓" : "→", "Move to \(columns[ci + 1])") { TaskStore.shared.move(t.id, to: columns[ci + 1]) }) }
        bar.addArrangedSubview(small("◐", "Change colour") { var u = t; u.color = (t.color + 1) % TaskStore.colors.count; TaskStore.shared.update(u) })
        bar.addArrangedSubview(small("✕", "Delete") { TaskStore.shared.delete(t.id) })
        bar.translatesAutoresizingMaskIntoConstraints = false
        v.addArrangedSubview(bar)
        bar.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -24).isActive = true   // only once bar is inside v
        return box
    }

    static func rel(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }
}

/// A blank sticky on the pad: colour, paper shadow, a glue strip. Click to take one.
final class PadNoteButton: NSButton {
    let color: NSColor
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        title = ""
        isBordered = false
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 46).isActive = true
        heightAnchor.constraint(equalToConstant: 38).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        NSColor.black.withAlphaComponent(0.22).setFill(); r.offsetBy(dx: 1.5, dy: -2).fill()
        color.setFill(); r.fill()
        NSColor.white.withAlphaComponent(0.45).setFill(); NSRect(x: r.minX, y: r.maxY - 6, width: r.width, height: 6).fill()
        NSAttributedString(string: "+", attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.black.withAlphaComponent(isHighlighted ? 0.9 : 0.45)])
            .draw(at: NSPoint(x: r.midX - 5, y: r.midY - 11))
    }
}

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt32(h, radix: 16) ?? 0
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
