import UIKit

final class KeyboardViewController: UIInputViewController, UITableViewDataSource, UITableViewDelegate {
    private var clips: [Clip] = []
    private var remoteClips: [Clip] = []
    private var tombstones: [UUID: Date] = [:]
    private var keyboardHeight: CGFloat {
        let screen = UIScreen.main.bounds
        return screen.width > screen.height ? 200 : min(320, screen.height * 0.42)
    }

    private var refreshTimer: Timer?

    private let bar = UIStackView()
    private let globeButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)

    private let clipsTable: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.rowHeight = 50
        return table
    }()

    private let toast: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        StoreChange.start()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: StoreChange.notification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pipCaptured), name: StoreChange.pipNotification, object: nil)
        view.backgroundColor = .systemBackground
        buildUI()
        clipsTable.dataSource = self
        clipsTable.delegate = self
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.sync()
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sync()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sync()
    }

    private func sync() {
        KopyStore.capturePasteboard()
        ClipBridge.fetch { [weak self] remote in
            DispatchQueue.main.async {
                self?.remoteClips = remote
                self?.refresh()
            }
        }
        refresh()
    }

    private func refresh() {
        tombstones = tombstones.filter { Date().timeIntervalSince($0.value) < 10 }
        var seen = Set<String>()
        var merged: [Clip] = []
        for clip in (KopyStore.clips() + remoteClips).sorted(by: { $0.date > $1.date }) {
            guard tombstones[clip.id] == nil else { continue }
            let key = clip.isImage ? clip.id.uuidString : clip.text
            guard seen.insert(key).inserted else { continue }
            merged.append(clip)
        }
        let latest = Array(merged.prefix(KopyStore.maxClips))
        guard latest != clips else { return }
        clips = latest
        clipsTable.reloadData()
        updateEmptyState()
    }

    private func buildUI() {
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.addTarget(self, action: #selector(nextKeyboard), for: .touchUpInside)
        backButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        backButton.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)
        clearButton.setTitle("Clear All", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 15)
        clearButton.setTitleColor(.systemRed, for: .normal)
        clearButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        clearButton.addTarget(self, action: #selector(clearAll), for: .touchUpInside)
        returnButton.setTitle("Return", for: .normal)
        returnButton.titleLabel?.font = .systemFont(ofSize: 15)
        returnButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        returnButton.addTarget(self, action: #selector(insertReturn), for: .touchUpInside)

        bar.axis = .horizontal
        bar.spacing = 12
        bar.alignment = .fill
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addArrangedSubview(globeButton)
        bar.addArrangedSubview(backButton)
        bar.addArrangedSubview(UIView())
        bar.addArrangedSubview(clearButton)
        bar.addArrangedSubview(returnButton)

        clipsTable.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        view.addSubview(clipsTable)
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 32),
            clipsTable.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            clipsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clipsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clipsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            toast.heightAnchor.constraint(equalToConstant: 30),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])

        let height = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        height.priority = UILayoutPriority(rawValue: 999)
        height.isActive = true
    }

    private func updateEmptyState() {
        let label = UILabel()
        label.text = "No clips yet.\nCopy text or an image, then reopen this keyboard."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        clipsTable.backgroundView = clips.isEmpty ? label : nil
    }

    @objc private func storeChanged() {
        refresh()
    }

    @objc private func pipCaptured() {
        refresh()
    }

    @objc private func nextKeyboard() {
        advanceToNextInputMode()
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func clearAll() {
        for clip in clips { tombstones[clip.id] = Date() }
        KopyStore.clearClips()
        ClipBridge.clear()
        remoteClips = []
        clips = []
        clipsTable.reloadData()
        updateEmptyState()
    }

    @objc private func insertReturn() {
        textDocumentProxy.insertText("\n")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        clips.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row") as? ClipCell ?? ClipCell(style: .default, reuseIdentifier: "row")
        cell.configure(with: clips[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let action = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deleteClip(at: indexPath)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        deleteClip(at: indexPath)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let clip = clips[indexPath.row]
        if let image = KopyStore.image(for: clip) {
            UIPasteboard.general.image = image
            KopyStore.markHandled()
            showToast("Image copied. Paste it to insert.")
            return
        }
        textDocumentProxy.insertText(clip.text)
    }

    private func showToast(_ text: String) {
        toast.text = "  \(text)  "
        toast.alpha = 1
        UIView.animate(withDuration: 0.3, delay: 1.5, options: .curveEaseIn) {
            self.toast.alpha = 0
        }
    }

    private func deleteClip(at indexPath: IndexPath) {
        guard clips.indices.contains(indexPath.row) else { return }
        let clip = clips[indexPath.row]
        tombstones[clip.id] = Date()
        remoteClips.removeAll { $0.id == clip.id }
        KopyStore.removeClip(id: clip.id)
        ClipBridge.delete(clip.id)
        clips.remove(at: indexPath.row)
        clipsTable.deleteRows(at: [indexPath], with: .automatic)
        updateEmptyState()
    }
}

final class ClipCell: UITableViewCell {
    private let thumb = UIImageView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 6
        thumb.tintColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 15)
        contentView.addSubview(thumb)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumb.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 40),
            thumb.heightAnchor.constraint(equalToConstant: 40),
            label.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with clip: Clip) {
        if let image = KopyStore.image(for: clip) {
            thumb.image = image
            thumb.contentMode = .scaleAspectFill
            label.text = clip.date.formatted(date: .omitted, time: .shortened) + "  Image"
        } else {
            thumb.image = UIImage(systemName: "doc.text")
            thumb.contentMode = .scaleAspectFit
            label.text = clip.text
        }
    }
}
