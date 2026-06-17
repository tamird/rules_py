"""Resolve modules under configured Bazel runfiles-manifest import roots.

This import hook is not a general virtual runfiles filesystem. It supports
module imports and discovery plus regular-package resources. Manifest-only
namespace packages remain loaderless so Python can combine their portions;
they cannot expose package resources. Unrelated runtime data should be located
through Bazel's runfiles API.
"""

from __future__ import annotations

import importlib.abc
import importlib.machinery
import importlib.util
import inspect
import ntpath
import os
import posixpath
import sys
from collections.abc import Iterable, Mapping, Sequence

try:
    from importlib.resources.abc import Traversable, TraversableResources
except ImportError:
    from importlib.abc import Traversable, TraversableResources


_PATH_PREFIX = "rules-py-runfiles:"
_MANIFEST_ONLY_PREFIX = "manifest-only:"
_PATH_FINDERS: dict[str, _ManifestPathFinder] = {}
# Stable root paths make repeated initialization idempotent.
_ROOT_PATHS: dict[str, str] = {}


def _unescape(value: str, *, escape_spaces: bool) -> str:
    if escape_spaces:
        value = value.replace(r"\s", " ")
    return value.replace(r"\n", "\n").replace(r"\b", "\\")


def _parse_manifest_line(line: str) -> tuple[str, str]:
    # Keep this in sync with rules_python's canonical manifest parser:
    # https://github.com/bazelbuild/rules_python/blob/d24691f0a7891136cf338f12480c33ad33ca39e4/python/runfiles/runfiles.py#L169-L192
    line = line.rstrip("\r\n")
    if line.startswith(" "):
        link, target = line[1:].split(" ", 1)
        return (
            _unescape(link, escape_spaces=True),
            _unescape(target, escape_spaces=False),
        )
    fields = line.split(" ", 1)
    return fields[0], fields[1] if len(fields) == 2 and fields[1] else fields[0]


def _runfiles_dir(environ: Mapping[str, str]) -> str | None:
    if environ.get("RUNFILES_MANIFEST_ONLY") == "1":
        return None
    runfiles_dir = environ.get("RUNFILES_DIR")
    if runfiles_dir and os.path.isdir(runfiles_dir):
        return runfiles_dir
    manifest = environ.get("RUNFILES_MANIFEST_FILE")
    if not manifest:
        return None
    if manifest.endswith(".runfiles_manifest"):
        candidate = manifest[: -len("_manifest")]
    elif manifest.endswith(".runfiles/MANIFEST"):
        candidate = os.path.dirname(manifest)
    else:
        return None
    return candidate if os.path.isdir(candidate) else None


class _ManifestGroup:
    def __init__(self) -> None:
        self.entries: dict[str, str] = {}
        self.directories: set[str] = set()
        self.children_by_directory: dict[str, set[str]] = {}
        self.path_entries: dict[str, str] = {}
        self.root_mapping_prefix = -1

    def add_entry(self, relative: str, target: str) -> None:
        self.entries[relative] = target
        descendant = relative
        while descendant:
            directory = posixpath.dirname(descendant)
            self.children_by_directory.setdefault(directory, set()).add(
                posixpath.basename(descendant)
            )
            if directory:
                self.directories.add(directory)
            descendant = directory

    def prefixed_path(self, relative: str) -> str | None:
        prefix = posixpath.dirname(relative)
        while True:
            if target := self.entries.get(prefix):
                suffix = relative[len(prefix) :].lstrip("/")
                return os.path.join(target, suffix.replace("/", os.sep))
            if not prefix:
                return None
            prefix = posixpath.dirname(prefix)

    def resolve(self, relative: str) -> str | None:
        target = self.entries.get(relative)
        return target if target is not None else self.prefixed_path(relative)

    def is_dir(self, relative: str) -> bool:
        target = self.resolve(relative)
        return relative in self.directories or (
            target is not None and os.path.isdir(target)
        )

    def is_file(self, relative: str) -> bool:
        target = self.resolve(relative)
        return target is not None and os.path.isfile(target)

    def children(self, relative: str) -> list[str]:
        children = set(self.children_by_directory.get(relative, ()))
        target = self.resolve(relative)
        if target is not None and os.path.isdir(target):
            try:
                children.update(os.listdir(target))
            except OSError:
                pass
        return sorted(children)


def _normalize_resource_path(path: str | os.PathLike[str]) -> str:
    path = os.fspath(path)
    if not isinstance(path, str):
        raise TypeError("resource paths must be strings")
    if (
        posixpath.isabs(path) or ntpath.isabs(path) or ntpath.splitdrive(path)[0]
    ):
        raise ValueError("resource path must stay within its package: {!r}".format(path))
    path = path.replace("\\", "/")
    if ".." in path.split("/"):
        raise ValueError("resource path must stay within its package: {!r}".format(path))
    return posixpath.normpath(path) if path else path


class _ManifestTraversable(Traversable):
    def __init__(self, group: _ManifestGroup, relative: str) -> None:
        self._group = group
        self._relative = _normalize_resource_path(relative)

    @property
    def name(self) -> str:
        return posixpath.basename(self._relative)

    def iterdir(self) -> Iterable[_ManifestTraversable]:
        if not self.is_dir():
            raise NotADirectoryError(self._relative)
        return (
            type(self)(self._group, posixpath.join(self._relative, child))
            for child in self._group.children(self._relative)
        )

    def is_dir(self) -> bool:
        return self._group.is_dir(self._relative)

    def is_file(self) -> bool:
        return self._group.is_file(self._relative)

    def joinpath(
        self,
        *descendants: str | os.PathLike[str],
    ) -> _ManifestTraversable:
        relative = self._relative
        for descendant in descendants:
            descendant = _normalize_resource_path(descendant)
            relative = posixpath.join(relative, descendant)
        return type(self)(self._group, relative)

    def __truediv__(
        self,
        child: str | os.PathLike[str],
    ) -> _ManifestTraversable:
        return self.joinpath(child)

    def read_bytes(self) -> bytes:
        with self.open("rb") as file:
            return file.read()

    def read_text(
        self,
        encoding: str | None = None,
        errors: str | None = None,
    ) -> str:
        with self.open("r", encoding=encoding, errors=errors) as file:
            return file.read()

    def open(self, mode: str = "r", *args: object, **kwargs: object):
        if mode not in ("r", "rb"):
            raise ValueError("resources are read-only")
        target = self._group.resolve(self._relative)
        if target is None or not os.path.isfile(target):
            raise FileNotFoundError(self._relative)
        return open(target, mode, *args, **kwargs)


class _ManifestResourceReader(TraversableResources):
    def __init__(self, group: _ManifestGroup, package_relative: str) -> None:
        self._root = _ManifestTraversable(group, package_relative)

    def files(self) -> _ManifestTraversable:
        return self._root

    def resource_path(self, resource: str) -> str:
        traversable = self._root.joinpath(resource)
        target = traversable._group.resolve(traversable._relative)
        if target is None or not os.path.isfile(target):
            raise FileNotFoundError(resource)
        return target

    def is_resource(self, path: str) -> bool:
        return self._root.joinpath(path).is_file()


class _ManifestPackageLoaderMixin:
    def __init__(
        self,
        fullname: str,
        path: str,
        group: _ManifestGroup,
        package_relative: str,
    ) -> None:
        super().__init__(fullname, path)
        self._manifest_group = group
        self._package_relative = package_relative
        self._package_directory = os.path.dirname(path)

    def get_resource_reader(self, fullname: str) -> _ManifestResourceReader | None:
        if fullname != self.name:
            return None
        return _ManifestResourceReader(
            self._manifest_group,
            self._package_relative,
        )

    def get_data(self, path: str) -> bytes:
        try:
            inside_package = os.path.commonpath(
                (self._package_directory, path)
            ) == os.path.commonpath((self._package_directory,))
        except ValueError:
            inside_package = False
        if not inside_package:
            parent_get_data = getattr(super(), "get_data", None)
            if parent_get_data is None:
                raise FileNotFoundError(path)
            return parent_get_data(path)

        resource = _normalize_resource_path(
            os.path.relpath(path, self._package_directory)
        )
        relative = posixpath.join(self._package_relative, resource)
        target = self._manifest_group.resolve(relative)
        if target is None or not os.path.isfile(target):
            raise FileNotFoundError(path)
        with open(target, "rb") as file:
            return file.read()


class _ManifestSourceFileLoader(
    _ManifestPackageLoaderMixin,
    importlib.machinery.SourceFileLoader,
):
    pass


class _ManifestSourcelessFileLoader(
    _ManifestPackageLoaderMixin,
    importlib.machinery.SourcelessFileLoader,
):
    pass


class _ManifestExtensionFileLoader(
    _ManifestPackageLoaderMixin,
    importlib.machinery.ExtensionFileLoader,
):
    pass


def _manifest_groups(path: str, roots: Sequence[str]) -> dict[str, _ManifestGroup]:
    roots = list(dict.fromkeys(roots))
    groups = {root: _ManifestGroup() for root in roots}
    roots_by_repo: dict[str, list[str]] = {}
    for root in roots:
        roots_by_repo.setdefault(root.split("/", 1)[0], []).append(root)

    with open(path, encoding="utf-8", newline="\n") as manifest:
        for line in manifest:
            link, target = _parse_manifest_line(line)
            for logical in roots_by_repo.get(link.split("/", 1)[0], ()):
                group = groups[logical]
                if link == logical:
                    group.add_entry("", target)
                    group.root_mapping_prefix = len(link)
                elif link.startswith(logical + "/"):
                    relative = link[len(logical) + 1 :]
                    group.add_entry(relative, target)
                elif (
                    logical.startswith(link + "/")
                    and len(link) > group.root_mapping_prefix
                ):
                    group.add_entry(
                        "",
                        os.path.join(
                            target,
                            logical[len(link) + 1 :].replace("/", os.sep),
                        ),
                    )
                    group.root_mapping_prefix = len(link)
    return groups


_MODULE_LOADERS = tuple(
    (suffix, importlib.machinery.ExtensionFileLoader)
    for suffix in importlib.machinery.EXTENSION_SUFFIXES
) + tuple(
    (suffix, importlib.machinery.SourceFileLoader)
    for suffix in importlib.machinery.SOURCE_SUFFIXES
) + tuple(
    (suffix, importlib.machinery.SourcelessFileLoader)
    for suffix in importlib.machinery.BYTECODE_SUFFIXES
)
_PACKAGE_LOADERS = {
    importlib.machinery.ExtensionFileLoader: _ManifestExtensionFileLoader,
    importlib.machinery.SourceFileLoader: _ManifestSourceFileLoader,
    importlib.machinery.SourcelessFileLoader: _ManifestSourcelessFileLoader,
}


# A manifest can map one logical import root to unrelated physical trees. Keep
# that root as one path entry so generated children remain visible after Python
# finds a regular package's __init__.py:
# https://docs.python.org/3/reference/import.html#path-entry-finder-protocol
class _ManifestPathFinder(importlib.abc.PathEntryFinder):
    def __init__(self, group: _ManifestGroup, relative: str = "") -> None:
        self._group = group
        self._relative = relative

    def find_spec(
        self,
        fullname: str,
        target: object | None = None,
    ) -> importlib.machinery.ModuleSpec | None:
        del target
        leaf = fullname.rsplit(".", 1)[-1]
        relative = posixpath.join(self._relative, leaf)
        for module_relative, is_package in (
            (relative + "/__init__", True),
            (relative, False),
        ):
            for suffix, loader_type in _MODULE_LOADERS:
                file_relative = module_relative + suffix
                # Match RlocationChecked: exact entries precede the longest
                # enclosing directory entry.
                # https://github.com/bazelbuild/rules_python/blob/d24691f0a7891136cf338f12480c33ad33ca39e4/python/runfiles/runfiles.py#L148-L164
                file_target = self._group.resolve(file_relative)
                if file_target is None or not self._group.is_file(file_relative):
                    continue
                locations = (
                    [_register_finder(type(self)(self._group, relative))]
                    if is_package
                    else None
                )
                loader = (
                    _PACKAGE_LOADERS[loader_type](
                        fullname,
                        file_target,
                        self._group,
                        relative,
                    )
                    if is_package
                    else loader_type(fullname, file_target)
                )
                return importlib.util.spec_from_file_location(
                    fullname,
                    file_target,
                    loader=loader,
                    submodule_search_locations=locations,
                )

        if self._group.is_dir(relative):
            # Keep loader=None so PathFinder can combine namespace portions
            # from multiple path entries. CPython's namespace resource reader
            # only accepts physical directories, so manifest-only namespace
            # packages cannot expose importlib.resources:
            # https://github.com/python/cpython/blob/v3.12.13/Lib/importlib/resources/readers.py#L131-L146
            spec = importlib.machinery.ModuleSpec(fullname, loader=None, is_package=True)
            spec.submodule_search_locations = [
                _register_finder(type(self)(self._group, relative))
            ]
            return spec
        return None

    def iter_modules(self, prefix: str = "") -> Iterable[tuple[str, bool]]:
        # Match FileFinder: sorted names put a package before its same-named
        # module, and a yielded set suppresses the module that follows.
        # https://github.com/python/cpython/blob/3bb231a6a5dc02b95658877318bf61501a7209e9/Lib/pkgutil.py#L100-L171
        yielded: set[str] = set()
        for child in self._group.children(self._relative):
            module_name = inspect.getmodulename(child)
            if module_name == "__init__" or module_name in yielded:
                continue

            relative = posixpath.join(self._relative, child)
            is_package = False
            if (
                module_name is None
                and "." not in child
                and self._group.is_dir(relative)
            ):
                for suffix, _ in _MODULE_LOADERS:
                    if self._group.is_file(
                        posixpath.join(relative, "__init__" + suffix)
                    ):
                        module_name = child
                        is_package = True
                        break
                else:
                    # Keep bare namespace directories out of pkgutil results.
                    continue

            if (
                module_name is not None
                and "." not in module_name
                and (is_package or self._group.is_file(relative))
            ):
                yielded.add(module_name)
                yield prefix + module_name, is_package


def _manifest_path_hook(path: str) -> _ManifestPathFinder:
    try:
        return _PATH_FINDERS[path]
    except KeyError as error:
        raise ImportError(path) from error


def _register_finder(finder: _ManifestPathFinder) -> str:
    if path := finder._group.path_entries.get(finder._relative):
        return path
    path = _PATH_PREFIX + str(len(_PATH_FINDERS))
    _PATH_FINDERS[path] = finder
    finder._group.path_entries[finder._relative] = path
    sys.path_importer_cache.pop(path, None)
    return path


def _install_manifest_groups(groups: Mapping[str, _ManifestGroup]) -> dict[str, str]:
    # Path hooks are Python's supported interface for non-filesystem sys.path
    # entries: https://docs.python.org/3/library/sys.html#sys.path_hooks
    if _manifest_path_hook not in sys.path_hooks:
        sys.path_hooks.insert(0, _manifest_path_hook)
    paths: dict[str, str] = {}
    for logical, group in groups.items():
        path = _ROOT_PATHS.get(logical)
        if not group.entries:
            if path is not None:
                _PATH_FINDERS[path] = _ManifestPathFinder(group)
                sys.path_importer_cache.pop(path, None)
            continue
        if path is None:
            path = _register_finder(_ManifestPathFinder(group))
            _ROOT_PATHS[logical] = path
        else:
            _PATH_FINDERS[path] = _ManifestPathFinder(group)
            group.path_entries[""] = path
            sys.path_importer_cache.pop(path, None)
        paths[logical] = path
    return paths


def _resolve_roots(
    roots: Sequence[str],
    fallback_runfiles: str,
    *,
    environ: Mapping[str, str] | None = None,
    prefix: str | None = None,
) -> dict[str, str]:
    environ = os.environ if environ is None else environ
    prefix = sys.prefix if prefix is None else prefix
    resolved: dict[str, str] = {}
    runfiles_dir = _runfiles_dir(environ)
    for logical in dict.fromkeys(roots):
        if runfiles_dir:
            candidate = os.path.join(runfiles_dir, logical.replace("/", os.sep))
        else:
            candidate = os.path.normpath(
                os.path.join(prefix, fallback_runfiles, logical.replace("/", os.sep))
            )
        if os.path.isdir(candidate):
            resolved[logical] = candidate
    return resolved


def initialize() -> None:
    config = os.path.splitext(__file__)[0] + ".txt"
    with open(config, encoding="utf-8") as file:
        fallback_runfiles, *configured_roots = file.read().splitlines()
    manifest_only_roots = {
        entry[len(_MANIFEST_ONLY_PREFIX) :]
        for entry in configured_roots
        if entry.startswith(_MANIFEST_ONLY_PREFIX)
    }
    roots = list(
        dict.fromkeys(
            entry[len(_MANIFEST_ONLY_PREFIX) :]
            if entry.startswith(_MANIFEST_ONLY_PREFIX)
            else entry
            for entry in configured_roots
        )
    )

    manifest_paths: dict[str, str] = {}
    manifest_groups: dict[str, _ManifestGroup] = {}
    manifest = os.environ.get("RUNFILES_MANIFEST_FILE")
    if _runfiles_dir(os.environ) is None and manifest and os.path.isfile(manifest):
        manifest_groups = _manifest_groups(manifest, roots)
        manifest_paths = _install_manifest_groups(manifest_groups)

    physical_paths = _resolve_roots(
        [
            root
            for root in roots
            if root not in manifest_paths and root not in manifest_only_roots
        ],
        fallback_runfiles,
    )
    paths = [
        manifest_paths[root] if root in manifest_paths else physical_paths[root]
        for root in roots
        if root in manifest_paths or root in physical_paths
    ]
    known = {
        path if path.startswith(_PATH_PREFIX) else os.path.normcase(os.path.abspath(path))
        for path in sys.path
        if path
    }
    for path in paths:
        key = path if path.startswith(_PATH_PREFIX) else os.path.normcase(os.path.abspath(path))
        if key not in known:
            sys.path.append(path)
            known.add(key)
