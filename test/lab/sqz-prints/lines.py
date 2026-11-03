FONTS = ['Calibri', 'Times New Roman']; SIZES = [10, 12, 14]
LINES = {1: 'Considerable administration', 3: 'Everyone has the administration', 8: 'Everyone has the right to a standard of administration'}
CONT = ' and other lack of livelihood in circumstances beyond his control.'
def run(f, sz, t): return '<w:r><w:rPr><w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s"/><w:sz w:val="%d"/><w:szCs w:val="%d"/><w:lang w:val="en-US"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (f, f, f, sz*2, sz*2, t)
