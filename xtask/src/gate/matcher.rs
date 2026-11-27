//! Matching log lines against a gate's ordered expectations.

use regex::Regex;

/// Walks through `expect` in order. Each expectation must match some line
/// after the line that matched the previous one; one line may satisfy
/// several consecutive expectations.
pub struct Matcher<'a> {
    expect: &'a [Regex],
    next: usize,
}

impl<'a> Matcher<'a> {
    pub fn new(expect: &'a [Regex]) -> Self {
        Self { expect, next: 0 }
    }

    /// Feed one line; returns true if it advanced the matcher.
    pub fn feed(&mut self, line: &str) -> bool {
        let start = self.next;
        while self.next < self.expect.len() && self.expect[self.next].is_match(line) {
            self.next += 1;
        }
        self.next > start
    }

    pub fn done(&self) -> bool {
        self.next == self.expect.len()
    }

    /// The first expectation not yet matched, as (1-based index, regex).
    pub fn pending(&self) -> Option<(usize, &Regex)> {
        self.expect.get(self.next).map(|re| (self.next + 1, re))
    }

    pub fn matched(&self) -> usize {
        self.next
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn res(pats: &[&str]) -> Vec<Regex> {
        pats.iter().map(|p| Regex::new(p).unwrap()).collect()
    }

    #[test]
    fn matches_in_order() {
        let e = res(&["^a", "^b"]);
        let mut m = Matcher::new(&e);
        assert!(!m.feed("b first does not count"));
        assert!(m.feed("a"));
        assert!(!m.feed("a again"));
        assert!(m.feed("b"));
        assert!(m.done());
    }

    #[test]
    fn one_line_can_satisfy_consecutive_expectations() {
        let e = res(&["kernel", "base=0x"]);
        let mut m = Matcher::new(&e);
        m.feed("aOS kernel 0.1.0 base=0xffff");
        assert!(m.done());
    }

    #[test]
    fn reports_pending() {
        let e = res(&["x", "y"]);
        let mut m = Matcher::new(&e);
        m.feed("x");
        let (i, re) = m.pending().unwrap();
        assert_eq!((i, re.as_str()), (2, "y"));
        assert_eq!(m.matched(), 1);
    }

    #[test]
    fn empty_expectations_are_done() {
        assert!(Matcher::new(&[]).done());
    }
}
