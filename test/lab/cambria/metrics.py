from fontTools.ttLib import TTFont, TTCollection
out=[]
def row(tag,f):
    h=f['hhea']; o=f['OS/2']
    out.append('\t'.join(map(str,[tag,f['head'].unitsPerEm,h.ascent,h.descent,h.lineGap,o.sTypoAscender,o.sTypoDescender,o.sTypoLineGap,o.usWinAscent,o.usWinDescent,(o.fsSelection>>7)&1,o.fsSelection])))
c=TTCollection('C:/Windows/Fonts/cambria.ttc')
for i,f in enumerate(c.fonts): row('cambria.ttc#%d %s'%(i,f['name'].getDebugName(4)),f)
for fn in ('cambriab.ttf','cambriai.ttf','cambriaz.ttf'):
    f=TTFont('C:/Windows/Fonts/'+fn); row(fn+' '+f['name'].getDebugName(4),f)
hdr='# font\tunitsPerEm\thhea_asc\thhea_desc\thhea_gap\ttypo_asc\ttypo_desc\ttypo_gap\twinAscent\twinDescent\tUSE_TYPO_METRICS\tfsSelection'
open('CAMBRIA-METRICS.tsv','w',encoding='utf8').write(hdr+'\n'+'\n'.join(out)+'\n'); print(hdr); print('\n'.join(out))
