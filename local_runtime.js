const XYLocal_token="xy-local-20261015-fd32b7ca938c4e0ea704";
let XYLocal_job=null;
function XYLocal_status(){
 const s={id:1,new_sn:"本地版",active_code:"",is_activated:"1",enable_days:365000,trial_times:0,module_ids:JSON.stringify([1,2,3,4,5,6,10,100])};
 const names={1:"批量导出",2:"关键帧与批量添加",3:"音字同步",4:"批量混剪",5:"实用功能",6:"素材批量处理",10:"草稿处理",100:"全部功能"};
 for(const id of [1,2,3,4,5,6,10,100])Object.assign(s,{["m"+id+"_activated"]:1,["m"+id+"_enable_days"]:365000,["m"+id+"_trial_times"]:0,["m"+id+"_module_name"]:names[id],["m"+id+"_month_price"]:0,["m"+id+"_season_price"]:0,["m"+id+"_year_price"]:0});
 return s;
}
async function XYLocal_api(action,data={}){
 let r;
 try{const resp=await fetch("http://127.0.0.1:48740/"+action,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({token:XYLocal_token,...data})});r=await resp.json();}
 catch(e){throw Error("本地处理服务尚未连接。请关闭程序后重新打开元点剪辑批量工具箱.exe。");}
 if(r.error)throw Error(r.error);return r;
}
const XYLocal_ControlComponent={props:["params","h"],data(){return{pending:false}},mounted(){this.pending=XYDesign_startPending;this._pendingListener=e=>{this.pending=e.detail};window.addEventListener("xy-export-pending",this._pendingListener)},beforeUnmount(){window.removeEventListener("xy-export-pending",this._pendingListener)},render(){return XYLocal_controlBody(this.params,this.h,this.pending)}};
function XYLocal_control(params,l,createVNode){return createVNode(XYLocal_ControlComponent,{params,h:l});}
function XYLocal_controlBody(params,h,pending){
 const count=params.selectedDrafts?.length||0,busy=!!params.collectBusy||!!params.timelineLoading||pending,mode=params.sizeMode||"original";
 const options=[["original","保持原尺寸","沿用草稿设置"],["auto720","自动 720P · 推荐","逐条跟随横竖方向"],["landscape","720P 横屏 1280×720","横向画面 · 16:9"],["portrait","720P 竖屏 720×1280","竖向画面 · 9:16"]];
 const message=params.timelineLoading?"正在读取所选草稿的时间线…":params.collectMessage||(count?"已选 "+count+" 个草稿，文件名沿用对应时间线。":"先选择要处理的草稿，再设置输出方式。");
 return h("section",{class:"xy-export-panel","aria-label":"导出设置"},[
  h("div",{class:"xy-panel-top"},[h("div",null,[h("h2",{class:"xy-panel-title"},"导出设置"),h("p",{class:"xy-panel-subtitle"},"混合横竖时间线，选自动；统一交付规格，选固定横屏或竖屏。")]),h("span",{class:"xy-count-badge"},count?"已选 "+count+" 个草稿":"等待选择草稿")]),
  h("div",{class:"xy-size-options",role:"radiogroup","aria-label":"导出尺寸"},options.map(([value,title,sub])=>h("button",{type:"button",role:"radio",class:"xy-size-option","aria-label":title,"aria-checked":mode===value,tabindex:mode===value?0:-1,disabled:busy,onClick:()=>{params.sizeMode=value;localStorage.setItem("xy-size-mode",value)},onKeydown:e=>{if(!["ArrowLeft","ArrowRight","ArrowUp","ArrowDown"].includes(e.key))return;e.preventDefault();const delta=["ArrowLeft","ArrowUp"].includes(e.key)?-1:1,next=options[(options.findIndex(x=>x[0]===mode)+delta+options.length)%options.length][0];params.sizeMode=next;localStorage.setItem("xy-size-mode",next);e.currentTarget.parentElement.querySelector('[aria-label="'+options.find(x=>x[0]===next)[1]+'"]').focus();}},[h("span",{class:"xy-size-icon "+value,"aria-hidden":"true"}),h("span",null,[h("strong",null,title),h("small",null,sub)])]))),
  h("div",{class:"xy-mode-note"},mode==="original"?(params.setCover==="random"?"保持每条视频原尺寸，生成随机首帧与内嵌封面。请先选择自定义保存路径。":"保留每条时间线导出后的原尺寸，不进行二次转码。"):mode==="auto720"?"按每个导出视频的画面比例分别处理：16:9 → 1280×720，9:16 → 720×1280；其他比例短边 720、等比缩放，不裁切、不补边。请先选择自定义保存路径；完成后只保留最终视频。":"固定为所选横屏或竖屏尺寸；方向不一致的视频会等比缩放并补黑边。请在下方选择自定义保存路径；完成后只保留最终视频。"),
  h("div",{class:"xy-material-row"},[h("label",{class:"xy-check-label"},[h("input",{type:"checkbox",checked:!!params.collectMaterials,disabled:busy,onChange:e=>{params.collectMaterials=e.target.checked;localStorage.setItem("xy-copy-materials",String(e.target.checked))}}),"导出前复制全部素材到草稿"]),h("div",{class:"xy-button-row"},[h("button",{type:"button",class:"xy-btn",disabled:busy||!count,onClick:()=>{XYLocal_collect(params).catch(()=>{})}},params.collectBusy?[h("span",{class:"xy-spinner","aria-hidden":"true"}),"正在复制素材"]:"立即复制所选草稿素材"),h("button",{type:"button",class:"xy-btn primary",disabled:busy||!count,onClick:XYDesign_startExport},pending?[h("span",{class:"xy-spinner","aria-hidden":"true"}),"正在准备"]:"开始导出")])]),
  h("div",{class:"xy-status "+(params.collectError?"error":params.collectMessage&&!params.collectBusy?"success":""),role:"status","aria-live":"polite"},[h("span",{class:params.collectBusy?"xy-spinner":"xy-status-dot","aria-hidden":"true"}),h("span",null,message)]),
  h("details",{class:"xy-material-help"},[h("summary",null,"素材整理与备份说明"),h("p",null,"复制前，请先在剪映中保存并关闭所选草稿。程序会整理所有时间线的外部素材，校验文件并保留原配置备份；遇到缺失素材会提示具体位置。")])
 ]);
}
async function XYLocal_collect(params){
 if(params.collectBusy)throw Error("素材复制正在进行中。");
 if(!params.selectedDrafts?.length){params.collectMessage="请先选择需要复制素材的草稿。";return false;}
 params.collectBusy=true;params.collectError=false;params.collectMessage="正在检查所选草稿的全部素材…";
 try{
  const task=await XYLocal_api("collect/start",{drafts:[...params.selectedDrafts]});
  while(true){const s=await XYLocal_api("collect/status",{id:task.id});params.collectMessage=s.message||"正在复制素材…";if(s.state==="completed")return true;if(s.state==="failed")throw Error(s.error||s.message);await new Promise(r=>setTimeout(r,500));}
 }catch(e){params.collectError=true;params.collectMessage=e.message;throw e;}finally{params.collectBusy=false;}
}
async function XYLocal_startCore(method,params){
 if(XYLocal_job)throw Error("上一次尺寸处理尚未完成，请等待后再启动。");
 if(params.collectBusy)throw Error("请等待素材复制完成后再导出。");
 if(params.collectMaterials)await XYLocal_collect(params);
 let outputNames=[];
 if(method==="BatchExportMultiTimeline"){
  const groups=await XYDesign_map(params.selections||[],async group=>{const timelines=await window.go.main.App.ListDraftTimelines(group.draftPath);return (timelines||[]).filter(t=>group.timelineIds.includes(t.id)).map(t=>String(t.name||"timeline").trim().replace(/[<>:"/\\|?*\x00-\x1f]/g,"_"));});const names=groups.flat();outputNames=names;
  const seen=new Set();for(const name of names){const k=name.toLowerCase();if(seen.has(k))throw Error("所选时间线名称重复：“"+name+"”。请先改为不同名称或分批导出，以免覆盖。");seen.add(k);}
  params={...params,nameVideo:"no",namePrefix:""};
 }else if(method==="BatchExportDraft"){
  const drafts=await window.go.main.App.GetDraftList(false),pairs=[],seen=new Set();
  const resolved=await XYDesign_map(params.selectedDrafts||[],async path=>({path,timelines:await window.go.main.App.ListDraftTimelines(path)}));
  for(const {path,timelines} of resolved){const draft=(drafts||[]).find(d=>d.draftFolder===path);const main=(timelines||[]).find(t=>t.isMain)||(timelines||[])[0];const name=String(main?.name||draft?.draftName||path.split(/[\\/]/).pop()).trim().replace(/[<>:"/\\|?*\x00-\x1f]/g,"_");if(seen.has(name.toLowerCase()))throw Error("所选草稿的当前时间线名称重复：“"+name+"”。请先改为不同名称或分批导出。");seen.add(name.toLowerCase());outputNames.push(name);pairs.push(String(draft?.draftName||path.split(/[\\/]/).pop())+"="+name);}
  params={...params,nameVideo:"yes",namePrefix:pairs.join(":")};
 }
 const mode=params.sizeMode||"original",coverMode=params.setCover==="random"?"random":"first";
 if(mode!=="original"||coverMode==="random"){
  if(!["original","auto720","landscape","portrait"].includes(mode))throw Error("请选择有效的导出尺寸。");
  if(!params.exportPath)throw Error("选择尺寸处理或随机封面时，请先选择自定义保存路径。");
  if(params.shutdown==="yes")throw Error("视频处理完成前不能自动关机，请关闭自动关机后导出。");
  XYLocal_job=await XYLocal_api("begin",{mode,coverMode,names:outputNames,folder:params.exportPath});
  params={...params,exportPath:XYLocal_job.folder,setCover:coverMode==="random"?"no":params.setCover};
 }
 try{const result=await window.go.main.App[method](params);if(result===false)throw Error("导出任务未启动，请检查草稿和导出设置。");return result}
 catch(e){if(XYLocal_job){await XYLocal_api("cancel",{id:XYLocal_job.id}).catch(()=>{});XYLocal_job=null}throw e}
}
async function XYLocal_progress(){
 const raw=await window.go.main.App.GetQtInspectorExportProgress();
 if(!XYLocal_job)return raw;
 if(["failed","cancelled"].includes(raw.phase)){await XYLocal_api("cancel",{id:XYLocal_job.id}).catch(()=>{});XYLocal_job=null;return raw;}
 if(raw.phase!=="completed")return raw;
 try{
  const state=await XYLocal_api("finish",{id:XYLocal_job.id});
  if(state.state==="completed"){XYLocal_job=null;return{...raw,message:"导出完成："+(state.outputFolder||state.folder)};}
  if(state.state==="failed"){XYLocal_job=null;return{...raw,running:false,phase:"failed",error:state.error,message:state.error};}
  return {...raw,running:true,phase:"正在生成最终视频",message:"正在生成最终视频",progress:0,completed:state.completed,total:state.total||raw.total};
 }catch(e){XYLocal_job=null;return {...raw,running:false,phase:"failed",error:e.message,message:e.message};}
}
