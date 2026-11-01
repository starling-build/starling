import sys,re,zipfile
s=zipfile.ZipFile(sys.argv[1]).read('word/document.xml').decode('utf8')
i=s.find(sys.argv[2]); j=s.rfind('<w:p ',0,i); k=s.find('</w:p>',i)
p=s[j:k+6]
print(re.sub(r' w:rsid\w*="[^"]*"','',p)[:3000])
