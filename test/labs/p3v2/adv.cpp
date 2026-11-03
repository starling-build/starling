#include <windows.h>
#include <dwrite.h>
#include <stdio.h>
#include <math.h>
static const double sizes[]={11,13,20,22,25,27,27.2,30,32};
static const int dpis[]={72,96,120,144,192,288,576,600,1200,2400};
static const char* CH="ABCabcdefghijklmnopqrstuvwxyz0123456789 .,";
int main(){
  int nch=(int)strlen(CH);
  // GDI
  HDC dc=CreateCompatibleDC(NULL);
  for(int di=0;di<10;di++) for(int si=0;si<9;si++){
    int dpi=dpis[di]; double sz=sizes[si];
    int ppem=(int)floor(sz*dpi/72.0+0.5);
    LOGFONTW lf={}; lf.lfHeight=-ppem; lf.lfWeight=400; wcscpy_s(lf.lfFaceName,L"Calibri"); lf.lfCharSet=DEFAULT_CHARSET; lf.lfQuality=ANTIALIASED_QUALITY; lf.lfOutPrecision=OUT_TT_ONLY_PRECIS;
    HFONT f=CreateFontIndirectW(&lf); HGDIOBJ old=SelectObject(dc,f);
    for(int ci=0;ci<nch;ci++){
      UINT c=(unsigned char)CH[ci]; INT w=0; GetCharWidth32W(dc,c,c,&w);
      ABC abc={}; GetCharABCWidthsW(dc,c,c,&abc);
      printf("gdi_w32\t%d\t%g\t%c\t%.4f\n",dpi,sz,CH[ci],w*72.0/dpi);
      printf("gdi_abc\t%d\t%g\t%c\t%.4f\n",dpi,sz,CH[ci],(abc.abcA+(int)abc.abcB+abc.abcC)*72.0/dpi);
    }
    SelectObject(dc,old); DeleteObject(f);
  }
  // DirectWrite
  IDWriteFactory* fac=NULL;
  if(FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,__uuidof(IDWriteFactory),(IUnknown**)&fac))){fprintf(stderr,"factory\n");return 1;}
  IDWriteFontFile* ff=NULL; if(FAILED(fac->CreateFontFileReference(L"C:/Windows/Fonts/calibri.ttf",NULL,&ff))){fprintf(stderr,"fontfile\n");return 1;}
  IDWriteFontFace* face=NULL; IDWriteFontFile* arr[1]={ff};
  if(FAILED(fac->CreateFontFace(DWRITE_FONT_FACE_TYPE_TRUETYPE,1,arr,0,DWRITE_FONT_SIMULATIONS_NONE,&face))){fprintf(stderr,"face\n");return 1;}
  DWRITE_FONT_METRICS fm; face->GetMetrics(&fm); double upem=fm.designUnitsPerEm;
  UINT16 gi[256]; UINT32 cp[256];
  for(int ci=0;ci<nch;ci++) cp[ci]=(unsigned char)CH[ci];
  face->GetGlyphIndices(cp,nch,gi);
  for(int natural=0;natural<2;natural++){
    const char* nm=natural?"dw_gdi_natural":"dw_gdi_classic";
    // (a) at GDI-rounded ppem for each dpi, ppd 1
    for(int di=0;di<10;di++) for(int si=0;si<9;si++){
      int dpi=dpis[di]; double sz=sizes[si]; double ppem=floor(sz*dpi/72.0+0.5);
      DWRITE_GLYPH_METRICS gm[256];
      if(FAILED(face->GetGdiCompatibleGlyphMetrics((FLOAT)ppem,1.0f,NULL,natural?TRUE:FALSE,gi,nch,gm,FALSE))){fprintf(stderr,"gm\n");continue;}
      for(int ci=0;ci<nch;ci++) printf("%s_ppem\t%d\t%g\t%c\t%.4f\n",nm,dpi,sz,CH[ci],gm[ci].advanceWidth*ppem/upem*72.0/dpi);
    }
    // (b) pixelsPerDip 1 and 2, emSize = size*96/72 DIPs (fractional ppem, no rounding)
    for(int pi=1;pi<=2;pi++) for(int si=0;si<9;si++){
      double sz=sizes[si]; double em=sz*96.0/72.0; DWRITE_GLYPH_METRICS gm[256];
      if(FAILED(face->GetGdiCompatibleGlyphMetrics((FLOAT)em,(FLOAT)pi,NULL,natural?TRUE:FALSE,gi,nch,gm,FALSE))){fprintf(stderr,"gm2\n");continue;}
      for(int ci=0;ci<nch;ci++){ double px=gm[ci].advanceWidth*em*pi/upem; printf("%s_ppd%d\t%d\t%g\t%c\t%.4f\n",nm,pi,96*pi,sz,CH[ci],px*72.0/(96.0*pi)); }
    }
  }
  return 0;
}
