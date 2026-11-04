import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - 离线生成一张测试用的大 JPEG，避免联网、第三方图片地址和不可控网络因素。
enum LargeImageFixture {
    static let side = 2600

    static func prepare(completion: @escaping (URL?) -> Void) {
        let fileURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("instruments-source-2600.jpg")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            DispatchQueue.main.async { completion(fileURL) }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            guard let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // 绘制复杂的彩色网格，让 JPEG 解码的 CPU/内存成本可观察。
            let blockSize = 26
            for y in stride(from: 0, to: side, by: blockSize) {
                for x in stride(from: 0, to: side, by: blockSize) {
                    let red = CGFloat((x * 17 + y * 5) % 255) / 255.0
                    let green = CGFloat((x * 3 + y * 13) % 255) / 255.0
                    let blue = CGFloat((x * 11 + y * 7) % 255) / 255.0
                    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: blockSize, height: blockSize))
                }
            }

            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(
                    fileURL as CFURL,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                  ) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.87] as CFDictionary
            )
            let succeeded = CGImageDestinationFinalize(destination)
            DispatchQueue.main.async { completion(succeeded ? fileURL : nil) }
        }
    }
}

// MARK: - 两种图片处理方式（用于实验，不应直接用故障版编写生产代码）
enum LabImageProcessing {
    // 【故障版】在主线程解出接近原图尺寸的像素，再缩小绘制进 72pt 图片。
    // 函数必须在主线程调用，故意制造卡顿。应用中不要这样写。
    static func oversizedDecodeOnMain(url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let largeImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2600,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        ) else { return nil }

        // 在主线程同步绘制，且源 CGImage 已经非常大。
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 72, height: 72))
        return renderer.image { _ in
            UIImage(cgImage: largeImage).draw(in: CGRect(x: 0, y: 0, width: 72, height: 72))
        }
    }

    // 【优化版】直接在后台按需要的像素尺寸创建缩略图。
    static func downsampleInBackground(url: URL, maxPixelSize: Int, scale: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: thumbnail, scale: scale, orientation: .up)
    }
}

// MARK: - 图片列表里的 Cell
final class ImageRowCell: UITableViewCell {
    let thumbnailView = UIImageView()
    private let rowLabel = UILabel()
    var representedID: Int = -1

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        thumbnailView.backgroundColor = .tertiarySystemFill
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        rowLabel.translatesAutoresizingMaskIntoConstraints = false
        rowLabel.font = .preferredFont(forTextStyle: .body)
        contentView.addSubview(thumbnailView)
        contentView.addSubview(rowLabel)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 72),
            thumbnailView.heightAnchor.constraint(equalToConstant: 72),
            rowLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),
            rowLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rowLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("仅支持纯代码初始化")
    }

    func configure(index: Int) {
        representedID = index
        rowLabel.text = "图片 #\(index + 1)"
        thumbnailView.image = UIImage(systemName: "photo")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedID = -1
        thumbnailView.image = nil
    }
}

// MARK: - 实验 C：图片首次显示时，主线程同步解码引起卡顿
final class ImageHitchViewController: UIViewController, UITableViewDataSource {
    private let tableView = UITableView()
    private let modeControl = UISegmentedControl(items: ["故障版", "优化版"])
    private let statusLabel = UILabel()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let processingQueue = DispatchQueue(label: "lab.downsampling.serial", qos: .userInitiated)
    private var imageURL: URL?
    private var generation = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "C｜图片出现时卡顿"
        view.backgroundColor = .systemBackground

        let explanation = UILabel()
        explanation.numberOfLines = 0
        explanation.font = .preferredFont(forTextStyle: .subheadline)
        explanation.textColor = .secondaryLabel
        explanation.text = "故障版：图片出现时在主线程解码 2600px 大图。优化版：后台降采样为约 72pt × Scale，并缓存缩略图。"

        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "正在后台准备离线 JPEG……请准备完成后再录制。"

        let stack = UIStackView(arrangedSubviews: [explanation, modeControl, statusLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.rowHeight = 92
        tableView.estimatedRowHeight = 92
        tableView.isHidden = true
        tableView.register(ImageRowCell.self, forCellReuseIdentifier: "ImageRowCell")
        view.addSubview(stack)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 大图片素材只在后台生成一次，避免污染后续的“图片解码”实验。
        LargeImageFixture.prepare { [weak self] url in
            guard let self else { return }
            self.imageURL = url
            self.tableView.isHidden = url == nil
            self.statusLabel.text = url == nil
                ? "生成图片失败，请返回重试。"
                : "素材准备完成。请开启 Instruments 并滚动；切换模式可重新实验。"
            self.tableView.reloadData()
        }
    }

    @objc private func modeChanged() {
        // 使上一个模式尚未完成的异步回调不能更新新模式 Cell。
        generation += 1
        thumbnailCache.removeAllObjects()
        tableView.reloadData()
        tableView.setContentOffset(.zero, animated: false)
        statusLabel.text = modeControl.selectedSegmentIndex == 0
            ? "故障版：滚动时大图同步解码（预期明显掉帧）。"
            : "优化版：异步降采样 + 小图缓存（预期更流畅）。"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        120
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ImageRowCell", for: indexPath
        ) as! ImageRowCell
        let index = indexPath.row
        cell.configure(index: index)
        guard let url = imageURL else { return cell }
        let currentGeneration = generation

        if modeControl.selectedSegmentIndex == 0 {
            // 故意延迟一小段时间：便于将“图片出现”的时刻与 hitch 对齐。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self, weak cell] in
                guard let self, let cell,
                      self.generation == currentGeneration,
                      cell.representedID == index else { return }
                var image: UIImage?
                LabSignpost.imageDecode {
                    image = LabImageProcessing.oversizedDecodeOnMain(url: url)
                }
                // 再次确认这个 Cell 没有被复用成别的数据。
                guard self.generation == currentGeneration,
                      cell.representedID == index else { return }
                cell.thumbnailView.image = image
            }
        } else {
            // 优化版：如果缩略图已经在内存中，直接读取。
            let key = "thumbnail-\(index)" as NSString
            if let cached = thumbnailCache.object(forKey: key) {
                cell.thumbnailView.image = cached
            } else {
                // 使用串行后台队列控制图片处理并发，避免同时解码过多大图。
                let screenScale = UIScreen.main.scale
                processingQueue.async { [weak self, weak cell] in
                    guard let self else { return }
                    var image: UIImage?
                    LabSignpost.imageDownsample {
                        image = LabImageProcessing.downsampleInBackground(
                            url: url,
                            maxPixelSize: Int(72 * screenScale),
                            scale: screenScale
                        )
                    }
                    guard let image else { return }
                    self.thumbnailCache.setObject(image, forKey: key)
                    DispatchQueue.main.async { [weak self, weak cell] in
                        guard let self, let cell,
                              self.generation == currentGeneration,
                              cell.representedID == index else { return }
                        cell.thumbnailView.image = image
                    }
                }
            }
        }
        return cell
    }
}
