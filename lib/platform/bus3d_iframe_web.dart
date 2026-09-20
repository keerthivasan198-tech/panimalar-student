// Web implementation of bus3d iframe helper.
// Only compiled on Flutter Web target.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

dynamic makeBus3dIframe() {
  final iframe = html.IFrameElement()
    ..src = 'bus3d.html'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.border = 'none'
    ..style.background = 'transparent'
    ..setAttribute('allow', '*');
  return iframe;
}
