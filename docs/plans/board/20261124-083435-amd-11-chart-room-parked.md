# amd-11 PARKED: wide chart with no room beside it (pt-79c00839f5)
- Fix on local branch w/amd-11/chart-wip: pt-79c00839f5 41 to 677 of 697, with a unit test that fails without it. NOT in a PR: the wide A/B shows 4 drops.
- Drops (756 zh-27a874b740, zh-d62da4dd45 by 1 point each; lo-61f8f967ad8633e0 100 to 50; xb jpn-z17350624-9bde52 98 to 82.3). The header-box fix alone has no drops.
- The rule is too broad. Trigger widths: pt-79c has the chart's left edge past the column (room left negative) and about 13 pt right; jpn has both sides negative; lo is a plain rectangle shape with 6 pt left and 16 pt right. Needs a tighter property and a lab on what Word does for the jpn and lo cases.
