# This file contains the API that users interact with.  Everything in here should
# depend only on `brew()` calls.

"""
`brew(cmd::Cmd; no_stderr=false, no_stdout=false, verbose=false, force=false, quiet=false)`

Run command `cmd` using the configured brew binary, optionally suppressing
stdout and stderr, and providing flags such as `--verbose` to the brew binary.
"""
function brew(cmd::Cmd; no_stderr=false, no_stdout=false, verbose::Bool=false, force::Bool=false, quiet::Bool=false)
    cmd = add_flags(`$brew_exe $cmd`, Dict(`--verbose` => verbose, `--force` => force, `--quiet` => quiet))

    if no_stderr
        cmd = pipeline(cmd, stderr=devnull)
    end
    if no_stdout
        cmd = pipeline(cmd, stdout=devnull)
    end
    return run(cmd)
end

"""
`brewchomp(cmd::Cmd; no_stderr=false, no_stdout=false, verbose=false, force=false, quiet=false))`

Run command `cmd` using the configured brew binary, optionally suppressing
stdout and stderr, and providing flags such as `--verbose` to the brew binary.

This function uses `readchomp()`, as opposed to `brew()` which uses `run()`
"""
function brewchomp(cmd::Cmd; no_stderr=false, no_stdout=false, verbose::Bool=false, force::Bool=false, quiet::Bool=false)
    cmd = add_flags(`$brew_exe $cmd`, Dict(`--verbose` => verbose, `--force` => force, `--quiet` => quiet))

    if no_stderr
        cmd = pipeline(cmd, stderr=devnull)
    end
    if no_stdout
        cmd = pipeline(cmd, stdout=devnull)
    end
    return readchomp(cmd)
end

"""
`update(;verbose::Bool=false)`

Runs `brew update` to update Homebrew itself and all taps.  Then runs `upgrade()`
to upgrade all formulae that have fallen out of date.
"""
function update(;verbose::Bool=false)
    # Just run `brew update`
    brew(`update`; force=true, verbose=verbose)

    # Ensure we're on the right tag
    update_tag(;verbose=verbose)

    # Finally, upgrade outdated packages.
    upgrade(;verbose=verbose)
end

"""
`prefix()`

Returns `brew_prefix`, the location where all Homebrew files are stored.
"""
function prefix()
    return brew_prefix
end

"""
`prefix(pkg::Union{AbstractString,BrewPkg})`

Returns the prefix for a particular package's latest installed version.
"""
function prefix(pkg::StringOrPkg) end

function prefix(name::AbstractString)
    path, tap_path = formula_tap(name)
    return joinpath(brew_prefix, "Cellar", path, info(name).version)
end

function prefix(pkg::BrewPkg)
    prefix(pkg.name)
end

"""
`list()`

Returns a list of all installed packages as a `Vector{BrewPkg}`
"""
function list()
    # Get list of fully-qualified installed packages
    names = brewchomp(`list --full-name`)

    # If we've got something, then return info on all those names
    if !isempty(names)
        return info(split(names,"\n"))
    end
    return BrewPkg[]
end

"""
`outdated()`

Returns a list of all installed packages that are out of date as a `Vector{BrewPkg}`
"""
function outdated()
    json_str = brewchomp(`outdated --json=v1`)
    if isempty(json_str)
        return BrewPkg[]
    end
    brew_outdated = JSON.parse(json_str)

    outdated_pkgs = BrewPkg[info(pkg["name"]) for pkg in brew_outdated]
    return outdated_pkgs
end

"""
`refresh!(;verbose=false)`

Forcibly remove all packages and add them again.  This should only be used to
fix a broken installation, normal operation should never need to use this.
"""
function refresh!(;verbose=false)
    pkg_list = list()
    for pkg in pkg_list
        rm(pkg,verbose=verbose)
    end
    for pkg in pkg_list
        add(pkg,verbose=verbose)
    end
end

"""
`upgrade(;verbose::Bool=false)`

Iterate over all packages returned from `outdated()`, removing the old version
and adding a new one.  Note that we do not simply call `brew upgrade` here, as
we have special logic inside of `add()` to install from our tap before trying to
install from mainline Homebrew.
"""
function upgrade(;verbose::Bool=false)
    # We have to manually upgrade each package, as `brew upgrade` will pull from mxcl/master
    for pkg in outdated()
        rm(pkg; verbose=verbose)
        add(pkg; verbose=verbose)
    end
end

const json_cache = Dict{String,Dict{AbstractString,Any}}()
"""
`json(names::Vector{AbstractString})`

For each package name in `names`, return the full JSON object for `name`, the
result of `brew info --json=v1 \$name`, stored in a dictionary keyed by the names
passed into this function. If `brew info` fails, throws an error. If `brew info`
returns an empty object "[]", that object is represented by an empty dictionary.

Note that running `brew info --json=v1` is somewhat expensive, so we cache the
results in a global dictionary, and batching larger requests with this function
similarly increases performance.
"""
function json(names::Vector{T}) where {T <: AbstractString}
    # This is the dictionary of responses we'll return
    objs = Dict{String,Dict{AbstractString,Any}}()

    # Build list of names we have to ask for, eschewing asking for caching when we can
    ask_names = String[]
    for name in names
        if haskey(json_cache, name)
            objs[name] = json_cache[name]
        else
            push!(ask_names, name)
        end
    end

    # Now ask for all these names if we have any
    if !isempty(ask_names)
        # Tap the necessary tap for each name we're asking about, if there is one
        for name in ask_names
            path, tap_path = formula_tap(name)

            if !isempty(tap_path)
                tap(tap_path)
            end
        end
        try
            jdata = JSON.parse(brewchomp(Cmd(String["info", "--json=v1", ask_names...])))
            for idx in 1:length(jdata)
                json_cache[ask_names[idx]] = jdata[idx]
                objs[ask_names[idx]] = jdata[idx]
            end
        catch
            throw(ArgumentError("`brew info` failed for $(ask_names)!"))
        end
    end

    # Return these hard-won objects
    return objs
end

"""
`json(pkg::Union{AbstractString,BrewPkg})`

Return the full JSON object for `pkg`, the result of `brew info --json=v1 \$pkg`.
If `brew info` fails, throws an error.  If `brew info` returns an empty object,
(e.g. "[]"), this returns an empty Dict.

Note that running `brew info --json=v1` is somewhat expensive, so we cache the
results in a global dictionary, and batching larger requests with the vectorized
`json()` function similarly increases performance.
"""
function json(pkg::StringOrPkg) end

function json(name::AbstractString)
    return json([name])[name]
end

function json(pkg::BrewPkg)
    return json([fullname(pkg)])[fullname(pkg)]
end

"""
`info(names::Vector{String})`

For each name in `names`, returns information about that particular package name
as a BrewPkg.  This is our batched `String` -> `BrewPkg` converter.
"""
function info(names::Vector{T}) where {T <: AbstractString}
    # Get the JSON representations of all of these packages
    objs = json(names)

    infos = BrewPkg[]
    for name in names
        obj = objs[name]

        # First, get name and version
        obj_name = obj["name"]
        version = obj["versions"]["stable"]

        # Manually append the revision to the end of the version, as brew is wont to do
        if obj["revision"] > 0
            version *= "_$(obj["revision"])"
        end

        tap = dirname(obj["full_name"])
        if isempty(tap)
            tap = "Homebrew/core"
        end

        # Push that BrewPkg onto our infos object
        push!(infos, BrewPkg(obj_name, tap, version))
    end

    # Return the list of infos
    return infos
end

"""
`info(name::AbstractString)`

Returns information about a particular package name as a BrewPkg.  This is our
basic `String` -> `BrewPkg` converter.
"""
function info(name::AbstractString)
    return info([name])[1]
end

"""
`direct_deps(pkg::Union{AbstractString,BrewPkg}; build_deps::Bool=false)`

Return a list of all direct dependencies of `pkg` as a `Vector{BrewPkg}`
If `build_deps` is `true` include formula depependencies marked as `:build`.
"""
function direct_deps(pkg::StringOrPkg; build_deps::Bool=false) end

function direct_deps(name::AbstractString; build_deps::Bool=false)
    obj = json(name)

    # Iterate over all dependencies, removing optional and build dependencies
    dependencies = String[dep for dep in obj["dependencies"]]
    dependencies = filter(x -> !(x in obj["optional_dependencies"]), dependencies)

    if !build_deps
        dependencies = filter(x -> !(x in obj["build_dependencies"]), dependencies)
    end
    return info(dependencies)
end

function direct_deps(pkg::BrewPkg; build_deps::Bool=false)
    return direct_deps(fullname(pkg); build_deps=build_deps)
end

"""
`deps_tree(pkg::Union{AbstractString,BrewPkg}; build_deps::Bool=false)`

Return a dictionary mapping every dependency (both direct and indirect) of `pkg`
to a `Vector{BrewPkg}` of all of its dependencies.  Used in `deps_sorted()`.

If `build_deps` is `true` include formula depependencies marked as `:build`.
"""
function deps_tree(pkg::StringOrPkg; build_deps::Bool=false) end

function deps_tree(name::AbstractString; build_deps::Bool=false)
    # First, get all the knowledge we need about dependencies
    deptree = Dict{String,Vector{BrewPkg}}()

    pending_deps = direct_deps(name; build_deps=build_deps)
    completed_deps = Set(String[])
    while !isempty(pending_deps)
        # Temporarily move pending_deps over to curr_pending_deps
        curr_pending_deps = pending_deps
        pending_deps = BrewPkg[]

        # Iterate over these currently pending deps, adding new ones to pending_deps
        for pkg in curr_pending_deps
            deptree[fullname(pkg)] = direct_deps(pkg; build_deps=build_deps)
            push!(completed_deps, fullname(pkg))
            for dpkg in deptree[fullname(pkg)]
                if !(fullname(dpkg) in completed_deps)
                    push!(pending_deps, dpkg)
                end
            end
        end
    end

    return deptree
end

function deps_tree(pkg::BrewPkg; build_deps::Bool=false)
    return deps_tree(fullname(pkg); build_deps=build_deps)
end

"""
`insert_after_dependencies(tree::Dict, sorted_deps::Vector{BrewPkg}, name::AbstractString)`

Given a mapping from names to dependencies in `tree`, and a list of sorted
dependencies in `sorted_deps`, insert a new dependency `name` into `sorted_deps`
after all dependencies of `name`.  If a dependency of `name` is not already in
`sorted_deps`, then recursively add that dependency as well.
"""
function insert_after_dependencies(tree::Dict, sorted_deps::Vector{BrewPkg}, name::AbstractString)
    # First off, are we already in sorted_deps?  If so, back out!
    self_idx = findfirst(x -> (fullname(x) == name), sorted_deps)
    if self_idx != nothing
        return self_idx
    end

    # This is the index at which we will insert ourselves
    insert_idx = 1
    # Iterate over all dependencies
    for dpkg in tree[name]
        # Is this dependency already in the sorted_deps?
        idx = findfirst(x -> (fullname(x) == fullname(dpkg)), sorted_deps)

        # If the dependency is not already in this list, then recurse into it!
        if self_idx == nothing
            idx = insert_after_dependencies(tree, sorted_deps, fullname(dpkg))
        end

        # Otherwise, update insert_idx
        insert_idx = max(insert_idx, idx + 1)
    end

    # Finally, insert ourselves
    insert!(sorted_deps, insert_idx, info(name))
    return insert_idx
end

"""
`deps_sorted(pkg::Union{AbstractString,BrewPkg}; build_deps::Bool)`

Return a sorted `Vector{BrewPkg}` of all dependencies (direct and indirect) such
that each entry in the list appears after all of its own dependencies.

If `build_deps` is `true` include formula depependencies marked as `:build`.
"""
function deps_sorted(pkg::StringOrPkg; build_deps::Bool=false) end

function deps_sorted(name::AbstractString; build_deps::Bool=false)
    tree = deps_tree(name; build_deps=build_deps)
    sorted_deps = BrewPkg[]

    # For each package in the tree, insert it only after all of its dependencies
    # Just for aesthetic purposes, sort the keys by the number of dependencies
    # they have first, so that packages with few deps end up on top
    for name in sort(collect(keys(tree)), by=k-> length(tree[k]))
        insert_after_dependencies(tree, sorted_deps, name)
    end

    return sorted_deps
end

function deps_sorted(pkg::BrewPkg; build_deps::Bool=false)
    return deps_sorted(fullname(pkg); build_deps=build_deps)
end

"""
`add(pkg::Union{AbstractString,BrewPkg}; verbose::Bool=false, keep_translations::Bool=false)`

Install package `pkg` and all dependencies, using bottles only, unlinking any
previous versions if necessary, and linking the new ones in place. Will attempt
to install non-relocatable bottles from `Homebrew/core` by translating formulae
and forcing `cellar :any` into the formulae.

Automatically deletes all translated formulae before adding formulae and after,
unless `keep_translations` is set to `true`.
"""
function add(pkg::StringOrPkg; verbose::Bool=false, keep_translations::Bool=false) end

function add(name::AbstractString; verbose::Bool=false, keep_translations::Bool=false)
    # We do this so that things are as unambiguous and fresh as possible.
    # It's not a bad situation because translation is very fast.
    if !keep_translations
        delete_all_translated_formulae()
    end

    # Begin by translating all dependencies of `name`, including :build deps.
    # We need to translate :build deps so that we don't run into the diamond of death
    sorted_deps = AbstractString[]
    build_deps_only = AbstractString[]
    runtime_deps = [x.name for x in deps_sorted(name)]
    if verbose
        println("runtime_deps: $runtime_deps")
    end
    for dep in deps_sorted(name; build_deps=true)
        translated_dep = translate_formula(dep; verbose=verbose)

        # Collect the translated runtime_deps into sorted_deps
        if dep.name in runtime_deps
            push!(sorted_deps, translated_dep)
        else
            push!(build_deps_only, translated_dep)
        end
    end
    if verbose
        println("sorted_deps: $sorted_deps")
        println("build_deps only: $build_deps_only")
    end

    # Translate the actual formula we're interested in
    name = translate_formula(name; verbose=verbose)

    # Push `name` onto the end of `sorted_deps` so we have one list of things to install
    push!(sorted_deps, name)

    # Ensure that we are able to install relocatable bottles for every package
    non_relocatable = filter(x -> !has_relocatable_bottle(x), sorted_deps)

    if !isempty(non_relocatable)
        @warn("""
The following packages do not have relocatable bottles, installation may fail!
Please report these packages to https://github.com/JuliaLang/Homebrew.jl:
  $(join(non_relocatable, "\n  "))""")
    end

    # Get list of outdated packages and remove them all
    for dep in filter(pkg -> pkg.name in sorted_deps, Homebrew.outdated())
        unlink(dep; verbose=verbose)
    end

    # Install this package and all dependencies, in dependency order
    for dep in sorted_deps
        install_and_link(dep; verbose=verbose)
    end

    # Cleanup translated formula once we're done, unless asked not to
    if !keep_translations
        delete_all_translated_formulae()
    end
end

function add(pkg::BrewPkg; verbose::Bool=false, keep_translations::Bool=false)
    add(fullname(pkg); verbose=verbose, keep_translations=keep_translations)
end


"""
`install_and_link(pkg::Union{AbstractString,BrewPkg}; verbose=false)`

Installs, and links package `pkg`.  Used by `add()`.  Don't call manually
unless you really know what you're doing, as this doesn't deal with
dependencies, and so can trigger compilation when you don't want it to.
"""
function install_and_link(pkg::StringOrPkg; verbose::Bool=false) end

function install_and_link(name::AbstractString; verbose::Bool=false)
    # If we're already linked, don't sweat it.
    if linked(name)
        return
    end

    # Install dependency and link it
    brew(`install $name`; verbose=verbose)
    link(name; verbose=verbose)
end

function install_and_link(pkg::BrewPkg; verbose::Bool=false)
    return install_and_link(fullname(pkg); verbose=verbose)
end


"""
`postinstall(pkg::Union{AbstractString,BrewPkg}; verbose=false)`

Runs `brew postinstall` against package `pkg`, useful for debugging complicated
formulae when a bottle doesn't install right and you want to re-run postinstall.
"""
function postinstall(pkg::StringOrPkg; verbose::Bool=false) end

function postinstall(name::AbstractString; verbose::Bool=false)
    brew(`postinstall $name`, verbose=verbose)
end

function postinstall(pkg::BrewPkg; verbose::Bool=false)
    postinstall(fullname(pkg), verbose=verbose)
end


"""
`link(pkg::Union{AbstractString,BrewPkg}; verbose=false, force=true)`

Link package `name` into the global namespace, uses `--force` if `force == true`
"""
function link(name::StringOrPkg; verbose::Bool=false, force::Bool=true) end

function link(name::AbstractString; verbose::Bool=false, force::Bool=true)
    brew(`link $name`, no_stdout=true, verbose=verbose, force=force)
end

function link(pkg::BrewPkg; verbose::Bool=false, force::Bool=true)
    return link(fullname(pkg); force=force, verbose=verbose)
end


"""
`unlink(pkg::Union{AbstractString,BrewPkg}; verbose::Bool=false, quiet::Bool=true)`

Unlink package `pkg` from the global namespace, uses `--quiet` if `quiet == true`
"""
function unlink(name::StringOrPkg; verbose::Bool=false) end

function unlink(name::AbstractString; verbose::Bool=false)
    brew(`unlink $name`; verbose=verbose)
end

function unlink(pkg::BrewPkg; verbose::Bool=false)
    return unlink(fullname(pkg); verbose=verbose)
end


"""
`rm(pkg::Union{AbstractString,BrewPkg}; verbose::Bool=false, force::Bool=true)`

Remove package `pkg`, use `--force` if `force` == `true`
"""
function rm(pkg::StringOrPkg; verbose::Bool=false, force::Bool=false) end

function rm(pkg::AbstractString; verbose::Bool=false, force::Bool=true)
    brew(`rm $pkg`; verbose=verbose, force=force)
end

function rm(pkg::BrewPkg; verbose::Bool=false, force::Bool=true)
    return rm(fullname(pkg); verbose=verbose, force=force)
end

"""
`rm(pkgs::Vector{String or BrewPkg}; verbose::Bool=false, force::Bool=true)`

Remove packages `pkgs`, use `--force` if `force` == `true`
"""
function rm(pkgs::Vector{T}; verbose::Bool=false, force::Bool=false) where {T <: StringOrPkg}
    for pkg in pkgs
        try
            rm(pkg; verbose=verbose, force=force)
        catch
        end
    end
end

"""
`cleanup()`

Cleans up old installed versions of formulae, as well as purging all downloaded bottles
"""
function cleanup()
    brew(`cleanup -s`)
end


"""
`tap(tap_name::AbstractString; full::Bool=true, verbose::Bool=false)`

Runs `brew tap \$tap_name` if the tap does not already exist.  If `full` is `true`
adds the flag `--full` to clone a full tap instead of Homebrew's default shallow.

If `git` is not available, manually tap it with curl and tar.  This tap will be
unshallowed at the next `brew update` when `git` is available.
"""
function tap(tap_name::AbstractString; full::Bool=true, verbose::Bool=false)
    if !tap_exists(tap_name)
        # If we have no git available, then do it oldschool style
        if !git_installed()
            user = dirname(tap_name)
            repo = "homebrew-$(basename(tap_name))"
            tarball_url = "https://github.com/$user/$repo/tarball/master"
            tap_path = joinpath(brew_prefix,"Library","Taps", user, repo)

            if verbose
                @info("Manually tapping $tap_name...")
            end
            try
                mkpath(tap_path)
                run(pipeline(`curl -\# -L $tarball_url`, `tar xz -m --strip 1 -C $tap_path`))
            catch
                @warn("Could not download/extract $tarball_url into $(tap_path)!")
                rethrow()
            end
        else
            if full
                brew(`tap --full $tap_name`; verbose=verbose)
            else
                brew(`tap $tap_name`; verbose=verbose)
            end
        end
    end
end

const OSX_VERSION = [""]
function osx_version_string()
    global OSX_VERSION
    if isempty(OSX_VERSION[1])
        OSX_VERSION[1] = join(split(readchomp(`sw_vers -productVersion`), ".")[1:2],".")
    end
    return Dict(
        "10.4" => "tiger",
        "10.5" => "leopard",
        "10.6" => "snow_leopard",
        "10.7" => "lion",
        "10.8" => "mountain_lion",
        "10.9" => "mavericks",
        "10.10" => "yosemite",
        "10.11" => "el_capitan",
        "10.12" => "sierra",
        "10.13" => "high_sierra",
        "10.14" => "mojave",
        "10.15" => "catalina"
    )[OSX_VERSION[1]]
end

"""
`has_bottle(name::AbstractString)`

Checks if a given formula has a bottle at all
"""
function has_bottle(name::AbstractString)
    return haskey(json(name)["bottle"], "stable") &&
           haskey(json(name)["bottle"]["stable"]["files"], osx_version_string())
end

"""
`has_relocatable_bottle(name::AbstractString)`

Checks to see if a given formula has a bottle that can be installed anywhere
"""
function has_relocatable_bottle(name::AbstractString)
    if !has_bottle(name)
        return false
    end

    return json(name)["bottle"]["stable"]["cellar"] in [":any", ":any_skip_relocation"]
end

function versioninfo(;verbose=false)
    InteractiveUtils.versioninfo(stdout; verbose=verbose)
    run(Cmd(`git log -1 '--pretty=format:Homebrew git revision %h; last commit %cr'`; dir=joinpath(prefix())))
    run(Cmd(`git log -1 '--pretty=format:homebrew/core git revision %h; last commit %cr'`; dir=joinpath(prefix(), "Library", "Taps", "homebrew", "homebrew-core")))
    run(Cmd(`git log -1 '--pretty=format:staticfloat/juliadeps revision %h; last commit %cr'`; dir=joinpath(prefix(), "Library", "Taps", "staticfloat", "homebrew-juliadeps")))

    installed_pkgs = list()
    println("\n$(length(installed_pkgs)) total packages installed:")
    println(join([x.name for x in installed_pkgs], ", "))
end
