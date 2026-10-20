// Execute the production orchestration with an isolated native/helper boundary.
// No registry access, editor launch or personal draft writes are performed.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const runtime = fs.readFileSync(path.join(__dirname, "local_runtime.js"), "utf8");
const draftPath = "E:\\草稿原位置\\测试草稿";
const defaultPath = "D:\\剪映默认成品";
const customPath = "E:\\指定成品";
const stagePath = "D:\\隔离视频处理目录";
const clone = value => JSON.parse(JSON.stringify(value));

function harness(options = {}) {
  const calls = [], requests = [], native = [];
  const app = {
    GetQtInspectorExportProgress: async () => ({ running: false, phase: "idle" }),
    ListDraftTimelines: async folder => {
      assert.equal(folder, draftPath);
      return [{ id: "timeline-main", name: "主时间线", isMain: true }];
    },
    GetDraftList: async () => [{ draftFolder: draftPath, draftName: "测试草稿" }],
    GetSetting: async () => {
      calls.push("GetSetting");
      if (options.settingError) throw options.settingError;
      return { draft_source: options.source === undefined ? "JianyingPro" : options.source };
    }
  };
  for (const method of ["BatchExportDraft", "BatchExportMultiTimeline"]) {
    app[method] = async params => { native.push({ method, params: clone(params) }); return true; };
  }
  const context = {
    console, XYExport_stage: "", XYDesign_map: (items, fn) => Promise.all(items.map(fn)),
    XYDesign_startExport: () => {},
    window: { go: { main: { App: app } } },
    fetch: async (url, config) => {
      const action = new URL(url).pathname.slice(1), body = JSON.parse(config.body);
      requests.push({ action, body });
      if (action === "export/default-path") {
        return { json: async () => options.defaultError ? { error: options.defaultError } : {
          folder: options.invalidResponse ? "" : defaultPath, source: body.appSource
        } };
      }
      if (action === "begin") return { json: async () => ({ id: "video-job", folder: stagePath }) };
      throw Error("Unexpected helper action: " + action);
    }
  };
  vm.createContext(context);
  vm.runInContext(runtime, context);
  return { context, calls, requests, native, start: context.XYLocal_startCore, render: context.XYLocal_controlBody };
}

function params(overrides = {}) {
  return {
    selectedDrafts: [draftPath],
    selections: [{ draftPath, timelineIds: ["timeline-main"] }],
    savePath: "default", exportPath: "", sizeMode: "original", setCover: "no", removeSilence: false, shutdown: "no",
    ...overrides
  };
}

function verifySourceUnchanged(test, before, supplied) {
  assert.deepStrictEqual(supplied, before, "caller preferences must stay unchanged");
  assert.deepStrictEqual(test.native[0].params.selectedDrafts, before.selectedDrafts);
  assert.deepStrictEqual(test.native[0].params.selections, before.selections);
  assert(!test.requests.some(r => r.action.startsWith("collect/")), "default export must never copy drafts or materials");
}

(async () => {
  let scenarios = 0;
  for (const method of ["BatchExportDraft", "BatchExportMultiTimeline"]) {
    for (const selection of [
      { setCover: "random" },
      ...["auto720", "auto1080", "auto1440", "auto2160"].map(sizeMode => ({ sizeMode })),
      { removeSilence: true }
    ]) {
      const test = harness(), supplied = params(selection), before = clone(supplied);
      assert.strictEqual(await test.start(method, supplied), true);
      assert.deepStrictEqual(test.calls, ["GetSetting"]);
      assert.deepStrictEqual(test.requests.map(r => r.action), ["export/default-path", "begin"]);
      assert.strictEqual(test.requests[0].body.appSource, "JianyingPro");
      const begin = test.requests[1].body;
      assert.strictEqual(begin.folder, defaultPath, "final output must use the registered client directory");
      assert.strictEqual(begin.mode, supplied.sizeMode);
      assert.strictEqual(begin.coverMode, supplied.setCover === "random" ? "random" : "first");
      assert.strictEqual(begin.removeSilence, supplied.removeSilence);
      assert.strictEqual(test.native.length, 1);
      assert.strictEqual(test.native[0].params.exportPath, stagePath, "only rendered videos are staged");
      assert.strictEqual(test.native[0].params.savePath, "custom", "native must use the video staging path even when the saved preference is default");
      verifySourceUnchanged(test, before, supplied);
      scenarios++;
    }
    {
      const test = harness({ source: "CapCut" }), supplied = params({ setCover: "random" });
      await test.start(method, supplied);
      assert.strictEqual(test.requests[0].body.appSource, "CapCut");
      assert.strictEqual(test.requests[1].body.folder, defaultPath);
      assert.strictEqual(test.native[0].params.savePath, "custom");
      scenarios++;
    }
    {
      const test = harness({ settingError: Error("GetSetting must not run") });
      const supplied = params({ savePath: "custom", exportPath: customPath, sizeMode: "auto1080", setCover: "random" }), before = clone(supplied);
      await test.start(method, supplied);
      assert.deepStrictEqual(test.calls, []);
      assert.deepStrictEqual(test.requests.map(r => r.action), ["begin"]);
      assert.strictEqual(test.requests[0].body.folder, customPath);
      assert.strictEqual(test.native[0].params.savePath, "custom");
      assert.strictEqual(test.native[0].params.exportPath, stagePath);
      verifySourceUnchanged(test, before, supplied);
      scenarios++;
    }
    {
      const test = harness({ settingError: Error("GetSetting must not run") });
      const supplied = params(), before = clone(supplied);
      await test.start(method, supplied);
      assert.deepStrictEqual(test.calls, []);
      assert.deepStrictEqual(test.requests, []);
      assert.strictEqual(test.native[0].params.exportPath, "", "original/first keeps native default-path behavior");
      assert.strictEqual(test.native[0].params.savePath, "default", "unprocessed export must keep native default mode");
      verifySourceUnchanged(test, before, supplied);
      scenarios++;
    }
    for (const failure of [
      { options: { defaultError: "尚未找到剪映的默认导出目录。请先设置保存位置。" }, pattern: /尚未找到剪映的默认导出目录/ },
      { options: { defaultError: "剪映的默认导出目录不存在或无法访问。" }, pattern: /默认导出目录不存在或无法访问/ },
      { options: { source: "..\\OtherApplication" }, pattern: /草稿来源设置无效/ },
      { options: { invalidResponse: true }, pattern: /未能读取客户端默认导出目录/ },
      { options: { settingError: Error("GetSetting RPC failure") }, pattern: /GetSetting RPC failure/ }
    ]) {
      const test = harness(failure.options), supplied = params({ setCover: "random" }), before = clone(supplied);
      await assert.rejects(test.start(method, supplied), failure.pattern);
      assert.deepStrictEqual(test.native, [], "unresolved default path must never start native export");
      assert(!test.requests.some(r => r.action === "begin"), "unresolved path must not create a video job");
      assert.strictEqual(vm.runInContext("XYLocal_job", test.context), null);
      assert.deepStrictEqual(supplied, before);
      scenarios++;
    }
  }
  const test = harness();
  const h = (tag, props, children) => ({ tag, props, children });
  const rendered = JSON.stringify(test.render(params({ sizeMode: "auto720", removeSilence: true }), h, false));
  assert(!/请选择自定义保存路径|需要自定义保存路径/.test(rendered));
  assert(rendered.includes("沿用客户端默认或所选自定义目录"));
  console.log(`PASS ${scenarios} default export path scenarios: both exports, random cover, 720/1080/2K/4K, silence removal, native default passthrough, custom paths, CapCut and failure isolation`);
})().catch(error => { console.error(error); process.exitCode = 1; });
