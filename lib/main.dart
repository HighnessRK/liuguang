import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:flutter_miuix/miuix.dart' as mx;
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PaintingContextCallback;
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import 'core/api.dart';
import 'core/models.dart';
import 'core/store.dart';
import 'core/updates.dart';
import 'screens/updates.dart';
import 'screens/create.dart';
import 'screens/editor.dart';
import 'screens/library.dart';
import 'screens/settings.dart';
import 'ui/glass.dart';
import 'ui/navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kProfileMode) {
    final frames = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback((batch) {
      frames.addAll(batch);
      if (frames.length >= 120) {
        final build = frames.map((f) => f.buildDuration.inMicroseconds).toList()
          ..sort();
        final raster =
            frames.map((f) => f.rasterDuration.inMicroseconds).toList()..sort();
        debugPrint(
          'LIUGUANG_FRAME_PROFILE samples=${frames.length} build_p90_ms=${build[(build.length * .9).floor()] / 1000} raster_p90_ms=${raster[(raster.length * .9).floor()] / 1000}',
        );
        frames.clear();
      }
    });
  }
  await LiquidGlass.precache();
  LicenseRegistry.addLicense(() async* {
    for (final library in ['miuix', 'liquidglass']) {
      yield LicenseEntryWithLineBreaks([
        library,
      ], await rootBundle.loadString('assets/licenses/$library.txt'));
    }
  });
  final store = AppStore();
  await store.init();
  await AppLog.init(store.directory);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(AppLog.record('flutter_framework_error'));
  };
  runApp(LiuguangApp(store: store));
}

class LiuguangApp extends StatelessWidget {
  final AppStore store;
  final StudioApi? api;
  const LiuguangApp({super.key, required this.store, this.api});
  @override
  Widget build(BuildContext context) => StudioScope(
    store: store,
    child: ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: '琉光',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        scrollBehavior: const StudioScrollBehavior(),
        themeMode: switch (store.theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        builder: (context, child) => mx.MiuixTheme(
          data: studioMiuixTheme(context, store),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1) * store.textScale,
              ),
              disableAnimations:
                  store.reduceMotion ||
                  MediaQuery.of(context).disableAnimations,
            ),
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    Theme.of(context).brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    Theme.of(context).brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
              child: child!,
            ),
          ),
        ),
        home: StudioHome(store: store, api: api),
      ),
    ),
  );
  ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: StudioPageTransitions()},
    ),
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Color(store.accent),
      brightness: brightness,
    ),

    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Color(store.accent),
      selectionColor: Color(store.accent).withValues(alpha: .2),
      selectionHandleColor: Color(store.accent),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme:
        (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light())
            .textTheme
            .apply(
              bodyColor: brightness == Brightness.dark
                  ? const Color(0xfff1f4fa)
                  : const Color(0xff19212f),
              displayColor: brightness == Brightness.dark
                  ? const Color(0xfff1f4fa)
                  : const Color(0xff19212f),
            ),
  );
}

mx.MiuixThemeData studioMiuixTheme(BuildContext context, AppStore store) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = dark ? mx.MiuixThemeData.dark() : mx.MiuixThemeData.light();
  final primary = dark
      ? Color.lerp(Color(store.accent), Colors.white, .42)!
      : Color(store.accent);
  return base.copyWith(
    colors: base.colors.copy(
      primary: primary,
      onPrimary: dark ? const Color(0xff15202c) : Colors.white,
      primaryVariant: primary.withValues(alpha: dark ? .22 : .12),
      onPrimaryVariant: primary,
      primaryContainer: primary.withValues(alpha: dark ? .22 : .12),
      onPrimaryContainer: primary,
      disabledPrimary: primary.withValues(alpha: .35),
      disabledPrimaryButton: primary.withValues(alpha: .18),
      disabledPrimarySlider: primary.withValues(alpha: .18),
    ),
  );
}

class StudioHome extends StatefulWidget {
  final AppStore store;
  final StudioApi? api;
  const StudioHome({super.key, required this.store, this.api});
  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> with WidgetsBindingObserver {
  bool checkingUpdates = false;
  Future<void> checkUpdates() async {
    if (!mounted || checkingUpdates || AppLog.file == null) return;
    checkingUpdates = true;
    try {
      await checkForAppUpdates(context, widget.store);
    } finally {
      checkingUpdates = false;
    }
  }

  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int index = 0, editorRevision = 0;
  String? editorPath, reusedPrompt;
  late final StudioApi api = widget.api ?? StudioApi(widget.store);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.store.prefs.getBool('restore_checkpoint') == true) {
      widget.store.prefs.remove('restore_checkpoint');
      index = (widget.store.prefs.getInt('last_page') ?? 0).clamp(0, 3);
      try {
        final checkpoint = jsonDecode(
          widget.store.prefs.getString('editor_checkpoint') ?? '{}',
        );
        final value = checkpoint['path'];
        if (value is String && File(value).existsSync()) editorPath = value;
      } catch (_) {}
    }

    const MethodChannel('liuguang/memory').setMethodCallHandler((call) async {
      if (call.method != 'checkpoint') return null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await widget.store.memoryCheckpoint?.call(call.arguments == true);
      await widget.store.prefs.setInt('last_page', index);
      await widget.store.prefs.setBool('restore_checkpoint', true);
      await widget.store.saveCatalog();
      return true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.store.storageWarning != null) {
        toast(context, widget.store.storageWarning!);
      }
      checkUpdates();
    });
  }

  void edit(String path) => setState(() {
    editorPath = path;
    index = 1;
    editorRevision++;
  });
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(
                bottom: MediaQuery.viewInsetsOf(context).bottom == 0
                    ? MediaQuery.paddingOf(context).bottom + 90
                    : 0,
                child: IndexedStack(
                  index: index,
                  children:
                      [
                            CreateScreen(
                              store: widget.store,
                              api: api,
                              initialPrompt: reusedPrompt,
                              onSettings: () => setState(() => index = 3),
                              onEdit: edit,
                            ),
                            EditorScreen(
                              key: ValueKey(editorRevision),
                              store: widget.store,
                              api: api,
                              initialPath: editorPath,
                              onClose: () => setState(() {
                                editorPath = null;
                                editorRevision++;
                              }),
                              onSettings: () => setState(() => index = 3),
                            ),
                            LibraryScreen(
                              store: widget.store,
                              active: index == 2,
                              onGif: () {
                                widget.store.defaults.format = 'gif';
                                widget.store.imageApi.protocol =
                                    ApiProtocol.gptImage;
                                widget.store.saveSettings();
                                setState(() => index = 0);
                              },
                              onEdit: edit,
                              onReuse: (p) => setState(() {
                                reusedPrompt = p;
                                index = 0;
                              }),
                            ),
                            SettingsScreen(store: widget.store, api: api),
                          ]
                          .asMap()
                          .entries
                          .map(
                            (entry) => TickerMode(
                              enabled: entry.key == index,
                              child: RepaintBoundary(
                                child: ClipRect(
                                  child: LiquidGlassLayer(
                                    settings: glassSettings(context),
                                    child: entry.value,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 14,
                  child: LiquidNavigation(
                    selected: index,
                    onChanged: (i) => setState(() => index = i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioScrollBehavior extends MaterialScrollBehavior {
  const StudioScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

class StudioPageTransitions extends PageTransitionsBuilder {
  const StudioPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return _StudioRouteTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      allowSnapshotting: route.allowSnapshotting,
      child: child,
    );
  }
}

// Freeze the expensive glass pass only for the bounded page transition.
// Release the texture at either endpoint; in-page glass stays fully live.
class _StudioRouteTransition extends StatefulWidget {
  final Animation<double> animation, secondaryAnimation;
  final bool allowSnapshotting;
  final Widget child;
  const _StudioRouteTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.allowSnapshotting,
    required this.child,
  });
  @override
  State<_StudioRouteTransition> createState() => _StudioRouteTransitionState();
}

class _StudioRouteTransitionState extends State<_StudioRouteTransition> {
  final snapshot = SnapshotController();
  late Animation<Offset> position;
  late CurvedAnimation curve;
  late _StudioSlidePainter painter;

  void updateSnapshot(AnimationStatus _) {
    snapshot.allowSnapshotting =
        !kIsWeb &&
        widget.allowSnapshotting &&
        (widget.animation.status.isAnimating ||
            widget.secondaryAnimation.status.isAnimating);
  }

  void attach() {
    curve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    position = Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(curve);
    painter = _StudioSlidePainter(position);
    widget.animation.addStatusListener(updateSnapshot);
    widget.secondaryAnimation.addStatusListener(updateSnapshot);
    updateSnapshot(widget.animation.status);
  }

  void detach(_StudioRouteTransition previous) {
    previous.animation.removeStatusListener(updateSnapshot);
    previous.secondaryAnimation.removeStatusListener(updateSnapshot);
    painter.dispose();
    curve.dispose();
  }

  @override
  void initState() {
    super.initState();
    attach();
  }

  @override
  void didUpdateWidget(covariant _StudioRouteTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      detach(oldWidget);
      attach();
    } else {
      updateSnapshot(widget.animation.status);
    }
  }

  @override
  void dispose() {
    detach(widget);
    snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: snapshot,
    painter: painter,
    mode: SnapshotMode.permissive,
    autoresize: true,
    child: RepaintBoundary(child: widget.child),
  );
}

// Transform the resulting texture, not the capture's widget coordinates.
// Liquid glass computes its sampling clip in global coordinates; translating
// the capture itself while rasterizing it at (0, 0) clips the wrong region.
class _StudioSlidePainter extends SnapshotPainter {
  final Animation<Offset> position;
  _StudioSlidePainter(this.position) {
    position.addListener(notifyListeners);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    context.pushTransform(
      true,
      offset,
      Matrix4.translationValues(size.width * position.value.dx, 0, 0),
      painter,
    );
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size imageSize,
    double pixelRatio,
  ) {
    context.canvas.drawImageRect(
      image,
      Offset.zero & imageSize,
      (offset + Offset(size.width * position.value.dx, 0)) & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _StudioSlidePainter oldPainter) =>
      oldPainter.position != position;

  @override
  void dispose() {
    position.removeListener(notifyListeners);
    super.dispose();
  }
}
