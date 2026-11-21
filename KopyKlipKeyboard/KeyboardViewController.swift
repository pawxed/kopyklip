import UIKit

final class KeyboardViewController: UIInputViewController, UITableViewDataSource, UITableViewDelegate {
    private var clips: [Clip] = []
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

    override func viewDidLoad() {
        super.viewDidLoad()
        StoreChange.start()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: StoreChange.notification, object: nil)
        view.backgroundColor = .systemBackground
        buildUI()
        clipsTable.dataSource = self
        clipsTable.delegate = self
        KopyStore.capturePasteboard()
        reload()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refreshIfChanged()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        KopyStore.capturePasteboard()
        reload()
    }

    private func refreshIfChanged() {
        KopyStore.capturePasteboard()
        guard KopyStore.clips() != clips else { return }
        reload()
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

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 32),
            clipsTable.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            clipsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clipsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clipsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let height = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        height.priority = UILayoutPriority(rawValue: 999)
        height.isActive = true
    }

    private func reload() {
        clips = KopyStore.clips()
        clipsTable.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let label = UILabel()
        label.text = "No clips yet.\nCopy text anywhere to build history."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        clipsTable.backgroundView = clips.isEmpty ? label : nil
    }

    @objc private func storeChanged() {
        reload()
    }

    @objc private func nextKeyboard() {
        advanceToNextInputMode()
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func clearAll() {
        KopyStore.clearClips()
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "row") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "row")
        let clip = clips[indexPath.row]
        cell.textLabel?.text = clip.text
        cell.textLabel?.numberOfLines = 2
        cell.detailTextLabel?.text = clip.date.formatted(date: .omitted, time: .shortened)
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
        textDocumentProxy.insertText(clips[indexPath.row].text)
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func deleteClip(at indexPath: IndexPath) {
        guard clips.indices.contains(indexPath.row) else { return }
        let id = clips[indexPath.row].id
        KopyStore.removeClip(id: id)
        clips.remove(at: indexPath.row)
        clipsTable.deleteRows(at: [indexPath], with: .automatic)
        updateEmptyState()
    }
}
