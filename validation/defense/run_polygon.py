"""Lua 5.4 rule and UI-stub regressions; does not launch or remotely build."""
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE / "python-deps"))
from lupa.lua54 import LuaRuntime, lua_type

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('package.path = ... .. "/scripts/?.lua;" .. ... .. "/?.lua;" .. package.path', ROOT.as_posix(), ROOT.as_posix())
syntax = {}
for path in sorted((ROOT / "scripts" / "defense").rglob("*.lua")):
    lua.execute("assert(load(...))", path.read_text(encoding="utf-8-sig"))
    syntax[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()

def convert(value):
    if lua_type(value) != "table":
        return value
    items = list(value.items())
    if items and all(isinstance(k, int) for k, _ in items):
        return [convert(value[i]) for i in range(1, len(items) + 1)]
    return {str(k): convert(v) for k, v in items}

report = convert(lua.execute('return require("defense.Tests").Run(...)', sys.argv[1] if len(sys.argv) > 1 else None))
report["lua"] = lua.eval("_VERSION")
report["source_sha256"] = syntax
report["evidence_boundary"] = "Lua rules and UI stubs only; engine graphics, audio, FPS and human playtest unverified."
output = HERE / "polygon-20261012"
output.mkdir(exist_ok=True)
name = sys.argv[2] if len(sys.argv) > 2 else "regression"
(output / (name + ".json")).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({k: report[k] for k in ("passed", "failed", "not_run", "lua")}, ensure_ascii=False))
sys.exit(1 if report["failed"] else 0)
