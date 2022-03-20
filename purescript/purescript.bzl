"""Rules for purescript"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

run_template = """
#!/usr/bin/env bash
set -o errexit

node -e "require('./{target_path}/{entry_module}/index.js').{entry_function}({entry_params})"
"""

compile_trans_template = "cp -R {path}/* {output}"

def _purescript_compile(ctx):
    srcs = ctx.files.srcs + ctx.files.deps
    target = ctx.actions.declare_file(ctx.outputs.target.basename)
    purs = ctx.executable.purs
    flags = " ".join(ctx.attr.compiler_flags)

    bazel_ps_deps = []
    for d in ctx.attr.deps:
        for f in d.files.to_list():
            if f.basename == "target_srcs":
                bazel_ps_deps = [f.path + "/**/*.purs"] + bazel_ps_deps

    compileCmd = "\n".join(
        [ "set -o errexit"
        , """mkdir "$2" """
        , """ "$1" compile """ + flags + """ --output "$2" "${@:3}" """
        ]
    )

    ctx.actions.run_shell(
        tools = srcs + [purs],
        outputs = [target],
        command = compileCmd,
        arguments = [purs.path, target.path] +
                    [src.path for src in srcs if src.extension == "purs"] +
                    bazel_ps_deps,
    )

    # TODO -- this will currently break if files have the same names, so --
    #         gotta fix that somehow
    cpSrcsCmd = "\n".join(
        [ "set -o errexit"
        , """mkdir -p "$1" """
        , """cp "${@:2}" "$1" """
        ]
    )

    target_srcs = ctx.actions.declare_file(ctx.outputs.target_srcs.basename)

    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [target_srcs],
        command = cpSrcsCmd,
        arguments = [target_srcs.path] + [src.path for src in ctx.files.srcs],
    )

    return target

def _purescript_tar(ctx):
    target = _purescript_compile(ctx)
    tar = ctx.actions.declare_file(ctx.outputs.tar.basename)
    ctx.actions.run_shell(
        inputs = [target],
        outputs = [tar],
        command = """
            set -o errexit
            tar --create --file "$1" --directory "$2" .
        """,
        arguments = [tar.path, target.path],
    )

def _purescript_app(ctx):
    target = _purescript_compile(ctx)

    entry_params = ",".join([
        '\\"{entry}\\"'.format(entry=e) for e in ctx.attr.entry_parameters
    ])

    script = ctx.actions.declare_file(ctx.label.name)
    script_content = run_template.format(
        target_path    = target.short_path,
        entry_module   = getattr(ctx.attr, "entry_module"),
        entry_function = getattr(ctx.attr, "entry_function"),
        entry_params   = entry_params,
    )
    ctx.actions.write(script, script_content, is_executable = True)

    runfiles = ctx.runfiles(files = [target])

    return [DefaultInfo(executable = script, runfiles = runfiles)]

purescript_app = rule(
    implementation = _purescript_app,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "deps": attr.label_list(
            default = [],
        ),
        "purs": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "host",
            default = "@purs",
        ),
        "compiler_flags": attr.string_list(
            default = []
        ),
        "entry_module": attr.string(
            default = "Main",
        ),
        "entry_function": attr.string(
            default = "main",
        ),
        "entry_parameters": attr.string_list(
            default = [],
        ),
    },
    outputs = {
        "target": "target",
        "target_srcs": "target_srcs",
    },
    executable = True,
)

def _purescript_lib(ctx):
    _purescript_compile(ctx)

purescript_lib = rule(
    implementation = _purescript_lib,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "deps": attr.label_list(
            default = [],
        ),
        "purs": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "host",
            default = "@purs",
        ),
        "compiler_flags": attr.string_list(
            default = []
        ),
    },
    outputs = {
        #"tar": "%{name}.tar",
        "target": "target",
        "target_srcs": "target_srcs",
    },
)

test_template = """
err=0
node -e "require('./{target_path}/{test_file}/index.js').{entry_function}()" || err=1
echo
"""

def _run_test(target_path, entry_module, entry_function):
    return test_template.format(
        target_path = target_path,
        test_file = entry_module,
        entry_function = entry_function,
    )

def _purescript_test(ctx):
    target = _purescript_compile(ctx)

    script = "\n".join(
        ["""
#!/usr/bin/env bash
err=0
"""     , _run_test(target.short_path, ctx.attr.main_module, ctx.attr.main_function)
        , "exit $err"
        ],
    )
    ctx.actions.write(
        output = ctx.outputs.executable,
        content = script,
    )

    runfiles = ctx.runfiles(files = [target])
    return [DefaultInfo(runfiles = runfiles)]

purescript_test = rule(
    implementation = _purescript_test,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "main_module": attr.string(
            default = "Test.Main",
        ),
        "main_function": attr.string(
            default = "main",
        ),
        "purs": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "host",
            default = "@purs",
        ),
        "compiler_flags": attr.string_list(
            default = []
        ),
    },
    outputs = {
        "target": "test-target",
        "target_srcs": "target_srcs",
    },
    test = True,
)

_PURS_DISTROS = {
    "linux_amd64": struct(
        url    = "https://github.com/purescript/purescript/releases/download/v0.14.7/linux64.tar.gz",
        sha256 = "cae16a0017c63fd83e029ca5a01cb9fc02cacdbd805b1d2b248f9bb3c3ea926d",
    ),
    "macos_amd64": struct(
        url    = "https://github.com/purescript/purescript/releases/download/v0.14.7/macos.tar.gz",
        sha256 = "2ca3e859b6f44760dfc39aed2c8ffe65da9396d436b34c808f4f1e58763f805d",
    ),
}
def _get_platform(repository_ctx):
    os_name = repository_ctx.os.name.lower()
    if os_name.startswith("linux"):
        return "linux_amd64"
    elif os_name.startswith("mac os"):
        return "macos_amd64"
    else:
        fail("Unknown OS: '{}'".format(os_name))

def _purescript_toolchain_impl(repository_ctx):
    distro = _PURS_DISTROS[_get_platform(repository_ctx)]
    repository_ctx.download_and_extract(
        url = distro.url,
        sha256 = distro.sha256,
        stripPrefix = "purescript",
    )
    repository_ctx.file(
        "BUILD.bazel",
        content = """exports_files(["purs"])""",
    )

_purescript_toolchain = repository_rule(
    _purescript_toolchain_impl,
    configure = True,
    environ = ["PATH"],
)

def purescript_toolchain():
    _purescript_toolchain(name = "purs")

_purescript_dep_build_content = """
filegroup(
    name = "pkg",
    srcs = glob(["src/**/*.purs", "src/**/*.js"]),
    visibility = ["//visibility:public"],
)
"""

def purescript_dep(name, url, sha256, strip_prefix):
    http_archive(
        name               = name,
        urls               = [url],
        sha256             = sha256,
        strip_prefix       = strip_prefix,
        build_file_content = _purescript_dep_build_content,
    )
