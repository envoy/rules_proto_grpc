load("//:plugin.bzl", "ProtoPluginInfo")
load(
    "//:common.bzl",
    "ProtoCompileInfo",
    _apply_plugin_transitivity_rules = "apply_plugin_transitivity_rules",
    _capitalize = "capitalize",
    _copy_jar_to_srcjar = "copy_jar_to_srcjar",
    "get_int_attr",
    _get_output_filename = "get_output_filename",
    _get_output_sibling_file = "get_output_sibling_file",
    _get_plugin_option = "get_plugin_option",
    _get_plugin_options = "get_plugin_options",
    _get_plugin_out = "get_plugin_out",
    "get_plugin_runfiles",
    _get_proto_filename = "get_proto_filename",
    "get_string_list_attr",
    _pascal_case = "pascal_case",
    _pascal_objc = "pascal_objc",
    _proto_path = "proto_path",
    _rust_keyword = "rust_keyword",
)


def get_plugin_out_arg(ctx, outdir, plugin, plugin_outfiles, plugin_options):
    """Build the --java_out argument
    Args:
      ctx: the <ctx> object
      output: the package output directory <string>
      plugin: the <PluginInfo> object.
      plugin_outfiles: The <dict<string,<File>>.  For example, {closure: "library.js"}
    Returns
      <string> for the protoc arg list.
    """
    label_name = ctx.label.name
    arg = "%s/%s" % (ctx.bin_dir.path, ctx.label.workspace_root)

    # Works for rust but not python!
    #if ctx.label.package:
    #    arg += "/" + ctx.label.package

    # Graveyard of failed attempts (above)....
    # arg = "%s/%s" % (ctx.bin_dir.path, ctx.label.package)
    # arg = ctx.bin_dir.path
    # arg = ctx.label.workspace_root
    # arg = ctx.build_file_path
    # arg = "."

    if plugin.outdir:
        arg = plugin.outdir.replace("{name}", outdir)
    elif plugin.out:
        outfile = plugin_outfiles[plugin.name]

        #arg = "%s" % (outdir)
        #arg = "%s/%s" % (outdir, outfile.short_path)
        arg = outfile.path

    # Collate a list of options from the plugin itself PLUS options from the
    # global plugin_options list (if they exist)
    options = getattr(plugin, "options", []) + plugin_options
    if options:
        arg = "%s:%s" % (",".join(_get_plugin_options(label_name, options)), arg)
    return "--%s_out=%s" % (plugin.name, arg)


def _get_plugin_outputs(ctx, descriptor, outputs, proto, plugin):
    """Get the predicted generated outputs for a given plugin

    Args:
      ctx: the <ctx> object
      descriptor: the descriptor <Generated File>
      outputs: the list of outputs.
      proto: the source .proto <Source File>
      plugin: the <PluginInfo> object.
    Returns:
      <list<Generated File>> the augmented list of files that will be generated
    """
    for output in plugin.outputs:
        filename = _get_output_filename(proto, plugin, output)
        if not filename:
            continue

        # sibling = _get_output_sibling_file(output, proto, descriptor)
        sibling = proto

        output = ctx.actions.declare_file(filename, sibling = sibling)

        # print("Using sibling file '%s' for '%s' => '%s'" % (sibling.path, filename, output.path))
        outputs.append(output)
    return outputs


def proto_compile_impl(ctx):
    files = []
    for dep in ctx.attr.deps:
        aspect = dep[ProtoLibraryAspectNodeInfo]
        files += aspect.outputs

    return [ProtoCompileInfo(
        label = ctx.label,
        outputs = files,
        files = files,
    ), DefaultInfo(files = depset(files))]


proto_compile_attrs = {
    # "plugins": attr.label_list(
    #     doc = "List of protoc plugins to apply",
    #     providers = [ProtoPluginInfo],
    #     mandatory = True,
    # ),
    "plugin_options": attr.string_list(
        doc = "List of additional 'global' options to add (applies to all plugins)",
    ),
    "plugin_options_string": attr.string(
        doc = "(internal) List of additional 'global' options to add (applies to all plugins)",
    ),
    "outputs": attr.output_list(
        doc = "Escape mechanism to explicitly declare files that will be generated",
    ),
    "has_services": attr.bool(
        doc = "If the proto files(s) have a service rpc, generate grpc outputs",
    ),
    # "protoc": attr.label(
    #     doc = "The protoc tool",
    #     default = "@com_google_protobuf//:protoc",
    #     cfg = "host",
    #     executable = True,
    # ),
    "verbose": attr.int(
        doc = "Increase verbose level for more debugging",
    ),
    "verbose_string": attr.string(
        doc = "Increase verbose level for more debugging",
    ),
    # "include_imports": attr.bool(
    #     doc = "Pass the --include_imports argument to the protoc_plugin",
    #     default = True,
    # ),
    # "include_source_info": attr.bool(
    #     doc = "Pass the --include_source_info argument to the protoc_plugin",
    #     default = True,
    # ),
    "transitive": attr.bool(
        doc = "Emit transitive artifacts",
    ),
    "transitivity": attr.string_dict(
        doc = "Transitive rules.  When the 'transitive' property is enabled, this string_dict can be used to exclude protos from the compilation list",
    ),
}


proto_compile_aspect_attrs = {
    "verbose_string": attr.string(
        doc = "Increase verbose level for more debugging",
        values = ["", "None", "0", "1", "2", "3", "4"],
    ),
    # "plugin_options": attr.string_list(
    #     doc = "List of additional 'global' options to add (applies to all plugins)",
    # ),
    # "outputs": attr.output_list(
    #     doc = "Escape mechanism to explicitly declare files that will be generated",
    # ),
    # "transitive": attr.bool(
    #     doc = "Emit transitive artifacts",
    # ),
    # "transitivity": attr.string_dict(
    #     doc = "Transitive rules.  When the 'transitive' property is enabled, this string_dict can be used to exclude protos from the compilation list",
    # ),
}


ProtoLibraryAspectNodeInfo = provider(
    fields = {
        "outputs": "the files generated by this aspect",
    },
)


def proto_compile_aspect_impl(target, ctx):
    # node - the proto_library rule node we're visiting
    node = ctx.rule

    # Confirm the node is a proto_library otherwise return no providers.
    if node.kind != "proto_library":
        return []

    ###
    ### Part 1: setup variables used in scope
    ###

    # <int> verbose level
    # verbose = ctx.attr.verbose
    verbose = get_int_attr(ctx.attr, "verbose_string")  # DIFFERENT

    # <File> the protoc tool
    # protoc = ctx.executable.protoc
    protoc = node.executable._proto_compiler  # DIFFERENT

    # <File> for the output descriptor.  Often used as the sibling in
    # 'declare_file' actions.
    # descriptor = ctx.outputs.descriptor
    descriptor = target.files.to_list()[0]  # DIFFERENT

    # <string> The directory where that generated descriptor is.
    outdir = descriptor.dirname  # SAME

    # <list<ProtoInfo>> A list of ProtoInfo
    # deps = [dep.proto for dep in ctx.attr.deps]
    deps = [dep[ProtoInfo] for dep in node.attr.deps]  # DIFFERENT

    # <list<PluginInfo>> A list of PluginInfo
    plugins = [plugin[ProtoPluginInfo] for plugin in ctx.attr._plugins]  # ~~SAME~~ SLIGHTLY DIFFERENT

    # <list<File>> The list of .proto files that will exist in the 'staging
    # area'.  We copy them from their source location into place such that a
    # single '-I.' at the package root will satisfy all import paths.
    # protos = []
    protos = node.files.srcs  # DIFFERENT

    # <dict<string,File>> The set of .proto files to compile, used as the final
    # list of arguments to protoc.  This is a subset of the 'protos' list that
    # are directly specified in the proto_library deps, but excluding other
    # transitive .protos.  For example, even though we might transitively depend
    # on 'google/protobuf/any.proto', we don't necessarily want to actually
    # generate artifacts for it when compiling 'foo.proto'. Maintained as a dict
    # for set semantics.  The key is the value from File.path.
    targets = {}  # NEW - ONLY IN compile.bzl

    # <dict<string,File>> A mapping from plugin name to the plugin tool. Used to
    # generate the --plugin=protoc-gen-KEY=VALUE args
    plugin_tools = {}  # SAME DECL

    # <dict<string,<File> A mapping from PluginInfo.name to File.  In the case
    # of plugins that specify a single output 'archive' (like java), we gather
    # them in this dict.  It is used to generate args like
    # '--java_out=libjava.jar'.
    plugin_outfiles = {}  # SAME

    # <list<File>> The list of srcjars that we're generating (like
    # 'foo.srcjar').
    srcjars = []

    # <list<File>> The list of generated artifacts like 'foo_pb2.py' that we
    # expect to be produced.
    outputs = []

    # Additional data files from plugin.data needed by plugin tools that are not
    # single binaries.
    data = []

    ###
    ### Part 2: gather plugin.out artifacts
    ###

    # Some protoc plugins generate a set of output files (like python) while
    # others generate a single 'archive' file that contains the individual
    # outputs (like java).  This first loop is for the latter type.  In this
    # scenario, the PluginInfo.out attribute will exist; the predicted file
    # output location is relative to the package root, marked by the descriptor
    # file. Jar outputs are gathered as a special case as we need to
    # post-process them to have a 'srcjar' extension (java_library rules don't
    # accept source jars with a 'jar' extension)

    # SAME
    for plugin in plugins:
        if plugin.executable:
            plugin_tools[plugin.name] = plugin.executable
        data += plugin.data + get_plugin_runfiles(plugin.tool)

        filename = _get_plugin_out(ctx, plugin)
        if not filename:
            continue
        out = ctx.actions.declare_file(filename, sibling = descriptor)
        outputs.append(out)
        plugin_outfiles[plugin.name] = out
        if out.path.endswith(".jar"):
            srcjar = _copy_jar_to_srcjar(ctx, out)
            srcjars.append(srcjar)

    #
    # Parts 3a and 3b are skipped in the aspect impl
    #

    ###
    ### Part 3c: collect generated artifacts for all in the target list of protos to compile
    ###
    # for proto in protos:
    #     for plugin in plugins:
    #         outputs = get_plugin_outputs(ctx, descriptor, outputs, proto, plugin)
    # DIFFERENT (similar but this uses targets.items)
    # for src, proto in targets.items():
    #     for plugin in plugins:
    #         outputs = get_plugin_outputs(ctx, descriptor, outputs, src, proto, plugin)
    for proto in protos:
        for plugin in plugins:
            outputs = _get_plugin_outputs(ctx, descriptor, outputs, proto, plugin)

    #
    # This is present only in the aspect impl.
    #
    descriptor_sets = depset(
        direct = target.files.to_list(),
        transitive = [d.transitive_descriptor_sets for d in deps],
    )

    #
    # Only present in the aspect impl.
    #

    import_files = depset(
        direct = protos,
        transitive = [d.transitive_imports for d in deps],
    )

    # By default we have a single 'proto_path' argument at the 'staging area'
    # root.
    # list<string> argument list to construct
    args = []

    # This is commented out in the aspect impl but present in compile.bzl
    # args = ["--descriptor_set_out=%s" % descriptor.path]

    #
    # This part about using the descriptor set in is only present in the aspect
    # impl.
    #
    pathsep = ctx.configuration.host_path_separator
    args.append("--descriptor_set_in=%s" % pathsep.join(
        [f.path for f in descriptor_sets.to_list()],
    ))

    #
    # plugin_options only present in aspect impl
    #
    plugin_options = get_string_list_attr(ctx.attr, "plugin_options_string")

    # for plugin in plugins:
    #     args += [get_plugin_out_arg(ctx, outdir, plugin, plugin_outfiles)]

    # DIFFERENT: aspect impl also passes in the plugin_options argument
    for plugin in plugins:
        args += [get_plugin_out_arg(ctx, outdir, plugin, plugin_outfiles, plugin_options)]

    args += ["--plugin=protoc-gen-%s=%s" % (k, v.path) for k, v in plugin_tools.items()]  # SAME

    args += [_proto_path(f) for f in protos]

    mnemonic = "ProtoCompile"  # SAME

    command = " ".join([protoc.path] + args)  # SAME

    inputs = import_files.to_list() + descriptor_sets.to_list() + data
    tools = [protoc] + plugin_tools.values()

    # SAME
    if verbose > 0:
        print("%s: %s" % (mnemonic, command))
    if verbose > 1:
        command += " && echo '\n##### SANDBOX AFTER RUNNING PROTOC' && find . -type f "
    if verbose > 2:
        command = "echo '\n##### SANDBOX BEFORE RUNNING PROTOC' && find . -type l && " + command
    if verbose > 3:
        command = "env && " + command
        for f in outputs:
            print("EXPECTED OUTPUT:", f.path)
        print("INPUTS:", inputs)
        print("TOOLS:", tools)
        print("COMMAND:", command)
        for arg in args:
            print("ARG:", arg)

    ctx.actions.run_shell(
        mnemonic = mnemonic,  # SAME
        command = command,  # SAME

        # This is different!
        inputs = inputs,
        tools = tools,

        # outputs = outputs + [descriptor] + ctx.outputs.outputs, # compile.bzl
        outputs = outputs,
    )

    #
    # Gather transitive outputs
    #
    deps = [dep[ProtoLibraryAspectNodeInfo] for dep in node.attr.deps]
    for dep in deps:
        outputs += dep.outputs

    info = ProtoLibraryAspectNodeInfo(
        outputs = outputs,
    )

    return struct(
        proto_compile = info,
        providers = [info],
    )
