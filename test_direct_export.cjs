// Exercise the shipped export orchestration, including preferences left by older versions.
// Backend calls are isolated; this test never opens or changes a real draft.
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");

const draftPath = "E:\\我的剪辑工程\\自选草稿位置\\外部素材4";
const outputPath = "D:\\视频成品\\外部素材4";
const stagedVideos = "D:\\视频成品\\临时视频处理";
const timelines = Array.from({ length: 13 }, (_, i) => ({
  id: `timeline-${i + 1}`,
  name: i === 0 ? "主时间线" : `时间线${String(i + 1).padStart(2, "0")}`,
  isMain: i === 0
}));
const staleSettings = {
  collectMaterials: true,
  collectBusy: true,
  collectMessage: "正在复制旧草稿素材",
  collectError: true
};
const legacyKeys = Object.keys(staleSettings);
const copy = value => JSON.parse(JSON.stringify(value));

function harness(nativeError = null) {
  const nativeCalls = [], reads = [], requests = [], events = [];
  const app = {
    GetQtInspectorExportProgress: async () => ({ running: false, phase: "idle" }),
    ListDraftTimelines: async path => {
      reads.push({ method: "ListDraftTimelines", path });
      assert.equal(path, draftPath, "timeline metadata must come from the chosen draft");
      return copy(timelines);
    },
    GetDraftList: async () => [{ draftFolder: draftPath, draftName: "外部素材4" }]
  };
  for (const method of ["BatchExportMultiTimeline", "BatchExportDraft"]) {
    app[method] = async params => {
      nativeCalls.push({ method, params: copy(params) });
      if (nativeError) throw nativeError;
      return true;
    };
  }
  const ctx = {
    console, Date, Set, Map, Promise, setTimeout, clearTimeout,
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options?.detail; } },
    XYUpdates: { installing: false, state: { install: { state: "idle" } } },
    window: { go: { main: { App: app } }, dispatchEvent: event => events.push(event) },
    fetch: async (url, args) => {
      const action = new URL(url).pathname.slice(1);
      const body = JSON.parse(args.body);
      requests.push({ action, body });
      assert(!action.startsWith("collect/"), "ordinary exports must never copy or rewrite draft materials");
      if (action === "begin") return { json: async () => ({ id: "video-stage", folder: stagedVideos }) };
      if (action === "diagnostics/export") return { json: async () => ({ logFile: "test-export.log" }) };
      if (action === "cancel") return { json: async () => ({ cancelled: true }) };
      throw Error(`Unexpected helper operation: ${action}`);
    }
  };
  vm.createContext(ctx);
  let studio = fs.readFileSync("work/studio_design.js", "utf8");
  const cutoff = studio.indexOf("\nXYDesign_theme(");
  assert(cutoff >= 0, "could not isolate the real studio export functions");
  studio = studio.slice(0, cutoff);
  vm.runInContext(
    fs.readFileSync("work/export_diagnostics.js", "utf8") + "\n" +
    studio + "\n" +
    fs.readFileSync("work/local_runtime.js", "utf8"),
    ctx
  );
  return {
    ctx, nativeCalls, reads, requests, events,
    start: vm.runInContext("XYLocal_start", ctx),
    render: vm.runInContext("XYLocal_controlBody", ctx)
  };
}

function paramsFor(sizeMode, setCover) {
  return {
    selectedDrafts: [draftPath],
    selections: [{ draftPath, timelineIds: timelines.map(t => t.id) }],
    exportPath: outputPath,
    sizeMode, setCover, removeSilence: false, shutdown: "no",
    ...staleSettings
  };
}

function h(tag, props, children) { return { tag, props: props || {}, children }; }
function walk(node) {
  if (node === null || node === undefined || node === false) return [];
  if (Array.isArray(node)) return node.flatMap(walk);
  if (typeof node !== "object") return [node];
  return [node, ...walk(node.children)];
}
function renderNodes(test, params, pending = false) { return walk(test.render(params, h, pending, null)); }
function text(nodes) { return nodes.filter(n => typeof n === "string").join(" "); }
function startButton(nodes) {
  const button = nodes.find(n => n?.tag === "button" && n.props.class?.includes("primary"));
  assert(button, "export action should be present");
  return button;
}

(async () => {
  let scenarios = 0;
  for (const method of ["BatchExportMultiTimeline", "BatchExportDraft"]) {
    for (const [sizeMode, setCover] of [["original", "no"], ["auto720", "random"]]) {
      const test = harness();
      const params = paramsFor(sizeMode, setCover), before = copy(params);
      assert.equal(await test.start(method, params), true);
      assert.equal(test.nativeCalls.length, 1, "one click must start one native export");
      const actual = test.nativeCalls[0].params;
      assert.deepStrictEqual(actual.selectedDrafts, before.selectedDrafts);
      assert.deepStrictEqual(actual.selections, before.selections);
      assert.equal(test.reads.length, 1);
      for (const key of legacyKeys) {
        assert(!Object.prototype.hasOwnProperty.call(actual, key), `legacy ${key} leaked to native export`);
      }
      assert.deepStrictEqual(params, before, "starting export should not rewrite the caller's draft selection");
      if (sizeMode === "original") {
        assert.equal(actual.exportPath, outputPath);
        assert.equal(test.requests.length, 0, "unchanged video exports need no material or staging operation");
      } else {
        assert.deepStrictEqual(test.requests.map(r => r.action), ["begin"]);
        const begin = test.requests[0].body;
        assert.equal(begin.folder, outputPath, "video staging must retain the user's final output directory");
        assert.equal(begin.mode, "auto720");
        assert.equal(begin.coverMode, "random");
        assert.equal(begin.names.length, method === "BatchExportMultiTimeline" ? 13 : 1);
        assert.equal(actual.exportPath, stagedVideos, "only rendered video output should enter staging");
        assert.equal(actual.setCover, "no", "random cover is handled after native rendering");
      }
      if (method === "BatchExportMultiTimeline") {
        assert.equal(actual.selections[0].timelineIds.length, 13);
        assert.equal(actual.nameVideo, "no");
      } else {
        assert.equal(actual.namePrefix, "外部素材4=主时间线");
      }
      assert.equal(vm.runInContext("XYDesign_startPending", test.ctx), false);
      assert.equal(vm.runInContext("typeof XYLocal_collect", test.ctx), "undefined");
      scenarios++;
    }
  }

  const ui = harness(), params = paramsFor("original", "no");
  const nodes = renderNodes(ui, params);
  assert.equal(startButton(nodes).props.disabled, false, "stale material-copy flags must not disable export");
  assert(!/复制|备份|素材整理/.test(text(nodes)), "ordinary export panel must not offer material-copy controls");
  assert(!text(nodes).includes(staleSettings.collectMessage), "old material-copy status must not reappear");
  assert.equal(startButton(renderNodes(ui, { ...params, selectedDrafts: [] })).props.disabled, true);
  assert.equal(startButton(renderNodes(ui, params, true)).props.disabled, true);
  assert.equal(startButton(renderNodes(ui, { ...params, timelineLoading: true })).props.disabled, true);

  for (const method of ["BatchExportMultiTimeline", "BatchExportDraft"]) {
    const nativeError = { message: "真实剪映导出错误：QT_CONNECT_TIMEOUT", code: -42 };
    const test = harness(nativeError);
    await assert.rejects(() => test.start(method, paramsFor("auto720", "random")), e => e === nativeError);
    assert.equal(test.nativeCalls.length, 1);
    assert.deepStrictEqual(test.requests.filter(r => r.action !== "diagnostics/export").map(r => r.action), ["begin", "cancel"]);
    assert.equal(vm.runInContext("XYExport_error.message", test.ctx), nativeError.message);
    assert.equal(vm.runInContext("XYExport_error.stage", test.ctx), "启动剪映导出组件");
    assert.equal(vm.runInContext("XYLocal_job", test.ctx), null);
    assert.equal(vm.runInContext("XYDesign_startPending", test.ctx), false);
  }
  console.log(`PASS ${scenarios} direct export scenarios: chosen Chinese draft paths, 13 timelines, no material-copy calls, stale preference removal, video-only staging, usable export controls and unchanged native errors`);
})().catch(error => { console.error(error); process.exitCode = 1; });
