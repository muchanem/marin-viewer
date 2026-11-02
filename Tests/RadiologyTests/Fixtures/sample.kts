// Gradle-style Kotlin script — 放射線
import java.io.File

val scanRoot = File("scans")

fun collect(root: File): List<String> =
    root.listFiles()?.map { it.name } ?: emptyList()

class Report(val title: String) {
    fun render(): String = "$title (${collect(scanRoot).size})"
}

println(Report("胸部").render())
