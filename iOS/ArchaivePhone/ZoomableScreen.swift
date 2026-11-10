import SwiftUI

struct ZoomableScreen: UIViewRepresentable {
    let image: UIImage
    let resetID: UUID

    func makeUIView(context: Context) -> ScreenScrollView { ScreenScrollView() }
    func updateUIView(_ view: ScreenScrollView, context: Context) {
        view.imageView.image = image
        if view.resetID != resetID {
            view.resetID = resetID
            view.setZoomScale(1, animated: false)
        }
    }
}

final class ScreenScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var resetID: UUID?
    private var lastSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Live Mac screen. Pinch to zoom; drag to pan."
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        setZoomScale(1, animated: false)
        imageView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }
}
