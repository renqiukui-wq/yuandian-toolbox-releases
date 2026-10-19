using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Text;

static class SilenceProcessor {
    internal sealed class Range { public double start,end;public Range(double a,double b){start=a;end=b;} }
    static string N(double value){return value.ToString("0.######",CultureInfo.InvariantCulture);}
    internal static List<Range> Parse(string log,double duration,double padding) {
        var raw=new List<Range>();double? start=null;
        foreach(Match match in Regex.Matches(log,@"silence_(start|end):\s*(-?\d+(?:\.\d+)?)")) {
            double value=Double.Parse(match.Groups[2].Value,CultureInfo.InvariantCulture);
            if(match.Groups[1].Value=="start")start=value;
            else if(start.HasValue){raw.Add(new Range(start.Value,value));start=null;}
        }
        if(start.HasValue)raw.Add(new Range(start.Value,duration));
        return Normalize(raw,duration,padding);
    }
    internal static List<Range> Normalize(List<Range> raw,double duration,double padding) {
        if(duration<=0||Double.IsNaN(duration)||Double.IsInfinity(duration))throw new Exception("无法读取有效时长");
        raw.Sort((a,b)=>a.start.CompareTo(b.start));var result=new List<Range>();
        foreach(var r in raw){double a=Math.Max(0,r.start)+padding,b=Math.Min(duration,r.end)-padding;if(b-a<.05)continue;
            if(result.Count>0&&a<=result[result.Count-1].end)result[result.Count-1].end=Math.Max(result[result.Count-1].end,b);else result.Add(new Range(a,b));}
        double removed=0;foreach(var r in result)removed+=r.end-r.start;
        if(removed/duration>=.8||duration-removed<.2)throw new Exception("静音判定异常：将删除 80% 以上或几乎全部内容。已停止处理，请降低判定强度或检查音轨。");
        if(result.Count>500)throw new Exception("静音段超过 500 段，请分批处理或增大最短静音时长。");return result;
    }
    internal static List<Range> Keep(List<Range> cuts,double duration){var keep=new List<Range>();double cursor=0;foreach(var c in cuts){if(c.start>cursor)keep.Add(new Range(cursor,c.start));cursor=c.end;}if(cursor<duration)keep.Add(new Range(cursor,duration));return keep;}
    internal static double Duration(List<Range> keep){double value=0;foreach(var r in keep)value+=r.end-r.start;return value;}
    internal static string Filter(List<Range> keep,string scale,bool audio){
        var graph=new StringBuilder();var join=new StringBuilder();
        for(int i=0;i<keep.Count;i++){var r=keep[i];graph.Append("[0:v:0]trim=start="+N(r.start)+":end="+N(r.end)+",setpts=PTS-STARTPTS[v"+i+"];" );if(audio)graph.Append("[0:a:0]atrim=start="+N(r.start)+":end="+N(r.end)+",asetpts=PTS-STARTPTS[a"+i+"];" );join.Append("[v"+i+"]");if(audio)join.Append("[a"+i+"]");}
        graph.Append(join.ToString()+"concat=n="+keep.Count+":v=1:a="+(audio?"1":"0")+"[joined]"+(audio?"[audio]":"")+";[joined]"+scale+"[base]");return graph.ToString();
    }
}
