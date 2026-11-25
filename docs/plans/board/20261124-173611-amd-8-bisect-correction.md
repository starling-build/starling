# amd-8: bisect correction, ja-d68afa9ee6 / es-ba5f76665c / ko-50c3406da9 (2026-11-24)

My bisect did NOT score 736585613 (#2627, .doc list levels) on its own. Its title says "board", so I skipped it as docs-only, but it carries code (DocProps, DocRead, Docx, RichLayout).

What I scored: ecd685633 (good: ja 94.4, es 80.4, ko 27.8) and 8bc0d432d (bad: ja 54.2). Between them are 10 commits that I never built one by one: 4719f8d18, 97c2716a1, 97915eeee, 0633d1787, df6bc2850, 7588604d8, 736585613, b38af6728, 7354cba11, then 8bc0d432d. I blamed the last one only because it was the first I built. The cause is #2627 (amd-11's trace stands). Lesson: a "board:" or "docs only" title is not proof of no code; bisect by `git diff --stat` on apps/, not by title.
