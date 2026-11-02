import { describe, expect, it } from "vitest";
import { contextPackage, isTestPath, ModuleIndex, moduleOf, packageName, parseImport, parseNameStatus, signatures } from "./repo.js";
import { groupByDirectory } from "./units.js";

describe("name-status parsing", () => {
  it("reads adds, modifications, deletions and renames", () => {
    const out = "M\tlib/a/src/a/x.py\nA\tlib/a/src/a/y.py\nD\tlib/a/src/a/z.py\nR087\tlib/a/src/a/old.py\tlib/a/src/a/new.py\n";
    expect(parseNameStatus(out)).toEqual([
      { status: "modified", path: "lib/a/src/a/x.py" },
      { status: "added", path: "lib/a/src/a/y.py" },
      { status: "deleted", path: "lib/a/src/a/z.py" },
      { status: "renamed", from: "lib/a/src/a/old.py", path: "lib/a/src/a/new.py" },
    ]);
  });
});

describe("modules", () => {
  it("maps src-layout paths to module names", () => {
    expect(moduleOf("lib/shellbox/src/shellbox/task.py")).toBe("shellbox.task");
    expect(moduleOf("lib/shellbox/src/shellbox/backends/__init__.py")).toBe("shellbox.backends");
    expect(moduleOf("lib/shellbox/tests/test_task.py")).toBe("tests.test_task");
    expect(moduleOf("README.md")).toBeNull();
    expect(packageName("lib/iris/src/iris/actor")).toBe("iris");
  });

  it("names modules outside lib/ from the repository root, and classes test files and packages", () => {
    expect(moduleOf("experiments/grug/base.py")).toBe("experiments.grug.base");
    expect(moduleOf("scripts/iris/__init__.py")).toBe("scripts.iris");
    expect(contextPackage("lib/iris/src/iris/actor/client.py")).toBe("iris");
    expect(contextPackage("experiments/grug/base.py")).toBe("experiments");
    expect(contextPackage("tests/execution/test_x.py")).toBe("tests");
    for (const p of ["lib/a/tests/x.py", "tests/foo.py", "lib/a/src/a/test_b.py", "lib/a/src/a/b_test.py", "lib/a/conftest.py"]) expect(isTestPath(p)).toBe(true);
    for (const p of ["lib/a/src/a/testing/util.py", "lib/a/src/a/contest.py", "experiments/attest.py"]) expect(isTestPath(p)).toBe(false);
  });

  it("resolves a module name two packages share to the importer's own, and counts imported names", () => {
    const idx = new ModuleIndex(["lib/a/tests/conftest.py", "lib/b/tests/conftest.py", "lib/s/src/s/__init__.py", "lib/s/src/s/task.py"]);
    expect(idx.resolve({ module: "tests.conftest", names: ["fx"] }, "lib/b/tests/test_y.py")).toEqual(["lib/b/tests/conftest.py"]);
    expect(idx.resolve({ module: "tests.conftest", names: ["fx"] }, "lib/a/tests/test_y.py")).toEqual(["lib/a/tests/conftest.py"]);
    expect([...idx.resolveNames({ module: "s", names: ["task", "A", "B"] })]).toEqual([
      ["lib/s/src/s/task.py", 1],
      ["lib/s/src/s/__init__.py", 2],
    ]);
    expect([...idx.resolveNames({ module: "s.task", names: [] })]).toEqual([["lib/s/src/s/task.py", 1]]);
  });

  it("parses absolute and relative imports", () => {
    expect(parseImport("lib/s/src/s/a/b.py", "from shellbox.task import TaskSpec, Task as T")).toEqual({ module: "shellbox.task", names: ["TaskSpec", "Task"] });
    expect(parseImport("lib/s/src/s/a/b.py", "from .c import d")).toEqual({ module: "s.a.c", names: ["d"] });
    expect(parseImport("lib/s/src/s/a/b.py", "from .. import machine")).toEqual({ module: "s", names: ["machine"] });
    expect(parseImport("lib/s/src/s/a/__init__.py", "from .b import x")).toEqual({ module: "s.a.b", names: ["x"] });
    expect(parseImport("lib/s/src/s/a.py", "import os.path, sys")).toEqual({ module: "os.path", names: [] });
    expect(parseImport("lib/s/src/s/a.py", "from x import (")).toEqual({ module: "x", names: [] });
  });

  it("resolves an import to submodules, or to the longest known prefix", () => {
    const idx = new ModuleIndex(["lib/s/src/s/__init__.py", "lib/s/src/s/machine.py", "lib/s/src/s/task.py"]);
    expect(idx.resolve({ module: "s", names: ["machine", "task"] })).toEqual(["lib/s/src/s/machine.py", "lib/s/src/s/task.py"]);
    expect(idx.resolve({ module: "s.task", names: ["TaskSpec"] })).toEqual(["lib/s/src/s/task.py"]);
    expect(idx.resolve({ module: "s.task.inner", names: [] })).toEqual(["lib/s/src/s/task.py"]);
    expect(idx.resolve({ module: "numpy", names: ["array"] })).toEqual([]);
  });

  it("lists module-level and method signatures, skipping dunders other than __init__", () => {
    const src = "import x\n\nclass A(B):\n    def __init__(self, a):\n        pass\n    def __repr__(self):\n        pass\n    async def run(self) -> None:\n        def inner():\n            pass\n\ndef f(x: int) -> int:\n    return x\n";
    expect(signatures(src)).toEqual(["class A(B):", "    def __init__(self, a):", "    async def run(self) -> None:", "def f(x: int) -> int:"]);
  });
});

describe("units", () => {
  it("groups changed files by directory", () => {
    const units = groupByDirectory(["lib/a/src/a/x.py", "lib/b/src/b/y.py", "lib/a/src/a/w.py"], "abc");
    expect(units.map((u) => [u.dir, u.package, u.targets])).toEqual([
      ["lib/a/src/a", "a", ["lib/a/src/a/w.py", "lib/a/src/a/x.py"]],
      ["lib/b/src/b", "b", ["lib/b/src/b/y.py"]],
    ]);
  });
});
