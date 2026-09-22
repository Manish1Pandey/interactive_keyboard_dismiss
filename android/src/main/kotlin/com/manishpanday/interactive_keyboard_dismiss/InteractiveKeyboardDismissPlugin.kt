package com.manishpanday.interactive_keyboard_dismiss

import android.app.Activity
import android.os.Build
import android.os.CancellationSignal
import android.view.Choreographer
import android.view.animation.LinearInterpolator
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsAnimationControlListenerCompat
import androidx.core.view.WindowInsetsAnimationControllerCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.roundToInt

/**
 * Drives the Android IME with the user's finger through
 * [WindowInsetsAnimationControllerCompat] (API 30+).
 *
 * While the controller is held, every `update` sets the IME bottom inset with
 * `setInsetsAndAlpha`. Flutter's embedding (ImeSyncDeferringInsetsCallback)
 * receives the resulting WindowInsetsAnimation progress and forwards the
 * moving inset to `FlutterView.viewInsets`, so the Flutter layout moves in the
 * same frame. On release a critically damped spring (mass 1, stiffness 400,
 * damping 40 — identical to the Dart side) settles the inset and the
 * controller is finished shown or hidden.
 *
 * Below API 30, or when the system refuses control, `begin` answers
 * `started: false` and the Dart side dismisses the keyboard on drag instead.
 */
class InteractiveKeyboardDismissPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private var activity: Activity? = null

  private var controller: WindowInsetsAnimationControllerCompat? = null
  private var cancellationSignal: CancellationSignal? = null
  private var requested = false
  private var finishingByUs = false
  /** Incremented per `begin`; callbacks of older control requests are ignored. */
  private var session = 0

  private var fraction = 0f
  private var pendingEnd: Pair<Boolean, Double>? = null
  private var pendingEndResult: MethodChannel.Result? = null
  private var spring: SpringRunner? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "interactive_keyboard_dismiss")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    release(shown = true)
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    release(shown = true)
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    release(shown = true)
    activity = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "begin" -> result.success(begin())
      "update" -> {
        update((call.argument<Double>("fraction") ?: 0.0).toFloat())
        result.success(null)
      }
      "end" -> end(
        dismiss = call.argument<Boolean>("dismiss") ?: false,
        velocity = call.argument<Double>("velocity") ?: 0.0,
        result = result,
      )
      "cancel" -> {
        release(shown = true)
        result.success(null)
      }
      "diagnostics" -> result.success(diagnostics())
      else -> result.notImplemented()
    }
  }

  // ------------------------------------------------------------------ begin

  private fun begin(): Map<String, Any> {
    val notStarted = mapOf<String, Any>("started" to false, "liveInsets" to true)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return notStarted
    val activity = activity ?: return notStarted
    val window = activity.window ?: return notStarted
    val decor = window.decorView
    val insets = ViewCompat.getRootWindowInsets(decor) ?: return notStarted
    if (!insets.isVisible(WindowInsetsCompat.Type.ime())) return notStarted

    release(shown = true)
    fraction = 0f
    pendingEnd = null
    finishingByUs = false
    requested = true
    val signal = CancellationSignal()
    cancellationSignal = signal
    WindowCompat.getInsetsController(window, decor).controlWindowInsetsAnimation(
      WindowInsetsCompat.Type.ime(),
      -1L,
      LinearInterpolator(),
      signal,
      ControlListener(++session),
    )
    return mapOf("started" to true, "liveInsets" to true)
  }

  private inner class ControlListener(private val id: Int) :
    WindowInsetsAnimationControlListenerCompat {
    override fun onReady(controller: WindowInsetsAnimationControllerCompat, types: Int) {
      if (id != session || !requested) {
        controller.finish(true)
        return
      }
      this@InteractiveKeyboardDismissPlugin.controller = controller
      applyFraction(fraction)
      pendingEnd?.let { (dismiss, velocity) ->
        pendingEnd = null
        startSettle(dismiss, velocity)
      }
    }

    override fun onFinished(controller: WindowInsetsAnimationControllerCompat) {
      if (id == session) onControlEnded(cancelled = false)
    }

    override fun onCancelled(controller: WindowInsetsAnimationControllerCompat?) {
      if (id == session) onControlEnded(cancelled = true)
    }
  }

  private fun onControlEnded(cancelled: Boolean) {
    val wasOurs = finishingByUs
    controller = null
    cancellationSignal = null
    requested = false
    finishingByUs = false
    spring?.stop()
    spring = null
    pendingEnd = null
    completePendingEnd()
    if (cancelled && !wasOurs) {
      // The system took the IME away (refused control, IME closed, window
      // lost focus): tell Dart so it stops tracking and falls back.
      channel.invokeMethod("onInteractionCancelled", null)
    }
  }

  // ----------------------------------------------------------------- update

  private fun update(value: Float) {
    if (!requested) return
    spring?.stop()
    spring = null
    fraction = value.coerceIn(0f, 1f)
    applyFraction(fraction)
  }

  private fun applyFraction(value: Float) {
    val c = controller ?: return
    if (!c.isReady) return
    val shown = c.shownStateInsets.bottom
    val hidden = c.hiddenStateInsets.bottom
    val bottom = (shown - value * (shown - hidden)).roundToInt()
    c.setInsetsAndAlpha(Insets.of(0, 0, 0, bottom), 1f, value)
  }

  // -------------------------------------------------------------------- end

  private fun end(dismiss: Boolean, velocity: Double, result: MethodChannel.Result) {
    if (!requested) {
      result.success(null)
      return
    }
    completePendingEnd()
    pendingEndResult = result
    if (controller == null) {
      // Not ready yet: settle as soon as onReady arrives.
      pendingEnd = Pair(dismiss, velocity)
      return
    }
    startSettle(dismiss, velocity)
  }

  private fun startSettle(dismiss: Boolean, velocity: Double) {
    spring?.stop()
    val target = if (dismiss) 1.0 else 0.0
    val runner = SpringRunner(
      from = fraction.toDouble(),
      to = target,
      velocity = velocity,
      onFrame = { value ->
        fraction = value.toFloat()
        applyFraction(fraction)
      },
      onDone = {
        spring = null
        fraction = target.toFloat()
        applyFraction(fraction)
        finishControl(shown = !dismiss)
      },
    )
    spring = runner
    runner.start()
  }

  private fun finishControl(shown: Boolean) {
    val c = controller
    if (c != null && c.isReady) {
      finishingByUs = true
      c.finish(shown)
    } else {
      onControlEnded(cancelled = false)
    }
  }

  /** Ends any interaction immediately, leaving the IME [shown] or hidden. */
  private fun release(shown: Boolean) {
    spring?.stop()
    spring = null
    pendingEnd = null
    val c = controller
    when {
      c != null && c.isReady -> {
        finishingByUs = true
        c.finish(shown)
      }
      requested -> {
        finishingByUs = true
        requested = false
        cancellationSignal?.cancel()
      }
    }
    controller = null
    cancellationSignal = null
    requested = false
    finishingByUs = false
    session++
    completePendingEnd()
  }

  private fun completePendingEnd() {
    val pending = pendingEndResult
    pendingEndResult = null
    pending?.success(null)
  }

  // ------------------------------------------------------------ diagnostics

  private fun diagnostics(): Map<String, Any?> {
    val decor = activity?.window?.decorView
    val insets = decor?.let { ViewCompat.getRootWindowInsets(it) }
    return mapOf(
      "platform" to "android",
      "sdkInt" to Build.VERSION.SDK_INT,
      "interactiveSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R),
      "imeVisible" to (insets?.isVisible(WindowInsetsCompat.Type.ime()) ?: false),
      "imeBottomPx" to (insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0),
      "controlling" to (controller != null),
    )
  }
}

/**
 * Critically damped spring (mass 1, stiffness 400, damping 40; must match
 * `keyboardSpring` in lib/src/release_decision.dart) driven by [Choreographer].
 * Values are keyboard fractions; [velocity] is in fractions per second.
 */
private class SpringRunner(
  private val from: Double,
  private val to: Double,
  private val velocity: Double,
  private val onFrame: (Double) -> Unit,
  private val onDone: () -> Unit,
) : Choreographer.FrameCallback {
  private val omega = 20.0 // sqrt(stiffness / mass); damping = 2 * omega * mass
  private var startNanos = -1L
  private var stopped = false

  fun start() {
    Choreographer.getInstance().postFrameCallback(this)
  }

  fun stop() {
    stopped = true
    Choreographer.getInstance().removeFrameCallback(this)
  }

  override fun doFrame(frameTimeNanos: Long) {
    if (stopped) return
    if (startNanos < 0) startNanos = frameTimeNanos
    val t = (frameTimeNanos - startNanos) / 1_000_000_000.0
    val a = from - to
    val b = velocity + omega * a
    val decay = exp(-omega * t)
    val position = to + (a + b * t) * decay
    val speed = (b - omega * (a + b * t)) * decay
    if (abs(position - to) < 0.001 && abs(speed) < 0.01) {
      stopped = true
      onDone()
      return
    }
    onFrame(position.coerceIn(0.0, 1.0))
    Choreographer.getInstance().postFrameCallback(this)
  }
}
