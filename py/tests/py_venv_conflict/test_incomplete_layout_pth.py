import sys


complete_count = sys.path.count("rules_py_pth_complete")
incomplete_count = sys.path.count("rules_py_pth_incomplete")

assert complete_count > 0, "complete-layout root .pth did not execute"
assert incomplete_count > 0, "incomplete-layout root .pth did not execute"
assert incomplete_count == complete_count, (
    "incomplete layout projected and rescanned its root .pth",
    complete_count,
    incomplete_count,
)
