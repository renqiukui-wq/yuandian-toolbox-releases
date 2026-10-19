const fs=require('fs'),acorn=require('./acorn/acorn.js');
const source=fs.readFileSync('work/extracted/frontend__dist__assets__index.42d30f6e.js','utf8');
const ast=acorn.parse(source,{ecmaVersion:'latest',sourceType:'module'});
const patches=[],components={},functions=[],variables=[],calls=[],guards=new Map(),caps=new Map(),singleDraft=[];
function visit(n,parents=[]){
 if(!n||typeof n!=='object')return;
 if(n.type==='ObjectExpression'){
  const name=n.properties.find(p=>p.key?.name==='__name')?.value?.value;
  if(name)components[name]=n;
 }
 if(n.type==='FunctionDeclaration')functions.push(n);
 if(n.type==='VariableDeclarator')variables.push(n);
 if(n.type==='CallExpression')calls.push(n);
 if(n.type==='Literal'&&n.value==='多时间线导出仅支持选择一个草稿')singleDraft.push(parents.findLast(p=>p.type==='IfStatement'));
 if(n.type==='Literal'&&typeof n.value==='string'&&/授权已到期/.test(n.value)){
  const f=parents.findLast(p=>p.type==='FunctionDeclaration');
  if(f&&f.end-f.start<1500)guards.set(f.start,f);
 }
 if(n.type==='IfStatement'&&/Activated/.test(source.slice(n.test.start,n.test.end))){
  const code=source.slice(n.start,n.end);
  const human=code.replace(/\\u([0-9a-f]{4})/gi,(_,x)=>String.fromCharCode(parseInt(x,16)));
  if(/试用.*(数量|片段|轨道|生成)/.test(human)&&!n.alternate)caps.set(n.start,n);
 }
 for(const v of Object.values(n))if(Array.isArray(v))v.forEach(x=>x?.type&&visit(x,[...parents,n]));else if(v?.type)visit(v,[...parents,n]);
}
visit(ast);
function removeAboutMenu(n){if(!n||typeof n!=="object")return;if(n.type==="ArrayExpression"){for(const item of n.elements){if(item?.type==="ObjectExpression"&&item.properties.some(p=>p.key?.name==="id"&&p.value?.value===10)&&item.properties.some(p=>p.key?.name==="label"&&p.value?.value==="7.激活软件")){add(item.start-1,item.end,"","remove about menu entry");}}}for(const v of Object.values(n))if(Array.isArray(v))v.forEach(removeAboutMenu);else if(v?.type)removeAboutMenu(v);}
removeAboutMenu(ast);
function add(start,end,text,reason){patches.push({start,end,text,reason});}
for(const f of guards.values())add(f.body.start,f.body.end,'{return true;}','remove module trial/expiry guard');
for(const n of caps.values())if(![...guards.values()].some(f=>f.start<=n.start&&f.end>=n.end))add(n.start,n.end,'','remove trial count restriction');
for(const n of singleDraft)add(n.start,n.end,'','remove single-draft export limit');
function wrap(name,body){const f=functions.find(n=>n.id.name===name);if(!f)throw Error('Missing '+name);add(f.body.start,f.body.end,'{'+body+'}','replace '+name);}
wrap('$l','return window.go.main.App.GetDraftList(e).then(value=>{setTimeout(XYPreview_refresh,0);return value;});');
wrap('Qc','return Promise.resolve(XYLocal_status());');
wrap('na','return Promise.resolve(XYLocal_status());');
wrap('la','return Promise.resolve({name:"本地功能",details:"本地版：全部功能开放，批量数量不受试用限制。",link:""});');
wrap('CA','return XYLocal_start("BatchExportDraft",e);');
wrap('EA','return XYLocal_start("BatchExportMultiTimeline",e);');
wrap('Hf','return XYLocal_progress();');
wrap('dB','if(XYBreath.busy||XYLocal_job)return Promise.reject(new Error("已有处理任务，请等待完成。"));XYBreath.busy=true;return window.go.main.App.RemoveBreath(e).finally(()=>{XYBreath.busy=false});');
wrap('gA','return Promise.reject(new Error("用户反馈功能已移除。"));');
const advice=components.AdvicePage;
add(advice.start,advice.end,'{__name:"AdvicePage",setup(){return()=>o(XYUpdate_component,{h:l});}}','replace feedback form with update page');
// Keep a patched binary from offering an in-place replacement with the paid build.
wrap('zD','return Promise.resolve({version:"3.5.5",is_forced:0,brief:"",desc:"",bravover:"",bravo_map:{}});');
const active=components.ActivePage;
add(active.start,active.end,'{__name:"ActivePage",setup(){return()=>null;}}',"remove about page content");
for(const call of calls){
 if(call.arguments[1]?.type==="ObjectExpression"&&call.arguments[1].properties.some(p=>p.key?.name==="class"&&p.value?.value==="draftCart")){const card=source.slice(call.start,call.end),item=card.match(/content:([A-Za-z_$][\w$]*)\.draftName/)[1];const children=call.arguments[2];add(children.start+1,children.start+1,"XYPreview_card("+item+",l,o),","render preview for every draft picker");}

 const props=call.arguments[1];

 if(call.start>components.ExportMultiTimeline.start&&call.end<components.ExportMultiTimeline.end&&props?.type==='ObjectExpression'&&props.properties.some(p=>p.key?.name==='label'&&p.value.value==='插入封面：')){
  let cover=source.slice(call.start,call.end).replace(/label:"[^"]*"/, 'label:"视频封面："');
  cover=cover.replace('S("\\u5426",-1)','S("默认首帧",-1)');
  cover=cover.replace('o($e,{value:"yes"}', 'o($e,{value:"random"},{default:i(()=>[S("随机画面帧")]),_:1}),o($e,{value:"yes"}');
  add(call.start,call.end,'l("div",{class:"xy-cover-field"},['+cover+',l("p",{class:"xy-cover-note"},"默认沿用视频首帧；随机模式为每条视频抽取画面，写入首帧并内嵌封面，不另存图片。")])','add random frame cover policy');
 }
 if(call.callee.name==='l'&&props?.type==='ObjectExpression'&&props.properties.some(p=>p.key.name==='class'&&p.value.value==='funcDesc')){
  add(call.start,call.end,'H("",!0)','remove demo banner');
  const owner=Object.entries(components).find(([name,c])=>call.start>c.start&&call.end<c.end);
  if(owner)add(call.start,call.start,'XYDesign_heading('+JSON.stringify(owner[0])+',l),','add contextual page heading');
 }
 if(call.callee.name==='l'&&props?.type==='Identifier'&&props.name==='E_e')add(call.start,call.end,'XYDesign_brand(l,o,x.value.currVersion)','replace header with studio controls');
 if(['ExportDraft','ExportMultiTimeline'].some(name=>call.start>components[name].start&&call.end<components[name].end)&&props?.type==='ObjectExpression'&&props.properties.some(p=>p.key.name==='label'&&p.value.value==='命名视频：'))add(call.start,call.end,'l("div",{style:{padding:"5px 10px",color:"#909399",fontSize:"12px"}},"导出文件名：使用时间线名称")','use timeline names without custom prefix');
 if(['ExportDraft','ExportMultiTimeline'].some(name=>call.start>components[name].start&&call.end<components[name].end)&&props?.type==='ObjectExpression'&&props.properties.some(p=>p.key.name==='label'&&p.value.value==='上传网盘：'))add(call.start,call.end,'H("",!0)','hide unavailable cloud upload placeholder');
 if(['ExportDraft','ExportMultiTimeline'].some(name=>call.start>components[name].start&&call.end<components[name].end)&&props?.type==='ObjectExpression'&&props.properties.some(p=>p.key.name==='class'&&p.value.value==='draftCart')){
  const item=call.start>components.ExportMultiTimeline.start?'me':'L';
  let text=source.slice(props.start,props.end).replace('class:"draftCart"','class:be(["draftCart",{"xy-selected":'+item+'.isChecked}])');
  text=text.slice(0,-1)+',role:"button",tabindex:0,"aria-label":String('+item+'.draftName||"草稿"),"aria-pressed":!!'+item+'.isChecked,onKeydown:XYDesign_cardKey}';
  add(props.start,props.end,text,'add visible selection and keyboard control to draft cards');
  if(call.arguments[3])add(call.arguments[3].start,call.arguments[3].end,'16','refresh all card accessibility and selection props');
 }
 if(props?.type==='ObjectExpression'&&props.properties.some(p=>p.key?.name==='content'&&p.value.type==='MemberExpression'&&p.value.property?.name==='draftName'))add(props.end-1,props.end-1,',showAfter:450,hideAfter:0','delay draft name tooltips until deliberate hover');
}
function relabel(n){
 if(!n||typeof n!=='object')return;
 const labels={"多个搜索关键词用 * 号分隔":"搜索草稿，关键词用 * 分隔","1.实用功能(免费)":"视频工具","2.剪映批量混剪":"批量混剪","3.剪映批量导出":"批量导出","4.剪映批量添加":"批量添加","5.素材批量处理":"素材处理","6.需求收集&意见反馈":"检查更新","7.激活软件":"关于本地版","激活软件":"关于本地版","正式版(":"本地版(","仅支持单一多时间线草稿":"支持多草稿、多时间线批量导出","请先选择上方草稿↑↑↑":"选择一个草稿，继续配置处理规则"," 请先选择上方草稿↑↑↑ ":"选择一个草稿，继续配置处理规则"};
 if(n.type==='Literal'&&Object.hasOwn(labels,n.value)&&!patches.some(p=>p.start<=n.start&&p.end>=n.end))add(n.start,n.end,JSON.stringify(labels[n.value]),'relabel local edition');
 for(const v of Object.values(n))if(Array.isArray(v))v.forEach(relabel);else if(v?.type)relabel(v);
}
relabel(ast);
for(const name of ['ExportDraft','ExportMultiTimeline']){
 const c=components[name];const part=source.slice(c.start,c.end);
 const marker='fps:"30fps"';const pos=part.indexOf(marker);if(pos<0)throw Error('No settings '+name);
 add(c.start+pos+marker.length,c.start+pos+marker.length,',sizeMode:XYLocal_sizeMode(localStorage.getItem("xy-size-mode")),removeSilence:localStorage.getItem("xy-remove-silence")==="true",collectMaterials:localStorage.getItem("xy-copy-materials")==="true",collectBusy:false,collectMessage:""','persist size and material settings '+name);
 const render=name==='ExportDraft'?'o(et,null,{default:i(()=>[':'o(Tt,null,{default:i(()=>[';
 const rp=part.indexOf(render);if(rp<0)throw Error('No render '+name);
 add(c.start+rp+render.length,c.start+rp+render.length,'XYLocal_control(d.value,l,o),','render size '+name);
 if(name==='ExportMultiTimeline'){
  const toggle=functions.find(f=>f.start>c.start&&f.end<c.end&&f.id.name==='ee');
  add(toggle.body.start,toggle.body.end,'{oe.isChecked=!oe.isChecked;d.value.selectedDrafts=c.value.draftList.filter(x=>x.isChecked).map(x=>x.draftFolder);}','allow multiple timeline drafts');
  const update=variables.find(v=>v.start>c.start&&v.end<c.end&&v.id.name==='V');
  add(update.init.body.start,update.init.body.end,'{const ke=await Ee(oe||[]);c.value.draftList=ke;d.value.selectedDrafts=ke.filter(x=>x.isChecked).map(x=>x.draftFolder);ae(c.value.searchDraft);}','preserve all selected timeline drafts');
  const all=part.indexOf('showSelectAll:!1');
  add(c.start+all,c.start+all+'showSelectAll:!1'.length,'showSelectAll:!0','enable timeline draft select all');
  const load=functions.find(f=>f.start>c.start&&f.end<c.end&&f.id.name==='Ce');
  let loadBody=source.slice(load.body.start,load.body.end);
  loadBody='{const xyLoad=(c.value.xyLoad=(c.value.xyLoad||0)+1);'+loadBody.slice(1);
  loadBody=loadBody.replace('const oe=d.value.selectedDrafts','const oe=[...d.value.selectedDrafts]')
   .replace('if(oe.length===0){f.value=[];return}', 'if(oe.length===0){f.value=[];y.value=false;d.value.timelineLoading=false;return}')
   .replace('y.value=!0;','y.value=!0;d.value.timelineLoading=true;')
   .replace('(await R0(je)||[])','(await XYDesign_timeline(je)||[])')
   .replace('ke.push({draftPath:je','if(xyLoad!==c.value.xyLoad)return;ke.push({draftPath:je')
   .replace('f.value=ke','xyLoad===c.value.xyLoad&&(f.value=ke)')
   .replace('catch(ke){f.value=[],xe(', 'catch(ke){if(xyLoad===c.value.xyLoad){f.value=[],xe(')
   .replace(')}finally{y.value=!1}',')}}finally{if(xyLoad===c.value.xyLoad){y.value=false;d.value.timelineLoading=false}}');
  // Only the latest selection's asynchronous read may replace the timeline groups.
  add(load.body.start,load.body.end,loadBody,'prevent stale timeline selection responses');
  const start=variables.find(v=>v.start>c.start&&v.end<c.end&&v.id.name==='Q');
  add(start.init.body.start+1,start.init.body.start+1,'if(y.value){Ie.warning("正在读取时间线，请稍后开始导出");return;}','wait for timeline enumeration');
 }
}

// Keep the original backend but repair unsafe thresholds and stale detection state.
const breath=components.RemoveBreath;
function breathFunction(name,transform){const fn=functions.find(f=>f.start>breath.start&&f.end<breath.end&&f.id.name===name);if(!fn)throw Error('Missing breath function '+name);add(fn.body.start,fn.body.end,transform(source.slice(fn.body.start,fn.body.end)),'breath '+name);}
breathFunction('f',s=>s.replace('noiseDb:y(qe==null?void 0:qe.noiseDb,-40)','noiseDb:XYBreath.noise(qe==null?void 0:qe.noiseDb)').replace('minDuration:y(qe==null?void 0:qe.minDuration,.5)','minDuration:XYBreath.duration(qe==null?void 0:qe.minDuration)'));
breathFunction('v',()=>'{return -60+Math.max(0,Math.min(100,Number(qe)||0))*.4}');
breathFunction('D',()=>'{return (XYBreath.noise(qe)+60)/.4}');
breathFunction('La',()=>'{if(Wu.value||XYBreath.busy){Eu("warning","请等待当前处理完成");return;}const path=qe.draftFolder;Ne.value.refDraftPath=path;Ne.value.draftName=qe.draftName;c.value.selectArea=false;$.value=[];A.value=[];_.value=[];V.value=[];te.value=[];De.clear();pa.value="";$t.value=E();Pl();Ml(false);ga(path).then(async()=>{if(Ne.value.refDraftPath!==path)return;c.value.selectArea=true;await Ya(true);await Xa()}).catch(e=>Eu("error","草稿读取失败："+e));}');
breathFunction('Re',s=>'{try{XYBreath.validate([...$.value,...V.value],Number($t.value.durationSec));}catch(e){Eu("error",e.message);return;}'+s.slice(1).replace('Cu=await dB(JSON.stringify(Bu));','Cu=await dB(JSON.stringify(Bu));if(!Cu||Cu.status==="failed"||!Cu.items?.length||(Pe.value==="draft"&&Number(Cu.failedCount)>0))throw Error("后台未确认处理成功，请查看素材是否缺失后重试。");'));
breathFunction('Xa',s=>{
 s='{if(ma.value){c.value.xyDetectAgain=true;return;}const xyPath=Ne.value.refDraftPath,xyRules=JSON.stringify([d.value,h.value]);'+s.slice(1);
 s=s.replace('$.value=Bu','if(xyPath!==Ne.value.refDraftPath||xyRules!==JSON.stringify([d.value,h.value])){c.value.xyDetectAgain=true;return;}$.value=Bu');
 s=s.replace(',if(xyPath',';if(xyPath');
 s=s.replace('finally{ma.value=!1}','finally{ma.value=false;if(c.value.xyDetectAgain){c.value.xyDetectAgain=false;Xa()}}');return s;
});
breathFunction('ga',s=>s.replace('const ht=await ID(qe);','const ht=await ID(qe);if(qe!==Ne.value.refDraftPath)return;'));
breathFunction('Ya',s=>s.replace('const Be=qa();','const Be=qa();').replace('Le.value=Zt.points','if(Be!==qa())return;Le.value=Zt.points'));
const breathPart=source.slice(breath.start,breath.end),breathRender='o(ln,{expand2fold:c.value.expand2fold';
const breathPos=breathPart.indexOf(breathRender);if(breathPos<0)throw Error('Missing breath render');
add(breath.start+breathPos,breath.start+breathPos,'XYBreath_toolbar(l,o,{busy:Wu.value||ma.value,selected:!!Ne.value.refDraftPath,ready:c.value.selectArea&&$.value.length>0,preset:(noise,min)=>{h.value={...h.value,noiseDb:noise,minDuration:min}},refresh:async()=>{De.clear();await ga(Ne.value.refDraftPath);await Ya(true);await Xa()},draft:async()=>{Pe.value="draft";Ne.value.exportMethod="merged";await Re()}}),','add quick and batch breath controls');

patches.sort((a,b)=>a.start-b.start||a.end-b.end);
for(let i=1;i<patches.length;i++)if(patches[i].start<patches[i-1].end)throw Error('Overlapping patches '+JSON.stringify(patches.slice(i-1,i+1)));
let out=source;for(const p of [...patches].reverse())out=out.slice(0,p.start)+p.text+out.slice(p.end);
out=out.replace("le.id===80||le.id===88||le.id===89?","le.id===80||le.id===88?");
out=out.replace("if(ue.children&&ue.children.length>0){const Ee=N.value;if(Ee&&(Ee.store.toggleExpansion(ue),ue.id===1&&Ee.store.nodesMap[18])){const _e=Ee.store.nodesMap[18];_e.expanded||Ee.store.toggleExpansion(_e)}return}",'if(ue.children&&ue.children.length>0)return;');
out=out.replace('H_e.classList.add("dark")','H_e.classList.toggle("dark",localStorage.getItem("xy-ui-theme")!=="light")');
const theme=fs.readFileSync('work/studio_theme.css','utf8').replace(/\/\*[\s\S]*?\*\//g,'').replace(/\s+/g,' ').trim();
const inject='const XYDesign_style=document.createElement("style");XYDesign_style.id="xy-studio-theme";XYDesign_style.textContent='+JSON.stringify(theme)+';document.head.appendChild(XYDesign_style);\n';
const release=JSON.parse(fs.readFileSync('work/release_config.json','utf8'));
if(!/^\d+\.\d+\.\d+$/.test(release.version))throw Error('Invalid release version');
out='const XYRelease='+JSON.stringify({version:release.version})+';\n'+fs.readFileSync('work/update_ui.js','utf8')+'\n'+inject+fs.readFileSync('work/studio_design.js','utf8')+'\n'+fs.readFileSync('work/local_runtime.js','utf8')+'\n'+fs.readFileSync('work/breath_tools.js','utf8')+'\n'+fs.readFileSync('work/draft_preview.js','utf8')+'\n'+out;

// Re-encode string literals without redundant Unicode escapes; preserve values via the parser.
const packedAst=acorn.parse(out,{ecmaVersion:'latest',sourceType:'module'}),strings=[];
function collectStrings(n){if(!n||typeof n!=='object')return;if(n.type==='Literal'&&typeof n.value==='string'){const text=JSON.stringify(n.value);if(Buffer.byteLength(text)<Buffer.byteLength(out.slice(n.start,n.end)))strings.push({start:n.start,end:n.end,text});}for(const v of Object.values(n))if(Array.isArray(v))v.forEach(collectStrings);else if(v?.type)collectStrings(v);}
collectStrings(packedAst);
const literalEdits=new Map(strings.map(p=>[p.start,p]));let inlineThemeCount=0;
function normalizeInline(n,inStyle=false){if(!n||typeof n!=='object')return;const key=n.type==='Property'?(n.key.name||n.key.value):'';const nextStyle=inStyle||key==='style';if(inStyle&&['color','background','backgroundColor','background-color','borderColor','border-color'].includes(key)&&n.value?.type==='Literal'&&typeof n.value.value==='string'){const value=n.value.value.trim().toLowerCase();let hex=value==='white'?'ffffff':value==='black'?'000000':value.replace(/^#/,'');if(/^[0-9a-f]{3}$/.test(hex))hex=hex.split('').map(c=>c+c).join('');if(/^[0-9a-f]{6}$/.test(hex)){const rgb=[0,2,4].map(i=>parseInt(hex.slice(i,i+2),16));if(Math.max(...rgb)-Math.min(...rgb)<40||key==='color'){const textToken=Math.max(...rgb)-Math.min(...rgb)<40?(rgb[0]>50&&rgb[0]<195?'muted':'text'):rgb[0]>rgb[1]*1.35&&rgb[0]>rgb[2]*1.3?(rgb[1]>rgb[0]*.42?'warning':'danger'):'accent';const token=key==='color'?textToken:key.toLowerCase().includes('border')?'border':'surface';literalEdits.set(n.value.start,{start:n.value.start,end:n.value.end,text:JSON.stringify('var(--xy-'+token+')')});inlineThemeCount++;}}}for(const v of Object.values(n))if(Array.isArray(v))v.forEach(x=>normalizeInline(x,nextStyle));else if(v?.type)normalizeInline(v,nextStyle);}
normalizeInline(packedAst);

for(const p of [...literalEdits.values()].sort((a,b)=>b.start-a.start))out=out.slice(0,p.start)+p.text+out.slice(p.end);

acorn.parse(out,{ecmaVersion:'latest',sourceType:'module'});
fs.writeFileSync('work/patched_frontend.js',out);
fs.writeFileSync('work/frontend_patch_manifest.json',JSON.stringify(patches.map(({text,...p})=>p),null,2));
console.log(JSON.stringify({patches:patches.length,licenseGuards:guards.size,trialCountBranches:[...caps.values()].filter(n=>![...guards.values()].some(f=>f.start<=n.start&&f.end>=n.end)).length,oldBytes:Buffer.byteLength(source),newBytes:Buffer.byteLength(out)}));

