import SwiftUI
import AVFoundation

struct ZoomableScreen: UIViewRepresentable {
    let image: UIImage
    let resetID: UUID
    let controlling: Bool
    let send: (PhoneControl.Command) -> Void

    func makeUIView(context: Context) -> ScreenScrollView { ScreenScrollView() }

    func updateUIView(_ view: ScreenScrollView, context: Context) {
        view.imageView.image = image
        view.send = send
        view.controlling = controlling
        if view.resetID != resetID {
            view.resetID = resetID
            view.setZoomScale(1, animated: false)
        }
    }
}

final class ScreenScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var resetID: UUID?
    var send: ((PhoneControl.Command) -> Void)?
    var controlling = false {
        didSet {
            guard oldValue != controlling else { return }
            if !controlling { cancelDrag() }
            for gesture in controls { gesture.isEnabled = controlling }
            panGestureRecognizer.isEnabled = !controlling
            pinchGestureRecognizer?.isEnabled = !controlling
            updateAccessibility()
        }
    }

    private var lastSize = CGSize.zero
    private var dragPoint: PhoneControl.Point?
    private lazy var controls: [UIGestureRecognizer] = {
        let click = UITapGestureRecognizer(target: self, action: #selector(tapped))
        let doubleClick = UITapGestureRecognizer(target: self, action: #selector(tapped))
        doubleClick.numberOfTapsRequired = 2
        click.require(toFail: doubleClick)
        let rightClick = UILongPressGestureRecognizer(target: self, action: #selector(held))
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))
        drag.maximumNumberOfTouches = 1
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        return [click, doubleClick, rightClick, drag, scroll]
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        addSubview(imageView)
        for gesture in controls {
            gesture.isEnabled = false
            addGestureRecognizer(gesture)
        }
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        cancelDrag()
        setZoomScale(1, animated: false)
        imageView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }

    private func updateAccessibility() {
        imageView.accessibilityLabel = controlling
            ? "Live Mac screen. Tap to click, hold to right-click, drag, or scroll with two fingers."
            : "Live Mac screen. Pinch to zoom or drag to pan."
    }

    private func normalized(_ position: CGPoint, clamped: Bool = false) -> PhoneControl.Point? {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return nil }
        let rect = AVMakeRect(aspectRatio: image.size, insideRect: imageView.bounds)
        guard !rect.isEmpty, clamped || rect.contains(position) else { return nil }
        return PhoneControl.Point(x: min(1, max(0, (position.x - rect.minX) / rect.width)),
                                  y: min(1, max(0, (position.y - rect.minY) / rect.height)))
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let point = normalized(gesture.location(in: imageView)) else { return }
        send?(gesture.numberOfTapsRequired == 2 ? .doubleClick(point) : .click(point))
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let point = normalized(gesture.location(in: imageView)) else { return }
        send?(.rightClick(point))
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let position = gesture.location(in: imageView)
        switch gesture.state {
        case .began:
            let delta = gesture.translation(in: imageView)
            guard let origin = normalized(CGPoint(x: position.x - delta.x, y: position.y - delta.y)) else { return }
            dragPoint = origin
            send?(.dragStart(origin))
        case .changed:
            guard dragPoint != nil, let point = normalized(position, clamped: true) else { return }
            dragPoint = point
            send?(.dragMove(point))
        case .ended:
            if dragPoint != nil, let point = normalized(position, clamped: true) { dragPoint = point }
            cancelDrag()
        case .cancelled, .failed: cancelDrag()
        default: break
        }
    }

    @objc private func scrolled(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        guard let point = normalized(gesture.location(in: imageView), clamped: true) else { return }
        send?(.scroll(point, horizontal: Int32(max(-240, min(240, delta.x * 2))),
                      vertical: Int32(max(-240, min(240, delta.y * 2)))))
    }

    private func cancelDrag() {
        if let dragPoint { send?(.dragEnd(dragPoint)) }
        dragPoint = nil
    }
}
