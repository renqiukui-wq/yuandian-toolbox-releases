const fs = require("fs"), vm = require("vm"), assert = require("assert"), path = require("path");
const runtime = fs.readFileSync(path.join(__dirname, "local_runtime.js"), "utf8");
const params = {
  sizeMode: "original", setCover: "random", savePath: "custom", exportPath: "C:/deliver",
  selections: [{ draftPath: "draft", timelineIds: ["a", "b"] }], shutdown: "no"
};

function harness(defaultError = null) {
  const calls = [], settings = [];
  const context = {
    fetch: async (url, args) => {
      const body = JSON.parse(args.body), action = new URL(url).pathname;
      calls.push({ action, body });
      if (action === "/export/default-path") return {
        json: async () => defaultError ? { error: defaultError } : { folder: "C:/client-default", source: "JianyingPro" }
      };
      assert.equal(action, "/begin");
      return { json: async () => ({ id: "job", folder: "C:/private-stage", outputFolder: body.folder }) };
    },
    window: { go: { main: { App: {
      GetQtInspectorExportProgress: async () => ({ running: false }),
      GetSetting: async () => { settings.push("GetSetting"); return { draft_source: "JianyingPro" }; },
      ListDraftTimelines: async () => [{ id: "a", name: "横屏" }, { id: "b", name: "竖屏" }],
      BatchExportMultiTimeline: async value => { calls.push({ native: value }); return true; }
    } } } },
    XYDesign_map: (items, fn) => Promise.all(items.map(fn)), setTimeout
  };
  vm.createContext(context);
  vm.runInContext(runtime, context);
  return { context, calls, settings, start: context.XYLocal_startCore };
}

function verifyRandomStaging(test, folder) {
  const begin = test.calls.find(c => c.action === "/begin").body;
  const native = test.calls.find(c => c.native).native;
  assert.equal(begin.coverMode, "random");
  assert.equal(begin.mode, "original");
  assert.deepEqual(begin.names, ["横屏", "竖屏"]);
  assert.equal(begin.folder, folder);
  assert.equal(native.setCover, "no", "native rendering must leave random cover to postprocessing");
  assert.equal(native.exportPath, "C:/private-stage");
  assert.equal(native.savePath, "custom", "the native path mode must explicitly select staging");
  assert.deepEqual(native.selections, params.selections, "source draft path and selected timelines must not change");
}

(async () => {
  const custom = harness();
  assert.equal(await custom.start("BatchExportMultiTimeline", params), true);
  verifyRandomStaging(custom, "C:/deliver");
  assert.deepEqual(custom.settings, [], "custom paths require no client setting lookup");
  assert.equal(custom.calls.filter(c => c.native).length, 1);

  const automatic = harness(), defaultParams = { ...params, savePath: "default", exportPath: "" };
  assert.equal(await automatic.start("BatchExportMultiTimeline", defaultParams), true);
  verifyRandomStaging(automatic, "C:/client-default");
  assert.deepEqual(automatic.settings, ["GetSetting"]);
  assert.equal(automatic.calls[0].action, "/export/default-path");
  assert.equal(automatic.calls[0].body.appSource, "JianyingPro");
  assert.equal(defaultParams.exportPath, "", "saved default-path preference must stay unchanged");
  assert.equal(defaultParams.savePath, "default", "saved path mode must stay unchanged");
  assert.equal(automatic.calls.filter(c => c.native).length, 1);

  const message = "尚未找到剪映的默认导出目录。请先在客户端的导出窗口设置保存位置，或在工具箱选择自定义保存目录。";
  const missing = harness(message);
  await assert.rejects(() => missing.start("BatchExportMultiTimeline", defaultParams), e => e.message === message);
  assert.deepEqual(missing.calls.map(c => c.action), ["/export/default-path"]);
  assert.equal(vm.runInContext("XYLocal_job", missing.context), null);
  console.log("PASS random cover custom/default staging, unchanged native parameters and missing-default failure without native export");
})().catch(error => { console.error(error); process.exitCode = 1; });
