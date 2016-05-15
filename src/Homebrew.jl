module Homebrew

import Base: show
if VERSION >= v"0.3.0-" && VERSION < v"0.5.0-dev+522"
    import Base: Pkg.Git
elseif VERSION >= v"0.5.0-dev+522"
    import Base: LibGit2
else
    import Base: Git
end
using JSON
using Compat; import Compat.String

# Find homebrew installation prefix
const brew_prefix = abspath(joinpath(dirname(@__FILE__),"..","deps", "usr"))
const brew_exe = joinpath(brew_prefix,"bin","brew")
const tappath = joinpath(brew_prefix,"Library","Taps","staticfloat","homebrew-juliadeps")

const BREW_URL = "https://github.com/Homebrew/homebrew.git"
const BREW_BRANCH = "master"
const BOTTLE_SERVER = "https://juliabottles.s3.amazonaws.com"

const DL_LOAD_PATH = VERSION >= v"0.4.0-dev+3844" ? Libdl.DL_LOAD_PATH : Base.DL_LOAD_PATH

function init()
    # Let's see if Homebrew is installed.  If not, let's do that first!
    install_brew()

    # Update environment variables such as PATH, DL_LOAD_PATH, etc...
    update_env()
end

function brew(cmd::Cmd; no_stderr=false, no_stdout=false, verbose=false)
    if verbose
        cmd = `$brew_exe --verbose $cmd`
    else
        cmd = `$brew_exe $cmd`
    end
    if no_stderr
        @compat cmd = pipeline(cmd, stderr=DevNull)
    end
    if no_stdout
        @compat cmd = pipeline(cmd, stdout=DevNull)
    end
    return run(cmd)
end

function brewchomp(cmd::Cmd; no_stderr=false)
    cmd = `$brew_exe $cmd`
    if no_stderr
        @compat cmd = pipeline(cmd, stderr=DevNull)
    end
    return readchomp(cmd)
end

function install_brew()
    # Ensure brew_prefix exists
    mkpath(brew_prefix)

    # Make sure brew isn't already installed
    if !isfile( brew_exe )
        # Clone brew into brew_prefix
        Base.info("Cloning brew from $BREW_URL")
        if VERSION < v"0.5.0-dev+522"
            try Git.run(`clone $BREW_URL -b $BREW_BRANCH --depth 1 $brew_prefix`)
            catch
                warn("Could not clone $BREW_URL/$BREW_BRANCH into $brew_prefix!")
                rethrow()
            end
        else
            try repo = LibGit2.clone(BREW_URL, brew_prefix)
            catch
                warn("Could not clone $BREW_URL/$BREW_BRANCH into $brew_prefix!")
                rethrow()
            end
        end
    end

    # Make sure we're on the right repo.  If not, clear it out!
    if VERSION < v"0.5.0-dev+522"
        if Git.readchomp(`config remote.origin.url`, dir=brew_prefix) != BREW_URL
            Git.run(`config remote.origin.url $BREW_URL`, dir=brew_prefix)
            Git.run(`config remote.origin.fetch +refs/heads/master:refs/remotes/origin/master`, dir=brew_prefix)
            Git.run(`fetch origin`, dir=brew_prefix)
            Git.run(`reset --hard origin/$BREW_BRANCH`, dir=brew_prefix)
        end
    else
        repo = LibGit2.GitRepo(brew_prefix)
        remote = LibGit2.get(LibGit2.GitRemote, repo, "origin")
        if LibGit2.url(remote) != BREW_URL
            config = LibGit2.GitConfig(repo)
            LibGit2.set!(config,"remote.origin.url",BREW_URL)
            LibGit2.set!(config,"remote.origin.fetch","+refs/heads/master:refs/remotes/origin/master")
            LibGit2.fetch(remote,LibGit2.fetch_refspecs(remote))
            MASTER_BRANCH = LibG.revparse(repo, "origin/$BREW_BRANCH")
            LibGit2.reset!(repo, MASTER_BRANCH, LibGit2.RESET_HARD)
        end
    end

    # Remove old tappath if it exists
    old_tappath = joinpath(brew_prefix,"Library","Taps","staticfloat-juliadeps")
    if isdir(old_tappath)
        if VERSION >= v"0.3.0-rc1"
            Base.rm(old_tappath, recursive=true)
        else
            run(`rm -rf $(old_tappath)`)
        end
        brew(`prune`)
    end


    if !isfile(joinpath(brew_prefix,"bin","otool"))
        # Download/install packaged install_name_tools
        try
            @compat run(pipeline(`curl --location $BOTTLE_SERVER/cctools_bundle.tar.gz`,
                                 `tar xz -C $(joinpath(brew_prefix,"bin"))`))
        catch
            warn("Could not download/extract $BOTTLE_SERVER/cctools_bundle.tar.gz into $(joinpath(brew_prefix,"bin"))!")
            rethrow()
        end
    end

    if !isdir(tappath)
        # Tap staticfloat/juliadeps
        try
            brew(`tap staticfloat/juliadeps`)
        catch
            warn( "Could not tap staticfloat/juliadeps!" )
            rethrow()
        end
    end
end

if VERSION < v"0.5.0-dev+522"
    function update()
        Git.run(`fetch origin`, dir=brew_prefix)
        Git.run(`reset --hard origin/$BREW_BRANCH`, dir=brew_prefix)

        # Find all namespaces inside <prefix>/Library/Taps, then search for taps
        tapsdir = joinpath(brew_prefix,"Library","Taps")
        namespaces = readdir(tapsdir)
        ns_taps = [[joinpath(tapsdir, ns, tap) for tap in readdir(joinpath(tapsdir, ns))] for ns in namespaces]
        taps = vcat(ns_taps...)

        # Update each tap, one after another
        for tap in taps
            println("Updating tap $(basename(tap))")
            Git.run(`fetch origin`, dir=tap)
            TAP_BRANCH = Git.readchomp(`rev-parse --abbrev-ref HEAD`, dir=tap)
            Git.run(`reset --hard origin/$TAP_BRANCH`, dir=tap)
        end

        # Finally, upgrade outdated packages.
        upgrade()
    end
else
    function update()
        repo = LibGit2.GitRepo(brew_prefix)
        remote = LibGit2.get(LibGit2.GitRemote, repo, "origin")
        
        tapsdir = joinpath(brew_prefix,"Library","Taps")
        namespaces = readdir(tapsdir)
        ns_taps = [[joinpath(tapsdir, ns, tap) for tap in readdir(joinpath(tapsdir, ns))] for ns in namespaces]
        taps = vcat(ns_taps...)

        # Update each tap, one after another
        for tap in taps
            println("Updating tap $(basename(tap))")
            LibGit2.fetch(remote,[BREW_BRANCH])
            TAP_BRANCH = LibGit2.revparseid(repo, tappath)
            LibGit2.reset!(repo, TAP_BRANCH, LibGit2.Consts.RESET_HARD)
        end
        upgrade()
    end
end

# Update environment variables so we can natively call brew, otool, etc...
function update_env()
    if length(Base.search(ENV["PATH"], joinpath(brew_prefix, "bin"))) == 0
        ENV["PATH"] = "$(realpath(joinpath(brew_prefix, "bin"))):$(joinpath(brew_prefix, "sbin")):$(ENV["PATH"])"
    end

    if !(joinpath(brew_prefix,"lib") in DL_LOAD_PATH)
        push!(DL_LOAD_PATH, joinpath(brew_prefix, "lib") )
    end

    # We need to set our own, private, cache directory so that we don't conflict with
    # user-maintained Homebrew installations, and multiple users can use it at once
    ENV["HOMEBREW_CACHE"] = joinpath(ENV["HOME"],"Library/Caches/Homebrew.jl/")
    return
end

immutable BrewPkg
    name::String
    version::VersionNumber
    version_str::String
    bottled::Bool
    cellar::String

    BrewPkg(n, v, vs, b) = new(n, v, vs, b)
end

function show(io::IO, b::BrewPkg)
    write(io, "$(b.name): $(b.version) $(b.bottled ? "(bottled)" : "")")
end

function prefix()
    brew_prefix
end

# Get the prefix of a given package's latest version
function prefix(name::AbstractString)
    cellar_path = joinpath(brew_prefix, "Cellar", name)
    version_str = info(name).version_str
    return joinpath(brew_prefix, "Cellar", name, version_str)
end

# If we pass in a BrewPkg, just sub out to running it on the name
function prefix(pkg::BrewPkg)
    prefix(pkg.name)
end

# Convert brew's much more lax versioning into something that we can handle
function make_version(name::AbstractString, vers_str::AbstractString)
    # Most of the time we fail due to weird stuff at the end; let's cut it off until it works!
    failing = true
    vers = nothing
    idx = length(vers_str)
    while failing && idx > 0
        try
            vers = convert(VersionNumber, vers_str[1:idx])
            failing = false
        catch
            idx -= 1
        end
    end

    if idx != 0
        # If there's some that we chopped off, see how much we can restore via +
        if idx < length(vers_str)
            idx_add = idx+2
            passing = true
            while passing && idx_add <= length(vers_str)
                try
                    vers = convert(VersionNumber, "$(vers_str[1:idx])+$(vers_str[idx+2:idx_add])")
                    idx_add += 1
                catch
                    passing = false
                end
            end
        end
    else
        # Special-case things we know how to deal with here
        if name == "x264"
            vers = convert(VersionNumber, vers_str[2:end])
        else
            warn("Brew is feeding us a weird version string for $(name): $(vers_str)")
            warn("Please report this at https://github.com/JuliaLang/Homebrew.jl")
            vers = v"1.0"
        end
    end

    return vers
end

# List all installed packages as a list of BrewPkg items
function list()
    brew_list = brewchomp(`list --versions`)
    if length(brew_list) != 0
        pkgs = BrewPkg[]
        for f in split(brew_list,"\n")
            name = split(f, " ")[1]
            vers = make_version(name, split(f, " ")[2])
            vers_str = split(f, " ")[2]
            push!(pkgs, BrewPkg(name, vers, vers_str, false))
        end
        return pkgs
    else
        BrewPkg[]
    end
end

function find(name::String, pkgs::Vector{BrewPkg})
    for p in pkgs
        if p.name == name
            return p
        end
    end
    return nothing
end

# List all outdated packages as a list of BrewPkg's
function outdated()
    outdated_pkgs = BrewPkg[]
    brew_outdated = brewchomp(`outdated`)
    if length(brew_outdated) == 0
        return outdated_pkgs
    end

    installed_packages = list()

    # For each package that brew outdated gives us
    for f in split(brew_outdated,"\n")
        # Get information about it
        pkg = info(f)

        # Check it against each package we have installed
        inst_pkg = find(pkg.name, installed_packages)

        # If this package isn't installed, or is and is actually a lower version
        if inst_pkg == nothing || (inst_pkg.version < pkg.version)
            push!(outdated_pkgs, pkg)
        end
    end
    return outdated_pkgs
end

# Forcibly go through, uninstalling and reinstalling every package we have.
function refresh(;verbose=false)
    pkg_list = list()
    for pkg in pkg_list
        rm(pkg,verbose=verbose)
    end
    for pkg in pkg_list
        add(pkg,verbose=verbose)
    end
end

function upgrade()
    # We have to manually upgrade each package, as `brew upgrade` will pull from mxcl/master
    for pkg in outdated()
        rm(pkg)
        add(pkg)
    end
end

# Get info for a specific package
function info(pkg::AbstractString)
    json_str = ""

    # Auto-detect whether we should add staticfloat/juliadeps/ to the front of this pkg
    cd(tappath) do
        if isfile("$pkg.rb")
            pkg = "staticfloat/juliadeps/$pkg"
        end
    end

    # Does our pkg perhaps need a tap?
    pkgtap = dirname(pkg)

    # If so, let's ensure it's tapped
    if !isempty(pkgtap)
        pkg_tappath = joinpath(brew_prefix,"Library","Taps",dirname(pkgtap), "homebrew-$(basename(pkgtap))")
        if !isdir(pkg_tappath)
            brew(`tap $pkgtap`)
        end
    end

    try
        json_str = brewchomp(`info --json=v1 $pkg`)
    catch
        throw(ArgumentError("Cannot find formula for $(pkg)!"))
    end

    if length(json_str) != 0
        obj = JSON.parse(json_str)

        if length(obj) != 0
            obj = obj[1]
            # First, get name and version
            name = obj["name"]
            version = make_version(name, obj["versions"]["stable"])
            version_str = obj["versions"]["stable"]
            if obj["revision"] > 0
                version_str *= "_$(obj["revision"])"
            end
            bottled = obj["versions"]["bottle"]

            # If we actually have a keg, return whether it was poured
            if !isempty(obj["installed"])
                bottled = obj["installed"][1]["poured_from_bottle"]
            end

            # Then, return a BrewPkg!
            return BrewPkg(name, version, version_str, bottled)
        else
            throw(ArgumentError("Cannot parse info for $(pkg)!"))
        end
    else
        throw(ArgumentError("brew didn't give us any info for $(pkg)!"))
    end
end

# Install a package
function add(pkg::AbstractString; verbose=false)
    cd(tappath) do
        # First, unlink any previous versions of this package
        if linked( pkg )
            brew(`unlink --quiet $pkg`, verbose=verbose)
        end
        # If we've got it in our tap, install it
        if isfile( "$pkg.rb" )
            brew(`install --force-bottle staticfloat/juliadeps/$pkg`, verbose=verbose)
        else
            # If not, try to install it from Homebrew
            brew(`install --force-bottle $pkg`, verbose=verbose)
        end

        # Finally, if we need to, link it in
        brew(`link --force $pkg`, no_stdout=true, verbose=verbose)
    end
end

function add(pkg::BrewPkg; verbose=false)
    add(pkg.name, verbose=verbose)
end

function postinstall(pkg::AbstractString; verbose=false)
    brew(`postinstall $pkg`, verbose=verbose)
end

function postinstall(pkg::BrewPkg; verbose=false)
    postinstall(pkg.name, verbose=verbose)
end

function installed(pkg::AbstractString)
    isdir(joinpath(brew_prefix,"Cellar",pkg))
end

function installed(pkg::BrewPkg)
    installed(pkg.name)
end

function linked(pkg::AbstractString)
    return islink(joinpath(brew_prefix,"Library","LinkedKegs",pkg))
end

function linked(pkg::BrewPkg)
    return linked(pkg.name)
end

function rm(pkg::AbstractString; verbose=false)
    brew(`rm --force $pkg`, verbose=verbose)
end

function rm(pkg::BrewPkg; verbose=false)
    rm(pkg.name, verbose=verbose)
end

# Include our own, personal bindeps integration stuff
include("bindeps_integration.jl")

init()
end # module
