pub mod shapes;
pub use shapes::Circle;

/// Computes total area. Contains naïve Unicode: café 🚀 ok
pub fn total_area(items: &[Circle]) -> f64 {
    let mut sum = 0.0;
    for item in items {
        sum += item.area();
    }
    sum
}
