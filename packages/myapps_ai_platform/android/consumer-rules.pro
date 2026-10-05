# ML Kit shared internals and coroutine bridges are required in release builds.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
