//
//  ViewController.swift
//  nestScroll
//
//  Created by yang on 26/01/2018.
//  Copyright © 2018 ocean. All rights reserved.
//

import UIKit
import WebKit

class DynamicItem: NSObject, UIDynamicItem {
    var center: CGPoint = .zero

    var bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var transform: CGAffineTransform = .identity
}

extension UIScrollView {
    var maxContentOffsetY: CGFloat {
        return max(0, contentSize.height - frame.height)
    }

    var isReachTop: Bool {
        return contentOffset.y <= 0
    }

    var isReachBottom: Bool {
        return contentOffset.y - maxContentOffsetY >= 0
    }

    var bounceDistanceThreshold: CGFloat {
        return frame.height * 0.66
    }
}

class ViewController: UIViewController {

    @IBOutlet weak var superScrollview: UIScrollView!
    @IBOutlet weak var webView: WKWebView!

    let panRecognizer = UIPanGestureRecognizer()
    private lazy var dynamicAnimator: UIDynamicAnimator = {
        let animator = UIDynamicAnimator(referenceView: view)
        animator.delegate = self
        return animator
    }()
    var dynamicItem: DynamicItem?
    private weak var inertialBehavior: UIDynamicItemBehavior?
    private weak var bounceBehavior: UIAttachmentBehavior?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        webView.layer.borderWidth = 1
        webView.scrollView.isScrollEnabled = false
        superScrollview.isScrollEnabled = false

        panRecognizer.addTarget(self, action: #selector(handlePanGestureRecognizer))
        view.addGestureRecognizer(panRecognizer)

        do {
            let templateURL = Bundle.main.url(forResource: "index", withExtension: "html")!
            let templateContent = try String(contentsOf: templateURL, encoding: String.Encoding.utf8)

            let markdownURL = Bundle.main.url(forResource: "markdown", withExtension: "html")!
            let markdownHTML = try String(contentsOf: markdownURL, encoding: String.Encoding.utf8)

            let htmlStr = templateContent.replacingOccurrences(of: "$PLACEHOLDER", with: markdownHTML)

            webView.loadHTMLString(htmlStr, baseURL: templateURL)
        } catch let error {
            print(error)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        dynamicAnimator.removeAllBehaviors()
    }

    func transitionDeltaY(_ deltaY: CGFloat) {
//        var deltaY = delta
//        if delta > 0 && superScrollview.isReachTop {
//            print("superScrollview.contentOffset.y", superScrollview.contentOffset.y)
//            print("superScrollview.bounceDistanceThreshold", superScrollview.bounceDistanceThreshold)
//            print(1 - min(-superScrollview.contentOffset.y, superScrollview.bounceDistanceThreshold) / superScrollview.bounceDistanceThreshold)
//            deltaY = (1 - min(-superScrollview.contentOffset.y, superScrollview.bounceDistanceThreshold) / superScrollview.bounceDistanceThreshold) * delta
//        }

        // 主scrollView偏移量
        var superDeltaY: CGFloat = 0

        // 子scrollView偏移量
        var subDeltaY: CGFloat = 0

        if deltaY < 0 {
            // 向上滑动
            let superOffsetY = superScrollview.contentOffset.y
            let superOffset = webView.frame.minY - superOffsetY
            let subOffsetY = webView.scrollView.contentOffset.y
            let bottomOffset = webView.scrollView.contentSize.height - subOffsetY - webView.scrollView.frame.height

            if superOffset + deltaY >= 0 {
                // 只移动super
                superDeltaY = deltaY
            } else {
                superDeltaY = -superOffset
            }
            subDeltaY = deltaY - superDeltaY
        } else {
            // 向下滑动
            let offset = webView.scrollView.contentOffset.y
            if offset - deltaY > 0 {
                // 只移动sub
                subDeltaY = deltaY
            } else {
                subDeltaY = offset
            }
            superDeltaY = deltaY - subDeltaY

            if superScrollview.contentOffset.y - superDeltaY < 0 {
                let bounceDelta = max(0, (superScrollview.bounceDistanceThreshold - fabs(superScrollview.contentOffset.y)) / superScrollview.bounceDistanceThreshold)
                superDeltaY = deltaY * bounceDelta
                subDeltaY = 0
            }
        }

        do {
            var contentOffset = superScrollview.contentOffset
            contentOffset.y -= superDeltaY
            superScrollview.setContentOffset(contentOffset, animated: false)
        }

        do {
            var contentOffset = webView.scrollView.contentOffset
            contentOffset.y -= subDeltaY
            webView.scrollView.setContentOffset(contentOffset, animated: false)
        }

        if superScrollview.isReachTop {
            performBounceIfNeeded(forScrollView: superScrollview)
        }
    }

    func performBounceIfNeeded(forScrollView scrollView: UIScrollView) {
        if self.inertialBehavior != nil {
            performBounce(forScrollView: scrollView)
        }
    }

    func performBounce(forScrollView scrollView: UIScrollView) {
        guard self.bounceBehavior == nil else {
            return
        }

        if let inertialBehavior = self.inertialBehavior {
            dynamicAnimator.removeBehavior(inertialBehavior)
        }

        let item = DynamicItem()
        item.center = scrollView.contentOffset
        var attachedToAnchorY: CGFloat = 0

        let bounceBehavior = UIAttachmentBehavior(item: item, attachedToAnchor: CGPoint(x: 0, y: attachedToAnchorY))
        bounceBehavior.length = 0
        bounceBehavior.damping = 1
        bounceBehavior.frequency = 2
        bounceBehavior.action = { [weak self] in
            scrollView.contentOffset = CGPoint(x: 0, y: item.center.y)
            if fabs(scrollView.contentOffset.y - attachedToAnchorY) <= CGFloat.leastNormalMagnitude,
                let bounceBehavior = self?.bounceBehavior,
                let dynamicAnimator = self?.dynamicAnimator {
                dynamicAnimator.removeBehavior(bounceBehavior)
            }
        }
        self.bounceBehavior = bounceBehavior
        dynamicAnimator.addBehavior(bounceBehavior)
    }
}

@objc
extension ViewController {
    func handlePanGestureRecognizer(pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            dynamicAnimator.removeAllBehaviors()
            break
        case .cancelled:
            break
        case .changed:
            // 纵向移动
            let deltaY = pan.translation(in: view).y
            // 滑动
            transitionDeltaY(deltaY)
            // 重置移动位置
            pan.setTranslation(.zero, in: view)
            break
        case .ended:
            if superScrollview.isReachTop {
                performBounce(forScrollView: superScrollview)
                break
            }
            let item = DynamicItem()
            let interialBehavior = UIDynamicItemBehavior(items: [item])
            interialBehavior.addLinearVelocity(CGPoint(x: 0, y: pan.velocity(in: view).y), for: item)
            interialBehavior.resistance = 2
            var lastCenterY: CGFloat = 0
            interialBehavior.action = { [weak self] in
                self?.transitionDeltaY(item.center.y - lastCenterY)
                lastCenterY = item.center.y
            }
            dynamicAnimator.addBehavior(interialBehavior)
            inertialBehavior = interialBehavior
            dynamicItem = item
            break
        case .failed:
            break
        case .possible:
            break
        }
    }
}

extension ViewController: UIDynamicAnimatorDelegate {
    func dynamicAnimatorWillResume(_ animator: UIDynamicAnimator) {
        webView.isUserInteractionEnabled = false
    }
    func dynamicAnimatorDidPause(_ animator: UIDynamicAnimator) {
        webView.isUserInteractionEnabled = true
    }
}
