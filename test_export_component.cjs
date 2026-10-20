// Integration regression for the actual bundled Vue export handlers.
// Run after patch_frontend.cjs: the test extracts setup/Q/J/j from the built bundle.
// Only Vue primitives, lifecycle scheduling and backend boundaries are simulated.
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
    p.key?.name === "__name" && p.value?.value === "ExportMultiTimeline")) component = node;
  if (node.type === "FunctionDeclaration" && ["EA", "Hf", "Gm", "Cr"].includes(node.id?.name)) {
    assert(!wrappers.has(node.id.name), `ambiguous native wrapper ${node.id.name}`);
    wrappers.set(node.id.name, source.slice(node.start, node.end));
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value?.type) visit(value);
  }
}
visit(ast);
assert(component, "built ExportMultiTimeline component was not found");
assert.equal(wrappers.size, 4, "expected the actual start/progress/error wrappers");
const setup = component.properties.find(p => p.key?.name === "setup")?.value;
const renderReturn = setup?.body.body.find(n => n.type === "ReturnStatement");
assert(renderReturn, "component setup/render boundary was not found");
// Retain every real setup declaration and handler; expose their state in place of rendering.
const setupBody = source.slice(setup.body.start + 1, renderReturn.start);
const setupHarness = `(function(e,{emit:t}){${setupBody}
return {Q,J,j,d,f,A,T,$,E,Fe};})({functionId:1,m1Activated:1},{emit(){}})`;
let studio = fs.readFileSync("work/studio_design.js", "utf8");
const studioCutoff = studio.indexOf("\nXYDesign_theme(");
assert(studioCutoff >= 0);
studio = studio.slice(0, studioCutoff);
const runtime = [
  fs.readFileSync("work/export_diagnostics.js", "utf8"),
  studio,
  fs.readFileSync("work/local_runtime.js", "utf8"),
  ...wrappers.values()
].join("\n");
const clone = x => JSON.parse(JSON.stringify(x));
const draftPath = "E:\\剪映项目\\用户选择的位置\\外部素材4";
const outputPath = "D:\\最终视频\\外部素材4";
const timelineIds = Array.from({ length: 13 }, (_, i) => `timeline-${i + 1}`);
const timelines = timelineIds.map((id, i) => ({ id, name: `时间线${i + 1}`, isMain: i === 0 }));
const idle = () => ({ running: false, phase: "idle", progress: 0, completed: 0, total: 0, error: "" });

function harness({ sizeMode = "original", setCover = "no", startResult = true, startError = null } = {}) {
  const timers = new Map(), notices = [], requests = [], nativeCalls = [];
  let timerId = 0;
  const state = { progress: idle(), pollError: null, nativeGate: null, progressReads: 0, queuedProgress: [], now: Date.now() };
  class TestDate extends Date {
    constructor(...args) { super(...(args.length ? args : [state.now])); }
    static now() { return state.now; }
  }
  const notify = notice => notices.push(notice);
  for (const type of ["warning", "error", "success", "info"]) {
    notify[type] = message => notices.push({ type, message });
  }
  const app = {
    GetQtInspectorExportProgress: async () => {
      state.progressReads++;
      if (state.queuedProgress.length) return clone(await state.queuedProgress.shift());
      if (state.pollError) throw state.pollError;
      return clone(state.progress);
    },
    ListDraftTimelines: async path => {
      assert.equal(path, draftPath);
      return clone(timelines);
    },
    BatchExportMultiTimeline: async params => {
      nativeCalls.push(clone(params));
      if (state.nativeGate) await state.nativeGate;
      if (startError) throw startError;
      return startResult;
    }
  };
  const ctx = {
    console: { ...console, error() {} },
    Date: TestDate, Set, Map, Promise, setTimeout, clearTimeout,
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options?.detail; } },
    b: value => ({ value }),
    Y: getter => ({ get value() { return getter(); } }),
    oo: async () => ({ platform: "windows" }),
    Wt() {}, so() {}, rt() {},
    navigator: { platform: "Win32", userAgent: "Windows" },
    localStorage: { getItem: () => "", setItem() {} },
    XYUpdates: { installing: false, state: { install: { state: "idle" } } },
    Ie: notify,
    na: async () => ({ is_activated: "1", m1_trial_times: 0 }),
    window: {
      go: { main: { App: app } },
      dispatchEvent() {},
      setInterval: callback => { timers.set(++timerId, callback); return timerId; },
      clearInterval: id => timers.delete(id)
    },
    fetch: async (url, args) => {
      const action = new URL(url).pathname.slice(1), body = JSON.parse(args.body);
      requests.push({ action, body });
      assert(!action.startsWith("collect/"), "component must not copy draft materials");
      if (action === "begin") return { json: async () => ({ id: "stage", folder: "D:\\视频临时处理" }) };
      if (action === "finish") return { json: async () => ({ state: "completed", outputFolder: outputPath }) };
      if (action === "cancel") return { json: async () => ({ cancelled: true }) };
      if (action === "diagnostics/export") return { json: async () => ({ logFile: "test-export.log" }) };
      throw Error(`unexpected helper request ${action}`);
    }
  };
  vm.createContext(ctx);
  vm.runInContext(runtime, ctx);
  const api = vm.runInContext(setupHarness, ctx);
  Object.assign(api.d.value, {
    selectedDrafts: [draftPath], sizeMode, setCover,
    savePath: "custom", exportPath: outputPath, shutdown: "no",
    collectMaterials: true, collectBusy: true,
    collectMessage: "旧版遗留的复制状态", collectError: true
  });
  api.f.value = [{ draftPath, draftName: "外部素材4", timelines: clone(timelines), selectedIds: [...timelineIds] }];
  return { api, ctx, state, timers, notices, requests, nativeCalls };
}

const settle = () => new Promise(resolve => setImmediate(resolve));
function assertStarted(test) {
  assert.equal(test.nativeCalls.length, 1);
  assert.deepStrictEqual(test.nativeCalls[0].selectedDrafts, [draftPath]);
  assert.deepStrictEqual(test.nativeCalls[0].selections, [{ draftPath, timelineIds }]);
  assert.equal(test.api.E.value, 13);
  assert(!/临时草稿|复制草稿/.test(test.api.A.value.message),
    "pre-render status must not falsely claim to be copying a draft");
}
function assertStopped(test, phase) {
  assert.equal(test.api.A.value.phase, phase);
  assert.equal(test.timers.size, 0, "terminal state must stop polling");
}

(async () => {
  let scenarios = 0;
  for (const options of [
    { sizeMode: "original", setCover: "no" },
    { sizeMode: "auto720", setCover: "random" }
  ]) {
    // The native Go method starts a worker and immediately acknowledges with true.
    // Failure can occur before the UI's next 500 ms poll; no running sample is guaranteed.
    const failed = harness(options);
    await failed.api.Q();
    assertStarted(failed);
    failed.api.T.value = false;
    await failed.api.Q();
    assert.equal(failed.nativeCalls.length, 1, "clicking again must reopen the running task");
    assert.equal(failed.api.T.value, true);
    assert.equal(failed.timers.size, 1, "clicking again must keep the active progress poll");
    scenarios++;
    failed.state.progress = {
      running: false, phase: "failed", progress: 0, completed: 0, total: 13,
      error: "剪映当前正在编辑草稿，请返回剪映首页后再开始导出"
    };
    failed.state.now += 600;
    await failed.api.j();
    assertStopped(failed, "failed");
    assert(failed.api.A.value.error.includes("返回剪映首页"));
    assert(failed.requests.some(r => r.action === "diagnostics/export" &&
      r.body.message.includes("返回剪映首页")), "asynchronous native failure must be saved");
    if (options.sizeMode !== "original") assert(failed.requests.some(r => r.action === "cancel"));
    scenarios++;

    const completed = harness(options);
    await completed.api.Q();
    assertStarted(completed);
    completed.state.progress = { running: false, phase: "completed", progress: 100, completed: 13, total: 13, error: "" };
    completed.state.now += 600;
    await completed.api.j();
    assertStopped(completed, "completed");
    assert.equal(completed.api.A.value.completed, 13);
    if (options.sizeMode !== "original") assert(completed.requests.some(r => r.action === "finish"));
    scenarios++;
  }

  const pending = harness();
  let release;
  pending.state.nativeGate = new Promise(resolve => { release = resolve; });
  const starting = pending.api.Q();
  await settle();
  assert.equal(pending.nativeCalls.length, 1);
  pending.state.progress = { running: false, phase: "completed", progress: 100, completed: 13, total: 13 };
  pending.state.now += 600;
  await pending.api.j();
  assert.notEqual(pending.api.A.value.phase, "completed", "stale completion must not finish a pending start");
  assert(pending.timers.size > 0);
  // The native method resets its progress synchronously before acknowledging true.
  pending.state.progress = { running: true, phase: "connecting", progress: 0, completed: 0, total: 13, error: "" };
  release();
  await starting;
  assert(pending.timers.size > 0, "acknowledging a running task must keep its progress polling");
  pending.state.progress = { running: false, phase: "failed", completed: 0, total: 13, error: "本次任务启动后失败" };
  pending.state.now += 600;
  await pending.api.j();
  assertStopped(pending, "failed");
  scenarios++;

  const lateOldPoll = harness();
  let resolveOldPoll;
  lateOldPoll.state.queuedProgress.push(new Promise(resolve => { resolveOldPoll = resolve; }));
  await lateOldPoll.api.Q();
  lateOldPoll.state.progress = {
    running: true, phase: "waiting_output", progress: 37,
    completed: 2, total: 13, message: "本次任务正在导出", error: ""
  };
  lateOldPoll.state.now += 600;
  await lateOldPoll.api.j();
  assert.equal(lateOldPoll.api.A.value.phase, "waiting_output");
  resolveOldPoll({ running: false, phase: "failed", completed: 0, total: 13, error: "上次任务的延迟响应" });
  await settle();
  assert.equal(lateOldPoll.api.A.value.phase, "waiting_output", "pre-ack poll must not overwrite the acknowledged job");
  assert.equal(lateOldPoll.api.A.value.progress, 37);
  assert(lateOldPoll.timers.size > 0);
  lateOldPoll.api.Fe();
  scenarios++;

  for (const options of [
    { sizeMode: "original", setCover: "no" },
    { sizeMode: "auto720", setCover: "random" }
  ]) {
    const silentBackend = harness(options);
    await silentBackend.api.Q();
    silentBackend.state.now += 11000;
    await silentBackend.api.j();
    assert.equal(silentBackend.api.A.value.phase, "reconnecting",
      "an acknowledged backend stuck idle must not silently show initialization forever");
    assert.equal(silentBackend.api.A.value.running, true);
    assert(silentBackend.timers.size > 0);
    silentBackend.state.progress = {
      running: true, phase: "waiting_output", progress: 10,
      completed: 0, total: 13, message: "剪映正在导出视频", error: ""
    };
    silentBackend.state.now += 2100;
    await silentBackend.api.j();
    assert.equal(silentBackend.api.A.value.phase, "waiting_output");
    silentBackend.state.progress = { running: false, phase: "completed", progress: 100, completed: 13, total: 13, error: "" };
    silentBackend.state.now += 600;
    await silentBackend.api.j();
    assertStopped(silentBackend, "completed");
    assert.equal(vm.runInContext("XYLocal_job", silentBackend.ctx), null);
    scenarios++;
  }

  for (const options of [
    { sizeMode: "original", setCover: "no" },
    { sizeMode: "auto720", setCover: "random" }
  ]) {
    const brokenPoll = harness(options);
    await brokenPoll.api.Q();
    brokenPoll.state.pollError = Error("进度 RPC 已断开：WAILS_DISCONNECTED");
    for (let i = 0; i < 5; i++) {
      brokenPoll.state.now += 2100;
      await brokenPoll.api.j();
    }
    assert.equal(brokenPoll.api.A.value.phase, "reconnecting");
    assert.equal(brokenPoll.api.A.value.running, true, "lost transport cannot prove the native export stopped");
    assert(brokenPoll.timers.size > 0, "lost transport must retain a recovery poll");
    assert(/WAILS_DISCONNECTED/.test(brokenPoll.api.A.value.error + " " + brokenPoll.api.A.value.message),
      "polling errors must be visible instead of swallowed");
    await settle();
    assert.equal(brokenPoll.requests.filter(r => r.action === "diagnostics/export").length, 1,
      "the same transport outage must not flood diagnostics");
    assert(!brokenPoll.requests.some(r => r.action === "cancel"),
      "transport loss must not delete the stage of an export that may still be running");
    brokenPoll.state.pollError = null;
    brokenPoll.state.progress = { running: false, phase: "completed", progress: 100, completed: 13, total: 13, error: "" };
    brokenPoll.state.now += 2100;
    await brokenPoll.api.j();
    assertStopped(brokenPoll, "completed");
    assert.equal(brokenPoll.nativeCalls.length, 1, "reconnecting must not start another export");
    assert.equal(vm.runInContext("XYLocal_job", brokenPoll.ctx), null, "recovery must release video staging");
    if (options.sizeMode !== "original") assert(brokenPoll.requests.some(r => r.action === "finish"));
    scenarios++;
  }

  for (const options of [
    { startResult: false },
    { startResult: undefined },
    { startResult: { success: false, error: "native result was not acknowledged" } },
    { startError: Error("真实启动失败：QT_CONNECT_TIMEOUT") }
  ]) {
    // Undefined needs an explicit assignment because the harness default is true.
    const test = harness(options);
    if (Object.hasOwn(options, "startResult") && options.startResult === undefined) {
      test.ctx.window.go.main.App.BatchExportMultiTimeline = async params => {
        test.nativeCalls.push(clone(params)); return undefined;
      };
    }
    await test.api.Q();
    await settle();
    assert.equal(test.nativeCalls.length, 1);
    assert.equal(test.timers.size, 0, "rejected start must clear the real component's interval");
    assert.equal(test.api.T.value, false, "rejected start must close the initializing dialog");
    assert(!test.notices.some(n => n.type === "success"), "unacknowledged start must not announce success");
    assert(test.notices.some(n => n.type === "error"));
    if (options.startError) {
      assert(test.notices.some(n => String(n.message).includes("QT_CONNECT_TIMEOUT")));
    }
    scenarios++;
  }
  console.log(`PASS ${scenarios} real ExportMultiTimeline component scenarios: start acknowledgement, fast terminal states, stale completion isolation, RPC recovery without duplicate export, strict native boolean contract, custom paths and 13 timelines`);
})().catch(error => { console.error(error); process.exitCode = 1; });
