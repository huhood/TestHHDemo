import UIKit

// MARK: - 首页：三个完全独立的实验入口
final class LabHomeViewController: UITableViewController {
    private let titles = [
        "实验 A｜首次进入页面卡顿",
        "实验 B｜快速滚动掉帧",
        "实验 C｜图片出现时卡顿"
    ]
    private let details = [
        "故意在主线程执行约 450ms CPU 任务",
        "故意在 cellForRowAt 中同步计算",
        "故意在主线程加载并解码大图片"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Instruments 实战实验室"
        tableView.rowHeight = 88
        tableView.tableFooterView = UIView()
        tableView.backgroundColor = .systemGroupedBackground

        let hint = UILabel()
        hint.text = "每个页面均有故障版与优化版。建议用真机、Release/Profile 配置录制。所有卡顿均为教学目的故意制造。"
        hint.font = .preferredFont(forTextStyle: .subheadline)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        hint.frame = CGRect(x: 0, y: 0, width: 330, height: 96)
        tableView.tableHeaderView = hint
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        titles.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "HomeRow"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        cell.textLabel?.text = titles[indexPath.row]
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = details[indexPath.row]
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let destination: UIViewController
        switch indexPath.row {
        case 0: destination = FirstLoadViewController()
        case 1: destination = ScrollHitchViewController()
        default: destination = ImageHitchViewController()
        }
        navigationController?.pushViewController(destination, animated: true)
    }
}

// MARK: - 实验 A：首次页面加载的同步主线程工作
final class FirstLoadViewController: UIViewController {
    private let modeControl = UISegmentedControl(items: ["故障版", "优化版"])
    private let statusLabel = UILabel()
    private var hasAutoRun = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "A｜首次加载卡顿"
        view.backgroundColor = .systemBackground

        let explanation = UILabel()
        explanation.numberOfLines = 0
        explanation.text = "故障版：页面出现后，在主线程执行约 450ms 的 CPU 计算，界面会短暂无响应。\n\n优化版：相同计算转到后台线程，主线程仍能正常响应。"
        explanation.font = .preferredFont(forTextStyle: .body)

        modeControl.selectedSegmentIndex = 0
        let runButton = UIButton(type: .system)
        runButton.configuration = .filled()
        runButton.configuration?.title = "重新运行当前模式"
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = "观察：初次进入卡顿、主线程 CPU 峰值"
        titleLabel.numberOfLines = 0
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "首次进入会自动运行故障版。"

        let stack = UIStackView(arrangedSubviews: [titleLabel, explanation, modeControl, runButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAutoRun else { return }
        hasAutoRun = true
        // 略晚于进入动画才执行，让用户和 Instruments 能清楚看到阻塞瞬间。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.runExperiment()
        }
    }

    @objc private func runTapped() { runExperiment() }

    private func runExperiment() {
        statusLabel.text = "正在计算……（故障版中 UI 会短暂停住）"
        let isBad = modeControl.selectedSegmentIndex == 0
        // 先把“正在计算”的文字送到屏幕，再执行测试操作。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if isBad {
                LabSignpost.firstLoad {
                    LabCPU.busyWork(milliseconds: 450)
                }
                self.statusLabel.text = "故障版完成：约 450ms CPU 工作占用了主线程。"
            } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    LabSignpost.firstLoad {
                        LabCPU.busyWork(milliseconds: 450)
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.statusLabel.text = "优化版完成：CPU 工作在后台执行，主线程未被这段代码直接阻塞。"
                    }
                }
            }
        }
    }
}

// MARK: - 实验 B：每生成一个 Cell 就做昂贵的同步 CPU 计算
final class ScrollHitchViewController: UIViewController, UITableViewDataSource {
    private let tableView = UITableView()
    private let modeControl = UISegmentedControl(items: ["故障版", "优化版"])
    private let itemCount = 2000

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "B｜快速滚动卡顿"
        view.backgroundColor = .systemBackground

        let explanation = UILabel()
        explanation.font = .preferredFont(forTextStyle: .subheadline)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0
        explanation.text = "故障版在 cellForRowAt 每创建/复用一行时同步计算约 12ms；优化版去掉这段工作。切换模式后快速上下滑动。"

        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        tableView.dataSource = self
        tableView.rowHeight = 70
        tableView.estimatedRowHeight = 70
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.tableFooterView = UIView()

        let stack = UIStackView(arrangedSubviews: [explanation, modeControl])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func modeChanged() {
        tableView.reloadData()
        tableView.setContentOffset(.zero, animated: false)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        itemCount
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "ScrollRow"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)

        if modeControl.selectedSegmentIndex == 0 {
            // 【故意错误】同步 CPU 计算阻塞主线程。请在 Time Profiler 中找这个方法。
            LabSignpost.scrollCell {
                LabCPU.busyWork(milliseconds: 12)
            }
        }

        cell.textLabel?.text = "商品编号 #\(indexPath.row + 1)"
        cell.detailTextLabel?.text = "同一批数据，仅比较 Cell 配置阶段的计算成本"
        cell.accessoryType = .none
        return cell
    }
}
