"""Helpers for classifying source-build attributes."""

def active_build_only_attrs(
        resource_set,
        env,
        pre_build_patches,
        pre_build_patch_strip,
        toolchains):
    """Returns the names of configured source-build attributes.

    Args:
        resource_set: Resource set name, where "default" means unset.
        env: Environment variables for the wheel-build action.
        pre_build_patches: Patches applied before building the wheel.
        pre_build_patch_strip: Strip count for pre-build patches.
        toolchains: Toolchains used by the wheel-build action.

    Returns:
        A list of configured attribute names.
    """
    active = []
    if resource_set != "default":
        active.append("resource_set")
    if env:
        active.append("env")
    if pre_build_patches:
        active.append("pre_build_patches")
    if pre_build_patch_strip:
        active.append("pre_build_patch_strip")
    if toolchains:
        active.append("toolchains")
    return active
