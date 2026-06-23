import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  // MARK: - App Switcher privacy
  //
  // The app uses the UIScene lifecycle, so AppDelegate.applicationWillResignActive
  // is never called — the privacy overlay must be driven from the scene callbacks
  // here. Cover the UI before iOS snapshots it for the App Switcher (and any time
  // the scene goes inactive), then reveal it once the scene is active again so
  // balances and transactions stay out of the background preview.
  private var _privacyView: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    showPrivacyScreen(in: scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    hidePrivacyScreen()
    super.sceneDidBecomeActive(scene)
  }

  private func sceneWindow(_ scene: UIScene) -> UIWindow? {
    if let w = window { return w }
    guard let ws = scene as? UIWindowScene else { return nil }
    if let key = ws.windows.first(where: { $0.isKeyWindow }) { return key }
    return ws.windows.first
  }

  private func showPrivacyScreen(in scene: UIScene) {
    guard _privacyView == nil, let window = sceneWindow(scene) else { return }

    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Opaque so nothing underneath shows through in the snapshot.
    cover.backgroundColor = UIColor.systemBackground

    // Frosted blur hides the live UI; a centered branded card sits on top.
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    blur.frame = cover.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.addSubview(blur)

    // Animated security lock (no app icon) — a pulsing-ring "securing" motion.
    let lock = securityLockView()

    // Title + a short privacy explanation. System label colors adapt to
    // light / dark automatically.
    let title = UILabel()
    title.text = "Locked"
    title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    title.textColor = UIColor.label
    title.textAlignment = .center

    let info = UILabel()
    info.text =
      "Your balances and transactions stay hidden while Trackora is in the background."
    info.font = UIFont.systemFont(ofSize: 13, weight: .regular)
    info.textColor = UIColor.secondaryLabel
    info.textAlignment = .center
    info.numberOfLines = 0
    info.translatesAutoresizingMaskIntoConstraints = false

    let stack = UIStackView(arrangedSubviews: [lock, title, info])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 6
    stack.setCustomSpacing(18, after: lock)
    stack.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(stack)

    NSLayoutConstraint.activate([
      lock.widthAnchor.constraint(equalToConstant: 120),
      lock.heightAnchor.constraint(equalToConstant: 120),
      info.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
      stack.leadingAnchor.constraint(
        greaterThanOrEqualTo: cover.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: cover.trailingAnchor, constant: -32),
      stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      // Sit slightly above the true center so it reads like a lock screen.
      stack.centerYAnchor.constraint(
        equalTo: cover.centerYAnchor, constant: -16),
    ])

    window.addSubview(cover)
    window.bringSubviewToFront(cover)
    _privacyView = cover

    // Smooth entrance: fade + gentle scale-up of the lock.
    stack.alpha = 0
    stack.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
    UIView.animate(
      withDuration: 0.4,
      delay: 0,
      usingSpringWithDamping: 0.85,
      initialSpringVelocity: 0.4,
      options: [.curveEaseOut],
      animations: {
        stack.alpha = 1
        stack.transform = .identity
      }
    )
  }

  /// A 120×120 view with a translucent lock disc and two outward-pulsing rings
  /// that loop forever ("securing" animation). Uses fixed internal frames so it
  /// stays centered regardless of screen size/rotation.
  private func securityLockView() -> UIView {
    let box: CGFloat = 120
    let disc: CGFloat = 74
    let center = CGPoint(x: box / 2, y: box / 2)
    // System tint so it matches the OS accent and adapts to light/dark.
    let accent = UIColor.systemBlue

    let container = UIView(frame: CGRect(x: 0, y: 0, width: box, height: box))

    // Two expanding/fading rings, staggered for a continuous pulse.
    for i in 0..<2 {
      let ring = CALayer()
      ring.frame = CGRect(
        x: center.x - disc / 2, y: center.y - disc / 2,
        width: disc, height: disc)
      ring.cornerRadius = disc / 2
      ring.borderWidth = 2
      ring.borderColor = accent.cgColor
      ring.opacity = 0
      container.layer.addSublayer(ring)

      let scale = CABasicAnimation(keyPath: "transform.scale")
      scale.fromValue = 0.85
      scale.toValue = 1.7
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.5
      fade.toValue = 0.0
      let group = CAAnimationGroup()
      group.animations = [scale, fade]
      group.duration = 2.0
      group.beginTime = CACurrentMediaTime() + Double(i)
      group.repeatCount = .infinity
      group.timingFunction = CAMediaTimingFunction(name: .easeOut)
      ring.add(group, forKey: "pulse")
    }

    // Center disc + lock glyph.
    let discView = UIView(
      frame: CGRect(
        x: center.x - disc / 2, y: center.y - disc / 2,
        width: disc, height: disc))
    discView.backgroundColor = accent.withAlphaComponent(0.12)
    discView.layer.cornerRadius = disc / 2
    container.addSubview(discView)

    let glyph = UIImageView(
      image: UIImage(
        systemName: "lock.fill",
        withConfiguration: UIImage.SymbolConfiguration(
          pointSize: 30, weight: .semibold)))
    glyph.tintColor = accent
    glyph.contentMode = .scaleAspectFit
    glyph.sizeToFit()
    glyph.center = CGPoint(x: disc / 2, y: disc / 2)
    discView.addSubview(glyph)

    // Gentle breathing on the disc so the lock feels alive.
    let breathe = CABasicAnimation(keyPath: "transform.scale")
    breathe.fromValue = 1.0
    breathe.toValue = 1.06
    breathe.duration = 1.5
    breathe.autoreverses = true
    breathe.repeatCount = .infinity
    breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    discView.layer.add(breathe, forKey: "breathe")

    return container
  }

  private func hidePrivacyScreen() {
    guard let cover = _privacyView else { return }
    _privacyView = nil
    UIView.animate(
      withDuration: 0.28,
      delay: 0,
      options: [.curveEaseOut],
      animations: { cover.alpha = 0 },
      completion: { _ in cover.removeFromSuperview() }
    )
  }
}
