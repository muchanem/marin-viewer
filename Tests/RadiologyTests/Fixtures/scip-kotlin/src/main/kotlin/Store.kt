package fixture

class Store {
    fun read(id: Int): String = "item:$id"
    fun read(name: String): String = name
}
