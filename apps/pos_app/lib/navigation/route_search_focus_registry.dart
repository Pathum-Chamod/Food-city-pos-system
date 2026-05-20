class RouteSearchFocusRegistry {
  RouteSearchFocusRegistry._();

  static final Map<String, void Function()> _handlers = {};

  static void register(String routeName, void Function() handler) {
    _handlers[routeName] = handler;
  }

  static void unregister(String routeName, void Function() handler) {
    if (_handlers[routeName] == handler) {
      _handlers.remove(routeName);
    }
  }

  static void focus(String routeName) {
    _handlers[routeName]?.call();
  }
}
