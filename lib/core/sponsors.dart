/// Opt-in sponsor recognition list — see `SPONSORS.md` at the repo root for
/// how an entry comes about. Deliberately empty until a real sponsor opts in;
/// nothing is added here automatically just because someone sponsored the
/// project. The About page's supporter section stays hidden while this list
/// is empty.
library;

/// A single opt-in sponsor entry. [url] is optional (a sponsor may want to be
/// named without linking anywhere).
typedef Sponsor = ({String name, String? url});

const List<Sponsor> kSponsors = [];
