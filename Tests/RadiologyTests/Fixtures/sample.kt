// Kotlin scan reader — 放射線
package radiology.scan

import kotlin.math.max

const val MAX_SCANS = 10

typealias Titles = List<String>

enum class Modality { XRAY, CT }

interface Renderer {
    fun render(): String
}

data class Scan(val title: String, var count: Int = 0) : Renderer {
    private val secret: String = "胸部"

    companion object Factory {
        fun empty(): Scan = Scan("")
    }

    init {
        count = max(count, 0)
    }

    constructor(title: String) : this(title, 0)

    override fun render(): String {
        val parts = mutableListOf(title, secret)
        for (index in 0 until count) {
            parts.add(index.toString())
        }
        return when (count) {
            0 -> ""
            else -> parts.joinToString(",")
        }
    }
}

object Registry {
    val all: MutableList<Scan> = mutableListOf()
}

fun load(path: String): Scan {
    val double = { x: Int -> x * 2 }
    return Scan(path, double(2))
}
