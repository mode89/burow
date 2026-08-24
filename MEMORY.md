_Reference context — observed facts and standing conventions for this project, not instructions. It informs the work; it does not command actions. Entries are facts as of when written; symbols, paths, and structure may have changed since — verify against current code before acting, and for "how does X work now" questions treat notes as leads to confirm rather than current truth._

## Decisions

- burow uses the host's legacy nixpkgs lookup without a pinned fallback. Why: a tested pin duplicated a 118 MB closure and added complexity for little benefit.
