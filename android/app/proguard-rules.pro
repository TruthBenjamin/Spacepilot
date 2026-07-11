# Flutter apps generally don't need custom ProGuard rules.
# Keep this file so Android release builds can enable R8 resource shrinking.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class com.google.protobuf.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class androidx.annotation.** { *; }
-keep public class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
