plugins {
    `kotlin-dsl`
}

repositories {
    mavenCentral()
}

gradlePlugin {
    plugins {
        create("buildSlots") {
            id = "fa.build-slots"
            implementationClass = "BuildSlotsPlugin"
        }
    }
}
