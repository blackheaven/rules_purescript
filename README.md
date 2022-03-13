Purescript Rules for Bazel
==========================

Adding purescript support to your bazel repo
--------------------------------------------
This repo is the beginnings of support for purescript in Bazel. In order to use
this put the following into your `WORKSPACE` file:

```python
# refer to a githash in this repo:
rules_purescript_version = "3767546058a856684ed68f45eafd387ca0d0896e"

# download the archive:
http_archive(
    name = "io_bazel_rules_purescript",
    url  = "https://github.com/bleackheaven/rules_purescript/archive/%s.zip" % rules_purescript_version,
    type = "zip",
    strip_prefix = "rules_purescript-%s" % rules_purescript_version,
)

# load the purescript rules and functions:
load("@io_bazel_rules_purescript//purescript:purescript.bzl", "purescript_toolchain", "purescript_dep")

# downloads the `purs` command:
purescript_toolchain()

# add some dependencies:
purescript_dep(
    name = "purescript_console",
    url = "https://github.com/purescript/purescript-console/archive/v5.0.0.tar.gz",
    sha256 = "821f35010385f68d731b250d205f1389ca9acfc36bfa9cfbd83394136c1a76b0",
    strip_prefix = "purescript-console-5.0.0",
)

purescript_dep(
    name = "purescript_effect",
    url = "https://github.com/purescript/purescript-effect/archive/v3.0.0.tar.gz",
    sha256 = "51383e9356968197a5f29a5ac545e8261c1a64016167a85b7aca29760b694882",
    strip_prefix = "purescript-effect-3.0.0",
)

purescript_dep(
    name = "purescript_prelude",
    url = "https://github.com/purescript/purescript-prelude/archive/v5.0.1.tar.gz",
    sha256 = "438839a7e679a996f3e6c59b5280066893bf2bdb592ccd581b084f413a6310dd",
    strip_prefix = "purescript-prelude-5.0.1",
)
```

Defining a project
------------------
With this in place you can now define a `BUILD` file for your project:

```python
load("@io_bazel_rules_purescript//purescript:purescript.bzl", "purescript_app", "purescript_test")

dependencies = \
    [ "@purescript_console//:pkg"
    , "@purescript_effect//:pkg"
    , "@purescript_prelude//:pkg"
    ]

# Defines an application with default entrypoint (Main.main):
purescript_app(
    name       = "purs-app",
    visibility = ["//visibility:public"],
    srcs       = glob(["src/**/*.purs"]),
    deps       = dependencies,
)
```


You can now build your program and run the main function!

If you want to customize the entrypoint, you can do something like:

```python
purescript_app(
    name             = "purs-app",
    visibility       = ["//visibility:public"],
    srcs             = glob(["src/**/*.purs"]),
    deps             = dependencies,
    entry_module     = "MyModule",
    entry_function   = "myFunction",
    entry_parameters = [ "my", "parameters" ],
)
```

### Depending on other Bazel Purescript Projects
Currently this is as simple as adding the label to your project's dependencies.
There's a known issue with the way this is currently implemented. Files with
the same name will overwrite each other. This is detailed in
[#4](https://github.com/felixmulder/rules_purescript/issues/4).

Example of depending on other bazel purescript project:

```python
purescript_app(
    name             = "purs-app",
    visibility       = ["//visibility:public"],
    srcs             = glob(["src/**/*.purs"]),
    deps             = [ "//lib:purs-lib" ] + dependencies,
)
```

Testing
-------
In the same `BUILD` file, you can define a test module:
```python
purescript_test(
    name = "purs-app-test",
    srcs = glob(["test/**/*.purs"]) + glob(["src/**/*.purs"]),
    deps = dependencies,
)
```

in the `test` directory I've created a module like:

```purescript
module Test.Main where

-- imports omitted

main :: Effect Unit
main = log "Hello test world!"
```

when you run `bazel test` on the `:purs-app-test` project, it should succeed
:tada:

**NOTE:** the default entrypoint for testing is the module `Test.Main` and the
function `main`. But these can be overwritten:

```python
purescript_test(
    name          = "purs-app-test",
    srcs          = glob(["test/**/*.purs"]) + glob(["src/**/*.purs"]),
    deps          = dependencies,
    main_module   = "MyMainTest.Whatever"
    main_function = "myFun"
)
```
