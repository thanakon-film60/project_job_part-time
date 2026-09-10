allprojects {
    repositories {
        google()
        mavenCentral()

        // ===================================================================
        // Maven ของ Tange — ที่เดียวที่มี native AAR ของ TiRTC (com.tange.ai:tirtc)
        // ใช้โดย tirtc_flutter สำหรับปุ่ม "กดค้างเพื่อพูด" ในแท็บกล้อง
        //
        // เป็น http ธรรมดาและบัญชีที่ใช้เป็นค่าสาธารณะจากคู่มือ Tange
        // (ไม่ใช่ความลับของเรา และไม่ใช่ credential ของ TiRTC ที่อยู่ใน .env
        // ฝั่ง backend) จึงต้องเปิด isAllowInsecureProtocol
        //
        // ล็อกด้วย includeGroup ไว้ ไม่งั้น dependency ตัวอื่นทั้งโปรเจ็กต์จะถูก
        // ไล่หาผ่าน http ที่ไม่ได้เข้ารหัสไปด้วย ซึ่งเปิดช่องให้ถูกสลับไฟล์กลางทาง
        // ถ้าวันหน้า Tange ย้ายขึ้น https ให้ถอด isAllowInsecureProtocol ออก
        // ===================================================================
        maven {
            url = uri("http://repo-sdk.tange-ai.com/repository/maven-public/")
            isAllowInsecureProtocol = true
            credentials {
                username = "tange_user"
                password = "tange_user"
            }
            content {
                includeGroup("com.tange.ai")
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
