import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_desktop/src/state/reference_shell_profile.dart';
import 'package:denial_desktop/src/state/reference_shell_presentation.dart';

import 'package:denial_flutter_sdk/popups.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/environment.dart';

import '../desktop/desktop_input_layout_publisher.dart';
import '../diagnostics/desktop_benchmark_binding.dart';
import '../desktop/desktop_pet_holds.dart';
import '../features/mobile/mobile_system_overlay_layer.dart';

import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_flutter_sdk/wallpaper.dart';

import '../widgets/input_layout_publisher.dart';
import '../widgets/mobile_screenshot_flash.dart';
import '../widgets/mobile_volume_hud.dart';
import '../widgets/low_battery_notification_binding.dart';

import 'package:denial_flutter_sdk/rendering.dart';

import '../widgets/edge_panel_layer.dart';
import '../widgets/input_deck/input_deck_layer.dart';
import '../widgets/screenshot_selection_layer.dart';

import 'package:denial_flutter_sdk/shell.dart';

import 'shell_runtime_bindings.dart';
import 'shell_secure_stage.dart';

const _shellDragDevices = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.mouse,
  PointerDeviceKind.unknown,
};

/// The reference plugin's root presentation assembly.
///
/// This plugin supplies mobile and desktop [DenialShellScene] trees. It
/// installs Denial's protocol lifecycle, theme, localization, cursor, input,
/// secure-session, overlay, software-keyboard, and screenshot infrastructure.
class DenialShell extends ConsumerWidget {
  const DenialShell({
    super.key,
    required this.mobile,
    required this.desktop,
    this.pairingSurfaceBuilder,
    this.onLocked,
    this.desktopWorkArea,
  });

  final DenialShellScene mobile;
  final DenialShellScene desktop;
  final DenialPairingSurfaceBuilder? pairingSurfaceBuilder;
  final DenialShellEffect? onLocked;
  final ShellWorkArea? desktopWorkArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(referenceShellProfileProvider);
    final displayLayout = ref.watch(displayLayoutProvider);
    final effectiveProfile = (displayLayout?.outputs.length ?? 0) > 1
        ? ReferenceShellProfile.desktop
        : profile;
    final selectedPresentation = ref.watch(referenceShellPresentationProvider);
    final effectivePresentation = (displayLayout?.outputs.length ?? 0) > 1
        ? ReferenceShellProfile.desktop
        : selectedPresentation;
    final presentation = ref.watch(
      shellSettingsProvider.select(
        (settings) => (
          appearance: settings.appearance,
          animationDurationScale: settings.animations.durationScale,
          locale: settings.localization.localeOverride,
          twentyFourHourClock: settings.localization.twentyFourHourClock,
        ),
      ),
    );
    final appearance = presentation.appearance;
    final startupCursorThemeId = ref
        .watch(startupEnvironmentProvider)['DENIAL_CURSOR_THEME']
        ?.trim();
    final cursorTheme = resolveShellCursorTheme(
      ref.watch(availableShellCursorThemesProvider),
      startupCursorThemeId?.isNotEmpty == true
          ? startupCursorThemeId!
          : appearance.cursorThemeId,
    );
    final accent = ref.watch(
      shellAccentProvider.select((accent) => accent.color),
    );
    final light = appearance.transparencyMode == ShellTransparencyMode.glass
        ? appearance.glass.appearance == ShellGlassAppearance.light
        : appearance.colorSchemePreference.effectiveBrightness ==
              Brightness.light;
    final colors = light ? ShellColorScheme.light : ShellColorScheme.dark;
    final theme = ShellThemeData(
      colors: colors,
      accent: accent,
      fontFamily: appearance.fontFamily,
      cornerRadiusScale: appearance.cornerRadiusScale,
      panelOpacity: appearance.panelOpacity,
      cardOpacity: appearance.cardOpacity,
      transparencyMode: appearance.transparencyMode,
      backdropBlurLevel: appearance.backdropBlurLevel,
      backdropBlurOpacityThreshold: appearance.backdropBlurOpacityThreshold,
      glass: appearance.glass,
      focusedWindowBorderEnabled: appearance.focusedWindowBorderEnabled,
      focusedWindowOpacity: appearance.focusedWindowOpacity,
      unfocusedWindowOpacity: appearance.unfocusedWindowOpacity,
    );
    final bridge = ref.watch(denialBridgeProvider);
    final hideCursor = ref.watch(
      screenshotSelectionProvider.select(
        (session) => session?.hidesCursor ?? false,
      ),
    );
    final scene = _ProfileScene(
      profile: effectivePresentation,
      policyProfile: effectiveProfile,
      scene: effectivePresentation == ReferenceShellProfile.mobile
          ? mobile
          : desktop,
    );
    final fingerprint = ref.watch(fingerprintSceneProvider);
    final locked = ref.watch(
      referenceShellProvider.select((state) => state.locked),
    );
    final content = FingerprintStage(
      scene: fingerprint,
      locked: locked,
      onLaidOut: ref.read(fingerprintSceneProvider.notifier).laidOut,
      child: ShellCursorHost(
        theme: effectivePresentation == ReferenceShellProfile.desktop
            ? cursorTheme
            : ShellCursorThemes.bibataModernIce,
        platformCursorShapes: bridge.cursorShapes,
        platformCursorStates: bridge.cursorStates,
        platformCursorPositions: bridge.cursorPositions,
        platformDragIcons: bridge.dragIcons,
        hideCursor: hideCursor,
        displayLayout: displayLayout,
        cursorSize: appearance.cursorSize,
        onCursorStatePresented: bridge.acknowledgeCursorPresented,
        benchmarkSocket: ref.watch(
          startupEnvironmentProvider,
        )['DENIAL_CURSOR_BENCHMARK_SOCKET'],
        child: ShellOverlayHost(child: scene),
      ),
    );

    return ShellRuntimeBindings(
      mobilePresentation: effectivePresentation == ReferenceShellProfile.mobile,
      workArea: effectivePresentation == ReferenceShellProfile.desktop
          ? desktopWorkArea
          : null,
      pairingSurfaceBuilder: pairingSurfaceBuilder,
      onLocked: onLocked,
      child: AnimatedShellTheme(
        data: theme,
        duration: Duration(
          milliseconds: (200 * presentation.animationDurationScale).round(),
        ),
        child: DenialLocalizationScope(
          locale: presentation.locale,
          twentyFourHourClock: presentation.twentyFourHourClock,
          child: LowBatteryNotificationBinding(
            child: _ShellEnvironment(
              profile: effectivePresentation,
              child: DesktopBenchmarkBinding(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileScene extends StatelessWidget {
  const _ProfileScene({
    required this.profile,
    required this.policyProfile,
    required this.scene,
  });

  final ReferenceShellProfile profile;
  final ReferenceShellProfile policyProfile;
  final DenialShellScene scene;

  @override
  Widget build(BuildContext context) {
    return switch (profile) {
      ReferenceShellProfile.mobile => InputLayoutPublisher(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ShellPopupHost(
              child: ShellSecureStage(
                useConfiguredLockAnimation:
                    policyProfile == ReferenceShellProfile.desktop,
                scene: Stack(
                  fit: StackFit.expand,
                  children: [scene.content, ...scene.overlays],
                ),
                chrome: scene.chrome,
              ),
            ),
            const MobileSystemOverlayLayer(),
            const SystemKeyboardLayer(),
            // Volume shows over the lock screen too, as on any phone.
            const MobileVolumeHud(),
            // Above everything, the lock screen included.
            const MobileScreenshotFlash(),
          ],
        ),
      ),
      ReferenceShellProfile.desktop => DesktopInputLayoutPublisher(
        // The startup profile controls automatic pop-up, not access to the
        // manual edge gesture. Desktop-first touch devices need it too.
        softwareKeyboardEnabled: true,
        child: DesktopPetHoldPublisher(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShellSecureStage(
                useConfiguredLockAnimation:
                    policyProfile == ReferenceShellProfile.desktop,
                scene: Stack(
                  fit: StackFit.expand,
                  children: [
                    ShellPopupHost(
                      // Keep desktop feature popups inside the scene's paint plane.
                      // The screenshot selection layer remains above this overlay,
                      // so its frozen texture includes open menus while its controls
                      // paint and receive input above them.
                      child: ShellOverlayHost(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [scene.content, ...scene.overlays],
                        ),
                      ),
                    ),
                    const InputDeckLayer(),
                    const ScreenshotSelectionLayer(),
                  ],
                ),
              ),
              const SystemKeyboardLayer(),
            ],
          ),
        ),
      ),
    };
  }
}

class _ShellEnvironment extends StatelessWidget {
  const _ShellEnvironment({required this.profile, required this.child});

  final ReferenceShellProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animatedTheme = context.shellTheme;
    final textInputPolicy = TapRegionSurface(
      child: ShellDefaultTextStyle(child: child),
    );
    return MediaQuery(
      data: MediaQueryData.fromView(View.of(context))
          .copyWith(platformBrightness: animatedTheme.brightness),
      child: ScrollConfiguration(
        behavior: const _ShellScrollBehavior(),
        child: profile == ReferenceShellProfile.mobile
            ? MobileTextInputPolicy(child: textInputPolicy)
            : textInputPolicy,
      ),
    );
  }
}

class _ShellScrollBehavior extends ScrollBehavior {
  const _ShellScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => _shellDragDevices;
}
