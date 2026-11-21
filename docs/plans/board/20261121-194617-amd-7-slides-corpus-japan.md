# amd-7 HANDOFF: Slides corpus, Japan (2026-11-21)

Target 65, delivered 52 Japanese decks in /data/corpus-cache/staging/pptx-new/amd-7/ (manifest.tsv: sha256, url, language, slides, title). 340 MB.
- 19 organisations (max 3 each): osaka-u, soumu, rehab, pref.saitama, pref.hiroshima, nta, maff, hyogo-c.ed, fsa, digital, jma, tcu (comm.tcu.ac.jp), yokohama, cbr.mlit, mhlw bosei-navi, anabuki, tokushima, fukui, tokyo infoedu.
- Filters applied: 10+ slides, <30 MB, SHA-256 dedupe (incl. pilot decks), PII scan (free-mail, mobile numbers) on slide+notes, Japanese text >= 20%, no licence filter.
- Why short of 65: discovery. Search engines do not index pptx; most ministry/city pages post PDF only; many pptx are under 10 slides or old .ppt. Common Crawl index was down (503/504). I crawled about 100 listing pages, two levels deep.
- Left: ~13 decks. Ideas: Kyoto/Tokyo OCW, more prefectural education centres, ministries not yet used (env, meti regional, cao). Tools: /data/s/amd-7/jp/{crawl2.py,crawl3.py,pull.py,state.json} (pull.py is resumable; usage `python3 -I pull.py 65 < cand.txt`).
- Not looked at: the held-out set.
