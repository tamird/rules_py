
load("@rules_python//python:pip.bzl", "pip_utils")

def _requirement(name):
    return "@@aspect_rules_py++uv+pypi_single//{0}:pkg".format(name)

def requirement(name):
    return _requirement(pip_utils.normalize_name(name))

all_requirements = [_requirement(name) for name in ["cowsay", "single_project_hub"]]

all_requirements_by_dep_group = {
    dep_group: [_requirement(name) for name in names]
    for dep_group, names in {"single_project_hub": ["cowsay", "single_project_hub"]}.items()
}

all_whl_requirements_by_package = {"cowsay": "@@aspect_rules_py++uv+pypi_single//cowsay:whl", "single_project_hub": "@@aspect_rules_py++uv+pypi_single//single_project_hub:whl"}

all_whl_requirements = all_whl_requirements_by_package.values()

all_data_requirements = all_requirements
