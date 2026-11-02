package fixture

fun changed(store: Store): String {
    val label = "café 🚀"; return label + store.read(2)
}

fun untouched(store: Store): String = store.read("name")
