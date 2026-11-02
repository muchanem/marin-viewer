#![feature(negative_impls)]
// café 🦀 ensures source coordinates remain canonical UTF-8.
pub mod implementations;
pub mod left {
    pub trait Render<A = ()> {
        fn render(&self) -> usize { 1 }
    }
    pub trait Marker {}
    pub trait Empty {}
}
pub mod right {
    pub trait Render {}
}
pub use left::Render as Alias;
pub struct Alpha;
pub struct Beta;
pub struct Other;
pub struct Wrapper<T>(pub T);
pub struct Negative;
pub fn bounds<T: left::Render>() {}
impl<T: left::Render> Wrapper<T> {
    pub fn inherent(&self) {}
}
