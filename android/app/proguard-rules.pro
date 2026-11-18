# ML Kit (the lab report document scanner) builds its components through
# Firebase's ComponentDiscovery, which reads each registrar's class name from
# the manifest and instantiates it by reflection. R8 kept the class but dropped
# its no-argument constructor, so the registrar was skipped silently and the
# scanner crashed on start with a NullPointerException (0.56.0+96).
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
