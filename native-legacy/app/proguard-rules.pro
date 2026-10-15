# libtorrent4j is a JNI binding: the native layer looks classes up by name and
# calls them reflectively, so its classes and members must survive shrinking.
-keep class org.libtorrent4j.** { *; }
-keepclassmembers class org.libtorrent4j.** { *; }
-dontwarn org.libtorrent4j.**

# junrar is only reachable through the CBR reader.
-keep class com.github.junrar.** { *; }
-dontwarn com.github.junrar.**

# kotlinx.serialization keeps generated serializers referenced reflectively.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class dev.torrentlens.**$$serializer { *; }
-keepclasseswithmembers class dev.torrentlens.** {
    kotlinx.serialization.KSerializer serializer(...);
}
