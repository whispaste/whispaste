# Support provider logos (website)

Local copies of the provider marks used on the support tiles (home page support
section and `/sponsor/`). Never hotlinked, no third-party scripts or widgets.

| File | Source | License / basis |
| --- | --- | --- |
| `paypal.svg` | Path from simple-icons 14.13.0 (`icons/paypal.svg`) | CC0 (simple-icons); the mark is PayPal's, see [PayPal media resources](https://newsroom.paypal-corp.com/media-resources) |
| `kofi.svg` | Path from simple-icons 14.13.0 (`icons/kofi.svg`) | CC0 (simple-icons); the mark is Ko-fi's, see [Ko-fi brand assets](https://more.ko-fi.com/brand-assets) |
| `buymeacoffee.svg` | Path from simple-icons 14.13.0 (`icons/buymeacoffee.svg`) | CC0 (simple-icons); the mark is Buy Me a Coffee's |
| `githubsponsors.svg` | Path from simple-icons 14.13.0 (`icons/githubsponsors.svg`), the GitHub Sponsors heart | CC0 (simple-icons); the mark is GitHub's, per [GitHub's logo guidelines](https://brand.github.com/foundations/logo) |

The paths are the same as the app's `assets/social/*-logo.svg` (see its
`NOTICE.md`); only `fill` is `currentColor` so the mark takes the tile's ink
(white on PayPal blue, navy on Ko-fi orange, coffee yellow and Sponsors pink).
Shape unaltered, no effects. `src/data/__tests__/support-links.test.ts` checks
that the paths stay identical to the app's.
