// Exercise the ordinary ExportDraft component's actual bundled setup/z/w/re.
// Only Vue primitives, timers and native/helper boundaries are simulated.
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const acorn = require("./acorn/acorn.js");
const source = fs.readFileSync("work/patched_frontend.js", "utf8");
const ast = acorn.parse(source, { ecmaVersion: "latest", sourceType: "module" });
let component;
const wrappers = new Map();
function visit(node) {
  if (!node || typeof node !== "object") return;
  if (node.type === "ObjectExpression" && node.properties.some(p =>
    p.key?.name === "__name" && p.value?.value === "ExportDraft")) component = node;
  if (node.type === "FunctionDeclaration" && ["CA", "Hf", "Gm", "Cr"].includes(node.id?.name)) {
    assert(!wrappers.has(node.id.name), `ambiguous wrapper ${node.id.name}`);
    wrappers.set(node.id.name, source.slice(node.start, node.end));
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value?.type) visit(value);
  }
}
visit(ast);
assert(component, "actual built ExportDraft component must exist");
assert.equal(wrappers.size, 4);
const setup = component.properties.find(p => p.key?.name === "setup")?.value;
const renderReturn = setup?.body.body.find(n => n.type === "ReturnStatement");
assert(renderReturn, "ExportDraft setup/render boundary must exist");
const render = source.slice(renderReturn.start, renderReturn.end);
assert(render.includes("G(A.value)"), "failed error text must be bound in the actual render");
assert(render.includes("G(x.value.message||E.value)"), "running/reconnect message must be bound in the actual render");
const setupBody = source.slice(setup.body.start + 1, renderReturn.start);
const setupHarness = `(function(e,{emit:t}){${setupBody}
return {z,w,re,te,d,c,x,f,D,A,E};})({functionId:1,m1Activated:1},{emit(){}})`;
let studio = fs.readFileSync("work/studio_design.js", "utf8");
const cutoff = studio.indexOf("\nXYDesign_theme(");
assert(cutoff >= 0);
studio = studio.slice(0, cutoff);
const runtime = [
  fs.readFileSync("work/export_diagnostics.js", "utf8"), studio,
  fs.readFileSync("work/local_runtime.js", "utf8"), ...wrappers.values()
].join("\n");
const clone = value => JSON.parse(JSON.stringify(value));
const draftPath = "E:\\剪映项目\\自定义 位置\\普通草稿";
const outputPath = "D:\\最终视频\\普通草稿";
const idle = () => ({ running: false, phase: "idle", progress: 0, completed: 0, total: 0, message: "", error: "" });
const running = () => ({ running: true, phase: "waiting_output", progress: 25, completed: 0, total: 1, message: "剪映正在导出普通草稿", error: "" });
const completed = () => ({ running: false, phase: "completed", progress: 100, completed: 1, total: 1, message: "导出完成", error: "" });
const failed = () => ({
  running: false, phase: "failed", progress: 0, completed: 0, total: 1,
  message: "导出失败", error: "等待剪映回到首页失败（当前时间线）: QT_HOME_TIMEOUT"
});
function harness({ sizeMode = "original", setCover = "no", startResult = true, afterStart = running } = {}) {
  const timers = new Map(), notices = [], requests = [], nativeCalls = [];
  let timerId = 0;
  const state = { progress: idle(), pollError: null, queuedProgress: [], now: Date.now() };
  class TestDate extends Date {
    constructor(...args) { super(...(args.length ? args : [state.now])); }
    static now() { return state.now; }
  }
  const notify = notice => notices.push(notice);
  for (const type of ["warning", "error", "success", "info"]) notify[type] = message => notices.push({ type, message });
  const app = {
    GetQtInspectorExportProgress: async () => {
      if (state.queuedProgress.length) return clone(await state.queuedProgress.shift());
      if (state.pollError) throw state.pollError;
      return clone(state.progress);
    },
    GetDraftList: async () => [{ draftFolder: draftPath, draftName: "普通草稿" }],
    ListDraftTimelines: async path => {
      assert.equal(path, draftPath);
      return [{ id: "main", name: "当前时间线", isMain: true }];
    },
    BatchExportDraft: async params => {
      nativeCalls.push(clone(params));
      state.progress = afterStart();
      return startResult;
    }
  };
  const ctx = {
    console: { ...console, error() {} }, Date: TestDate, Set, Map, Promise, setTimeout, clearTimeout,
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options?.detail; } },
    b: value => ({ value }), Y: getter => ({ get value() { return getter(); } }),
    oo: async () => ({ platform: "windows" }), Wt() {}, so() {}, rt() {}, Vde: true,
    navigator: { platform: "Win32", userAgent: "Windows" },
    localStorage: { getItem: () => "", setItem() {} },
    XYUpdates: { installing: false, state: { install: { state: "idle" } } },
    Ie: notify, na: async () => ({ is_activated: "1", m1_trial_times: 0 }),
    window: {
      go: { main: { App: app } }, dispatchEvent() {},
      setInterval: callback => { timers.set(++timerId, callback); return timerId; },
      clearInterval: id => timers.delete(id)
    },
    fetch: async (url, args) => {
      const action = new URL(url).pathname.slice(1), body = JSON.parse(args.body);
      requests.push({ action, body });
      assert(!action.startsWith("collect/"), "ordinary export must not copy draft materials");
      if (action === "begin") return { json: async () => ({ id: "stage", folder: "D:\\视频临时处理" }) };
      if (action === "finish") return { json: async () => ({ state: "completed", outputFolder: outputPath }) };
      if (action === "cancel") return { json: async () => ({ cancelled: true }) };
      if (action === "diagnostics/export") return { json: async () => ({ logFile: "test-draft-export.log" }) };
      throw Error(`unexpected helper request ${action}`);
    }
  };
  vm.createContext(ctx);
  vm.runInContext(runtime, ctx);
  const api = vm.runInContext(setupHarness, ctx);
  Object.assign(api.d.value, {
    selectedDrafts: [draftPath], sizeMode, setCover, savePath: "custom", exportPath: outputPath, shutdown: "no",
    collectMaterials: true, collectBusy: true, collectMessage: "旧复制设置", collectError: true
  });
  api.c.value.draftList = [{ draftFolder: draftPath, draftName: "普通草稿", isChecked: true }];
  return { api, ctx, state, timers, notices, requests, nativeCalls };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
function assertStarted(test) {
  assert.equal(test.nativeCalls.length, 1);
  assert.deepStrictEqual(test.nativeCalls[0].selectedDrafts, [draftPath]);
  assert.equal(test.nativeCalls[0].deleteDraftAfterExport, false);
  assert.equal(test.nativeCalls[0].namePrefix, "普通草稿=当前时间线");
  assert(!test.requests.some(request => request.action.startsWith("collect/")));
}
function assertTerminal(test, phase) {
  assert.equal(test.api.x.value.phase, phase);
  assert.equal(test.timers.size, 0);
  assert.equal(vm.runInContext("XYLocal_job", test.ctx), null);
}
(async () => {
  let scenarios = 0;
  for (const options of [{ sizeMode: "original", setCover: "no" }, { sizeMode: "auto720", setCover: "random" }]) {
    const quickFailure = harness({ ...options, afterStart: failed });
    await quickFailure.api.z();
    await settle();
    assertStarted(quickFailure);
    assertTerminal(quickFailure, "failed");
    assert(quickFailure.api.f.value, "failure details must remain visible in the progress dialog");
    assert(quickFailure.api.A.value.includes("QT_HOME_TIMEOUT"), "render-bound error must preserve the home timeout reason");
    assert(!quickFailure.notices.some(n => n.type === "success"), "immediate failure must not be followed by a started-success toast");
    const diagnostic = quickFailure.requests.find(request => request.action === "diagnostics/export");
    assert(diagnostic);
    assert.equal(diagnostic.body.method, "BatchExportDraft");
    assert(diagnostic.body.message.includes("等待剪映回到首页失败"));
    if (options.sizeMode !== "original") assert(quickFailure.requests.some(request => request.action === "cancel"));
    scenarios++;

    const quickCompletion = harness({ ...options, afterStart: completed });
    await quickCompletion.api.z();
    assertStarted(quickCompletion);
    assertTerminal(quickCompletion, "completed");
    assert.equal(quickCompletion.api.x.value.completed, 1);
    if (options.sizeMode !== "original") assert(quickCompletion.requests.some(request => request.action === "finish"));
    scenarios++;

    const disconnected = harness(options);
    await disconnected.api.z();
    disconnected.state.pollError = Error("WAILS_DRAFT_PROGRESS_DISCONNECTED");
    for (let i = 0; i < 5; i++) {
      disconnected.state.now += 2100;
      await disconnected.api.re();
    }
    await settle();
    assert.equal(disconnected.api.x.value.phase, "reconnecting");
    assert.equal(disconnected.api.x.value.running, true);
    assert.equal(disconnected.api.E.value, "正在恢复进度连接");
    assert(disconnected.api.x.value.message.includes("正在重试"), "render-bound running message must explain reconnecting");
    assert(disconnected.api.x.value.error.includes("WAILS_DRAFT_PROGRESS_DISCONNECTED"));
    assert(disconnected.timers.size > 0);
    assert.equal(disconnected.requests.filter(request => request.action === "diagnostics/export").length, 1);
    assert(!disconnected.requests.some(request => request.action === "cancel"));
    disconnected.state.pollError = null;
    disconnected.state.progress = completed();
    disconnected.state.now += 2100;
    await disconnected.api.re();
    assertTerminal(disconnected, "completed");
    assert.equal(disconnected.nativeCalls.length, 1, "recovery must not start another export");
    if (options.sizeMode !== "original") assert(disconnected.requests.some(request => request.action === "finish"));
    scenarios++;
  }

  const lateOldPoll = harness();
  let releaseOld;
  lateOldPoll.state.queuedProgress.push(new Promise(resolve => { releaseOld = resolve; }));
  await lateOldPoll.api.z();
  assertStarted(lateOldPoll);
  assert.equal(lateOldPoll.api.x.value.phase, "waiting_output");
  releaseOld(failed());
  await settle();
  assert.equal(lateOldPoll.api.x.value.phase, "waiting_output", "pre-ack RPC cannot overwrite the acknowledged task");
  assert.equal(lateOldPoll.api.x.value.progress, 25);
  assert(lateOldPoll.timers.size > 0);
  lateOldPoll.api.te();
  scenarios++;

  const repeated = harness();
  await repeated.api.z();
  const activeTimers = [...repeated.timers.keys()];
  repeated.api.f.value = false;
  await repeated.api.z();
  assert.equal(repeated.nativeCalls.length, 1, "repeated click must not start another native export");
  assert.deepStrictEqual([...repeated.timers.keys()], activeTimers, "repeated click must retain the original progress poll");
  assert.equal(repeated.api.f.value, true, "repeated click reopens the existing task's progress dialog");
  assert.equal(repeated.api.x.value.phase, "waiting_output");
  assert(!repeated.notices.some(notice => notice.type === "error"));
  repeated.api.te();
  scenarios++;

  const rejected = harness({ startResult: false, afterStart: idle, sizeMode: "auto720", setCover: "random" });
  await rejected.api.z();
  await settle();
  assertStarted(rejected);
  assert.equal(rejected.timers.size, 0);
  assert.equal(rejected.api.f.value, false, "rejected native start must close the initializing modal");
  assert.equal(vm.runInContext("XYLocal_job", rejected.ctx), null);
  assert(rejected.requests.some(request => request.action === "cancel"));
  assert(!rejected.notices.some(notice => notice.type === "success"));
  assert(rejected.notices.some(notice => notice.type === "error"));
  scenarios++;
  console.log(`PASS ${scenarios} actual ExportDraft component scenarios: immediate native failure/completion, rendered home-timeout reason, RPC reconnection/recovery, stale response isolation and rejected-start cleanup`);
})().catch(error => { console.error(error); process.exitCode = 1; });
