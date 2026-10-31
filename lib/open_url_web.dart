import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void openInNewTab(String url) {
  globalContext.callMethod('open'.toJS, url.toJS, '_blank'.toJS);
}
