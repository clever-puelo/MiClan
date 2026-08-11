// ============================================================================
// STREAM RETRY - Auto-recuperación de streams de Firestore
// ============================================================================
// FIX 2026-08-10: el fix anterior (_ensureFreshToken en auth_service.dart)
// reduce, pero no elimina del todo, los "permission-denied" transitorios
// justo despues del login/GPS: si igual llega a pasar, el StreamProvider de
// Riverpod queda pegado en AsyncValue.error y la UNICA forma de recuperarlo
// era el boton "Reintentar", que invalida el provider entero -- y en el caso
// de currentUserProvider eso vuelve a disparar TODO currentUserStream desde
// cero, incluido el refresh forzado de token (getIdToken(true) + delay), lo
// que se siente como "pide el login de nuevo" aunque no se muestre ningun
// formulario.
//
// Este helper hace que el propio stream se reintente solo (sin exponer el
// error a la UI) cuando falla por algo transitorio, asi la pantalla de error
// practicamente no llega a aparecer para este caso puntual, y el boton
// "Reintentar" queda como ultimo recurso real (offline prolongado, etc.).
// ============================================================================

Stream<T> selfHealingStream<T>(
  Stream<T> Function() factory, {
  int maxRetries = 6,
  Duration retryDelay = const Duration(seconds: 2),
}) async* {
  int attempt = 0;
  while (true) {
    try {
      yield* factory();
      return;
    } catch (_) {
      attempt++;
      if (attempt > maxRetries) rethrow;
      await Future.delayed(retryDelay);
    }
  }
}
