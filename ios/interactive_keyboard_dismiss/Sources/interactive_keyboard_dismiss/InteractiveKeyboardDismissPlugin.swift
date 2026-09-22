import Flutter
import UIKit

/// Gives Flutter the real iOS `UIScrollView.keyboardDismissMode = .interactive`
/// behaviour.
///
/// Why not move the keyboard view directly? From iOS 26 the keyboard is
/// rendered outside the app's view hierarchy: translating the in-process
/// `UIKeyboardItemContainerView` / `UIInputSetHostView` (or its container, or
/// the `UITextEffectsWindow`) changes nothing on screen, and a screenshot of
/// the screen no longer contains the keyboard either. Only UIKit itself can
/// drive the keyboard interactively.
///
/// So the plugin lets UIKit do it: it keeps an invisible `UIScrollView` with
/// `keyboardDismissMode = .interactive` inside the `FlutterView` and moves
/// that scroll view's `panGestureRecognizer` onto the `FlutterView` (the
/// pattern Apple showed for driving a scroll view from another view). The
/// recognizer never cancels or delays Flutter's touches, and it only begins
/// inside the screen regions registered by `InteractiveKeyboardDismiss`
/// widgets. When the finger crosses into the keyboard, UIKit moves the real
/// keyboard with it and, on release, springs it away or back with the system
/// animation. The plugin reports that decision to Dart, which keeps the
/// Flutter layout in step.
public class InteractiveKeyboardDismissPlugin: NSObject, FlutterPlugin {
  private weak var registrar: FlutterPluginRegistrar?
  private var scrollView: KeyboardPanScrollView?

  private var regions: [Int: CGRect] = [:]
  private var keyboardFrame: CGRect = .zero
  private var keyboardVisible = false

  private var panActive = false
  private var hideSeenDuringPan = false
  private var lastDecision: Bool?
  /// Duration of the system hide animation reported by keyboardWillHide.
  private var hideDuration: Double = 0
  private var pendingEnd: FlutterResult?
  private var decisionWork: DispatchWorkItem?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    center.addObserver(
      self, selector: #selector(keyboardWillShow(_:)),
      name: UIResponder.keyboardWillShowNotification, object: nil)
    center.addObserver(
      self, selector: #selector(keyboardWillHide(_:)),
      name: UIResponder.keyboardWillHideNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "interactive_keyboard_dismiss", binaryMessenger: registrar.messenger())
    let instance = InteractiveKeyboardDismissPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setRegion":
      let id = (args["id"] as? NSNumber)?.intValue ?? 0
      if let l = args["left"] as? NSNumber, let t = args["top"] as? NSNumber,
        let w = args["width"] as? NSNumber, let h = args["height"] as? NSNumber
      {
        regions[id] = CGRect(
          x: l.doubleValue, y: t.doubleValue, width: w.doubleValue, height: h.doubleValue)
      } else {
        regions.removeValue(forKey: id)
      }
      syncRecognizer()
      result(nil)
    case "begin":
      syncRecognizer()
      let ready = scrollView?.panGestureRecognizer.isEnabled == true && keyboardVisible
      result(["started": ready, "liveInsets": false, "systemDriven": true])
    case "update":
      // UIKit moves the keyboard itself from the same touch.
      result(nil)
    case "end":
      end(result: result)
    case "cancel":
      answerPendingEnd(dismissed: false)
      result(nil)
    case "diagnostics":
      result(diagnostics())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Recognizer management

  private var flutterView: UIView? {
    return registrar?.viewController?.view
  }

  /// Installs the tracking scroll view on first use and enables its pan
  /// recognizer only while at least one widget region is registered.
  private func syncRecognizer() {
    guard let view = flutterView else { return }
    if scrollView == nil || scrollView?.superview !== view {
      scrollView?.removeFromSuperview()
      let sv = KeyboardPanScrollView(frame: .zero)
      sv.keyboardDismissMode = .interactive
      sv.alwaysBounceVertical = true
      sv.showsVerticalScrollIndicator = false
      sv.showsHorizontalScrollIndicator = false
      sv.scrollsToTop = false
      sv.isUserInteractionEnabled = false
      sv.isAccessibilityElement = false
      sv.accessibilityElementsHidden = true
      sv.alpha = 0
      sv.frame = view.bounds
      sv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      sv.contentSize = CGSize(width: 1, height: 1)
      view.insertSubview(sv, at: 0)
      let pan = sv.panGestureRecognizer
      pan.cancelsTouchesInView = false
      pan.delaysTouchesBegan = false
      pan.delaysTouchesEnded = false
      view.addGestureRecognizer(pan)
      pan.addTarget(self, action: #selector(handlePan(_:)))
      sv.hostView = view
      scrollView = sv
    }
    scrollView?.regions = Array(regions.values)
    scrollView?.panGestureRecognizer.isEnabled = !regions.isEmpty
  }

  @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
    switch pan.state {
    case .began:
      panActive = true
      hideSeenDuringPan = false
      lastDecision = nil
      decisionWork?.cancel()
    case .ended, .cancelled, .failed:
      guard panActive else { return }
      panActive = false
      scrollView?.setContentOffset(.zero, animated: false)
      if hideSeenDuringPan {
        decide(dismissed: true)
      } else {
        // UIKit may post keyboardWillHide slightly after the pan ends.
        let work = DispatchWorkItem { [weak self] in
          guard let self = self else { return }
          self.decide(dismissed: self.hideSeenDuringPan)
        }
        decisionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
      }
    default:
      break
    }
  }

  private func decide(dismissed: Bool) {
    decisionWork = nil
    lastDecision = dismissed
    answerPendingEnd(dismissed: dismissed)
  }

  private func end(result: @escaping FlutterResult) {
    answerPendingEnd(dismissed: false)
    if let decision = lastDecision, !panActive, decisionWork == nil {
      lastDecision = nil
      result(["dismissed": decision, "duration": decision ? hideDuration : 0])
      return
    }
    if !panActive && decisionWork == nil {
      // UIKit never tracked this drag (no pan on the FlutterView).
      result(["dismissed": false, "duration": 0])
      return
    }
    pendingEnd = result
  }

  private func answerPendingEnd(dismissed: Bool) {
    guard let pending = pendingEnd else { return }
    pendingEnd = nil
    lastDecision = nil
    pending(["dismissed": dismissed, "duration": dismissed ? hideDuration : 0])
  }

  // MARK: - Keyboard notifications

  @objc private func keyboardWillChangeFrame(_ notification: Notification) {
    if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
      keyboardFrame = frame
    }
  }

  @objc private func keyboardWillShow(_ notification: Notification) {
    keyboardVisible = true
  }

  @objc private func keyboardWillHide(_ notification: Notification) {
    keyboardVisible = false
    hideDuration =
      (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
      .doubleValue ?? 0
    if panActive || decisionWork != nil {
      hideSeenDuringPan = true
      if let work = decisionWork {
        work.cancel()
        decide(dismissed: true)
      }
    }
  }

  // MARK: - Diagnostics

  private func diagnostics() -> [String: Any] {
    var windows: [String] = []
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      windows.append(contentsOf: windowScene.windows.map { NSStringFromClass(type(of: $0)) })
    }
    return [
      "platform": "ios",
      "systemVersion": UIDevice.current.systemVersion,
      "technique": "UIScrollView.keyboardDismissMode.interactive via relocated pan recognizer",
      "flutterViewFound": flutterView != nil,
      "recognizerInstalled": scrollView != nil,
      "recognizerEnabled": scrollView?.panGestureRecognizer.isEnabled ?? false,
      "regions": regions.count,
      "keyboardVisible": keyboardVisible,
      "keyboardFrame": NSCoder.string(for: keyboardFrame),
      "windows": windows,
    ]
  }
}

/// The invisible scroll view whose pan recognizer lives on the FlutterView.
/// It only lets the pan begin inside regions registered from Dart.
final class KeyboardPanScrollView: UIScrollView {
  weak var hostView: UIView?
  var regions: [CGRect] = []

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === panGestureRecognizer {
      guard let host = hostView else { return false }
      let point = gestureRecognizer.location(in: host)
      guard regions.contains(where: { $0.contains(point) }) else { return false }
      let velocity = panGestureRecognizer.velocity(in: host)
      // Only vertical drags; horizontal ones belong to Flutter (PageView etc.).
      if abs(velocity.x) > abs(velocity.y) { return false }
    }
    return super.gestureRecognizerShouldBegin(gestureRecognizer)
  }
}
