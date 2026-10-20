# Plugins called from Dart through JNI (e.g. shared_preferences_android 2.5+)
# look up classes and methods by name, so R8 must not rename or remove them.
-keep class io.flutter.plugins.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.tundralabs.fluttertts.** { *; }
-keep class xyz.luan.audioplayers.** { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
# Suspend functions take a Continuation as their last parameter.
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn com.google.android.play.core.**
# The JNI bridge also reaches Kotlin runtime classes such as kotlin.Result by name.
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
