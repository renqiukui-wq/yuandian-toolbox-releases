const XYBreath={busy:false,
 noise(value){const n=Number(value);return Number.isFinite(n)&&n>=-60&&n<=-20?n:-40;},
 duration(value){const n=Number(value);return Number.isFinite(n)?Math.max(.2,Math.min(5,n)):.5;},
 ranges(items,duration){if(!Number.isFinite(duration)||duration<=0)throw Error("无法读取草稿时长，请重新保存草稿后刷新。");const ranges=[];for(const item of [...(items||[])].sort((a,b)=>a.start-b.start)){const a=Math.max(0,Number(item.start)),b=Math.min(duration,Number(item.end));if(!Number.isFinite(a)||!Number.isFinite(b)||b<=a)continue;const last=ranges.at(-1);if(last&&a<=last.end)last.end=Math.max(last.end,b);else ranges.push({start:a,end:b});}return ranges;},
 validate(items,duration){const ranges=this.ranges(items,duration),removed=ranges.reduce((sum,x)=>sum+x.end-x.start,0);if(removed/duration>=.8||duration-removed<.2)throw Error("检测将删除 80% 以上或几乎全部内容，已停止。请降低判定强度并重新检测，不要直接确认删除。");return {ranges,removed,ratio:removed/duration};},
 async quick(params,inspect,segments,run,notify){try{this.validate(segments,Number(inspect.durationSec));await run();}catch(e){notify("error",String(e.message||e));}},
};
const XYBreath_quick={props:["h","createVNode","actions"],render(){return XYBreath_quickBody(this.h,this.createVNode,this.actions)}};
function XYBreath_toolbar(h,createVNode,actions){return createVNode(XYBreath_quick,{h,createVNode,actions},null,16)}
function XYBreath_quickBody(h,createVNode,actions){return h("section",{class:"xy-export-panel"},[
 h("h2",{class:"xy-panel-title"},"删气口 · 快捷处理"),
 h("p",{class:"xy-mode-note"},"先在剪映保存，选择下方草稿。生成无气口副本时自动拼接保留片段；原草稿不覆盖。当前版本不能直接改写剪映内正在打开的时间线。"),
 h("div",{class:"xy-button-row"},[
 h("button",{class:"xy-btn",disabled:actions.busy,onClick:()=>actions.preset(-45,.6)},"保守 · 少删"),h("button",{class:"xy-btn",disabled:actions.busy,onClick:()=>actions.preset(-40,.5)},"均衡 · 推荐"),h("button",{class:"xy-btn",disabled:actions.busy||!actions.selected,onClick:actions.refresh},"重新读取并检测"),
 h("button",{class:"xy-btn primary",disabled:actions.busy||!actions.ready,onClick:actions.draft},"生成无气口草稿并排齐")]),
 h("p",{class:"xy-mode-note"},"强度越高，删除越多。新强度范围对应 -60 至 -20 dB；异常删除比例会被拦截。高级分段、字幕规则仍保留在下方。"),
 createVNode(XYBreath_batch,{h})]);}
const XYBreath_batch={props:["h"],data(){return{open:false,loading:false,items:[],selected:[],query:"",busy:false,stop:false,mode:"draft",folder:"",noise:-40,min:.5,message:"",results:[],done:[],progress:""}},methods:{
 async load(){this.open=!this.open;if(!this.open||this.busy)return;this.loading=true;try{this.items=await window.go.main.App.GetDraftList(false)||[];}catch(e){this.message=String(e)}finally{this.loading=false}},
 async folderPick(){const folder=await window.go.main.App.GetDialogDirectoryPath();if(folder){this.folder=folder;this.done=[]}},
 async start(){if(this.busy||XYBreath.busy||XYLocal_job){this.message="已有处理任务，请完成后再开始。";return}if(!this.selected.length){this.message="请先选择草稿";return}if(this.mode==="export"&&!this.folder){this.message="请先选择输出文件夹";return}this.busy=true;XYBreath.busy=true;this.stop=false;this.message="";const mode=this.mode,folder=this.folder,noise=XYBreath.noise(this.noise),min=XYBreath.duration(this.min),pending=this.items.filter(d=>this.selected.includes(d.draftFolder)&&!this.done.includes(d.draftFolder));this.results=[];
 try{for(let i=0;i<pending.length;i++){if(this.stop)break;const draft=pending[i],path=draft.draftFolder;this.progress=(i+1)+"/"+pending.length+" · "+draft.draftName;try{
 const info=await window.go.main.App.InspectRemoveBreathDraft(path);if(this.stop)break;if(!info.hasAudioTrack&&!info.hasVideoWithAudio)throw Error("没有可用于检测的音轨");
 const segments=await window.go.main.App.DetectBreath(JSON.stringify({draftPath:path,silence:true,subtitle:false,noiseDb:noise,minDuration:min}));if(this.stop)break;
 const checked=XYBreath.validate(segments,Number(info.durationSec));if(!checked.ranges.length){this.results.push({name:draft.draftName,state:"跳过：没有需要删除的静音"});this.done.push(path);continue;}
 const result=await window.go.main.App.RemoveBreath(JSON.stringify({draftPath:path,draftName:draft.draftName,outputMode:mode,exportType:"video",destDir:folder,deleteSegments:checked.ranges,chooseSpeed:"accurate",exportMethod:"merged",groups:[],mergeAdjacentSubtitles:false,detectMode:"silence",_fps:"default",_bitrate:"default",_resolution:"",tailor_bitrate:""}));
 if(!result||!result.items?.length||result.status==="failed"||Number(result.failedCount)>0)throw Error((result?.items||[]).filter(x=>x.status==="failed").map(x=>x.error).join("；")||"后台未确认处理成功");
 this.done.push(path);this.results.push({name:draft.draftName,state:"完成 · 删除 "+checked.removed.toFixed(1)+" 秒",files:(result.items||[]).map(x=>x.outputFilePath).filter(Boolean).join("；")});
 }catch(e){this.results.push({name:draft.draftName,state:"失败："+String(e.message||e)})}}
 this.message=this.stop?"已停止排队；当前完成结果保留。":"批量处理结束；已完成和无需删除项不会重复执行。";
 }finally{this.busy=false;XYBreath.busy=false;this.progress=""}},
 },render(){const h=this.h,visible=this.items.filter(d=>!this.query||String(d.draftName).includes(this.query));return h("div",{class:"xy-breath-batch"},[
 h("button",{class:"xy-btn",disabled:this.busy,onClick:this.load},this.open?"收起批量草稿处理":"批量删气口 / 批量导出"),this.open?h("div",{style:{marginTop:"16px"}},[
 h("p",{class:"xy-mode-note"},"这里逐个处理所选草稿已保存的主时间线。多时间线请使用“多时间线导出 → 导出后删除静音”。"),
 h("input",{class:"xy-breath-search",placeholder:"搜索草稿",value:this.query,disabled:this.busy,onInput:e=>this.query=e.target.value}),
 h("div",{class:"xy-breath-drafts"},visible.map(d=>h("label",{class:"xy-check-label"},[h("input",{type:"checkbox",checked:this.selected.includes(d.draftFolder),disabled:this.busy,onChange:e=>{this.selected=e.target.checked?[...this.selected,d.draftFolder]:this.selected.filter(p=>p!==d.draftFolder)}}),d.draftName]))),
 this.loading?h("p",null,"正在读取草稿…"):null,
 h("div",{class:"xy-button-row",style:{marginTop:"12px"}},[h("select",{"aria-label":"批量输出方式",disabled:this.busy,value:this.mode,onChange:e=>{this.mode=e.target.value;this.done=[]}},[h("option",{value:"draft"},"生成无气口草稿"),h("option",{value:"export"},"导出无气口视频")]),h("select",{"aria-label":"静音检测预设",disabled:this.busy,value:this.noise,onChange:e=>{this.noise=Number(e.target.value);this.done=[]}},[h("option",{value:-45},"保守 -45 dB"),h("option",{value:-40},"均衡 -40 dB")]),this.mode==="export"?h("button",{class:"xy-btn",disabled:this.busy,onClick:this.folderPick},this.folder||"选择输出文件夹"):null,h("button",{class:"xy-btn primary",disabled:this.busy||!this.selected.length,onClick:this.start},"开始 / 重试未完成项"),this.busy?h("button",{class:"xy-btn",onClick:()=>{this.stop=true;this.message="当前草稿完成后停止，不再开始下一项。"}},"完成当前项后停止"):null]),
 h("p",{role:"status"},this.progress||this.message),h("div",{class:"xy-breath-results"},this.results.map(r=>h("p",null,[h("strong",null,r.name+"："),r.state,r.files?h("small",{style:{display:"block",overflowWrap:"anywhere"}},r.files):null])))
 ]):null]);}};
