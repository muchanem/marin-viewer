use crate::{Alias, Alpha, Beta, Other, Wrapper, Negative, left, right};
impl Alias for Alpha {
    fn render(&self) -> usize { 2 }
}
impl crate::left::Render<()> for Beta {}
impl<T> left::Render<T> for Wrapper<T>
where T: Copy {}
impl right::Render for Other {}
impl !left::Marker for Negative {}
