param($Out)
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic; using System.IO;
public static class Adv {
 [StructLayout(LayoutKind.Sequential)] public struct ABC { public int a; public uint b; public int c; }
 [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
 [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr dc, int i);
 [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateFontW(int h,int w,int e,int o,int wt,uint it,uint u,uint s,uint cs,uint op,uint cp,uint q,uint pf,string face);
 [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
 [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
 [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern int GetTextFaceW(IntPtr dc, int n, StringBuilder sb);
 [DllImport("gdi32.dll")] static extern bool GetCharWidth32W(IntPtr dc, uint a, uint b, out int w);
 [DllImport("gdi32.dll")] static extern bool GetCharABCWidthsW(IntPtr dc, uint a, uint b, out ABC abc);
 public static int Dpi(){ IntPtr dc=GetDC(IntPtr.Zero); int d=GetDeviceCaps(dc,88); ReleaseDC(IntPtr.Zero,dc); return d; }
 public static void Run(string path, string[] faces, double[] sizes, int[] styles, uint[][] ranges){
  IntPtr dc=GetDC(IntPtr.Zero);
  using(var w=new StreamWriter(path,false,new UTF8Encoding(false))){
   w.WriteLine("# face\tactual_face\tsize_pt\tlfHeight\tbold\titalic\tcode\tcw32_px\tabc_a\tabc_b\tabc_c\tabc_adv_px");
   foreach(var face in faces) foreach(var sz in sizes) foreach(var st in styles){
    bool bold=(st&1)!=0, it=(st&2)!=0;
    int h=-(int)Math.Round(sz*96.0/72.0, MidpointRounding.AwayFromZero);
    IntPtr f=CreateFontW(h,0,0,0,bold?700:400,it?1u:0u,0,0,1,0,0,0,0,face); IntPtr old=SelectObject(dc,f);
    var sb=new StringBuilder(64); GetTextFaceW(dc,64,sb);
    foreach(var r in ranges) for(uint c=r[0]; c<=r[1]; c++){
     int cw; GetCharWidth32W(dc,c,c,out cw); ABC abc; GetCharABCWidthsW(dc,c,c,out abc);
     w.WriteLine(face+"\t"+sb+"\t"+sz.ToString(System.Globalization.CultureInfo.InvariantCulture)+"\t"+h+"\t"+(bold?1:0)+"\t"+(it?1:0)+"\tU+"+c.ToString("X4")+"\t"+cw+"\t"+abc.a+"\t"+abc.b+"\t"+abc.c+"\t"+(abc.a+(int)abc.b+abc.c));
    }
    SelectObject(dc,old); DeleteObject(f);
   }
  }
  ReleaseDC(IntPtr.Zero,dc);
 }
}
'@
"dpi=$([Adv]::Dpi())"
$sizes=[double[]](8,9,10,10.5,11,12,14,16,18,20,24)
$latin=@([uint32[]](0x20,0x7E),[uint32[]](0xA0,0xFF))
$a=@('Calibri','Arial','Cambria','Verdana','Tahoma','Times New Roman','Courier New','Segoe UI','Microsoft Sans Serif')
$it=@('Calibri','Arial','Times New Roman')
# regular+bold for all, italic (and bold italic) added for three faces
[Adv]::Run((Join-Path $Out 'adv-latin.tsv'),[string[]]$a,$sizes,[int[]](0,1),[uint32[][]]$latin)
[Adv]::Run((Join-Path $Out 'adv-latin-italic.tsv'),[string[]]$it,$sizes,[int[]](2,3),[uint32[][]]$latin)
$cjk=@('SimSun','MS Gothic','MS PGothic','Microsoft YaHei','Malgun Gothic','PMingLiU')
$cr=@([uint32[]](0x20,0x7E),[uint32[]](0x4E2D,0x4E2D),[uint32[]](0x3042,0x3042),[uint32[]](0xFF21,0xFF21))
[Adv]::Run((Join-Path $Out 'adv-cjk.tsv'),[string[]]$cjk,$sizes,[int[]](0),[uint32[][]]$cr)
