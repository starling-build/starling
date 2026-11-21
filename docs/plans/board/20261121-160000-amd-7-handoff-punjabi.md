# amd-7 handoff 2026-11-21
- PR 864 (Tamil marked-line surplus at page foot, a347c3b3 page 4): in gate. a347c3b3 page-5 drift ~1 pt/paragraph left (Word gap 31 pt after a marked paragraph, ours 32).
- PR 879 (Punjabi 53342b69): Gurmukhi with Times New Roman cs face draws in Raavi when the document's first Gurmukhi run names Raavi. mean |dy| 7.8 to 1.35. No other Punjabi dx2 doc changed (60aa1e5d stays Nirmala: first run Arial).
- 230be2f4: layout matches; loss is Word's PDF text layer garbling Gurmukhi (nukta/matra order). Scorer issue.
- Next: 827a8947 line 6 onward (-2.13 pt).
- Trap: the wideab base copy goes stale; hash-named dx2 docs dropped for that reason only.
