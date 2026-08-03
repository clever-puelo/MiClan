# ============================================================================
# Reglas de ProGuard/R8 para MiClan
# ============================================================================

# 1. Preservar el Motor de Flutter y sus plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 2. Preservar Google Play Services Location (FGS)
-keep class com.google.android.gms.location.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.android.gms.location.**

# 3. Preservar Google Play Core (Resuelve el error "Missing class" de R8)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# 4. Preservar Firebase (Auth, Core, Firestore)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.firebase.**

# 5. Preservar nuestro Servicio Nativo específico
-keep class com.agiletask.miclan.LocationForegroundService { *; }
-keep class com.agiletask.miclan.MainActivity { *; }

# 6. Reglas generales de seguridad para reflexión y enumeraciones
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Ignorar advertencias de clases internas de Google que no usamos directamente
-dontwarn com.google.android.gms.internal.**
-dontwarn com.google.firebase.internal.**